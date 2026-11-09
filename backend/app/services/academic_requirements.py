"""Versioned administrator documents with typed content and explicit catalog references."""

from datetime import UTC, datetime
from uuid import uuid4

from pydantic import TypeAdapter
from sqlalchemy import delete, func, select

from app.core.auth_errors import conflict
from app.models.academic import GraduationRule
from app.models.academic_workspace import (
    AcademicCurriculumRevision,
    AcademicRequirementDepartmentRef,
    AcademicRequirementNodeRef,
    AcademicRequirementRevision,
    AcademicRequirementTrackRef,
)
from app.schemas import academic_requirements as dto
from app.schemas.academic_workspace import AcademicScope, AcademicScopeClause
from app.services import academic
from app.services import academic_curricula as curricula
from app.services.academic_workspace import digest, invalid, mutate, require_school, scoped_record

CONTENT = TypeAdapter(dto.Content)


def view(db, revision):
    db.flush()
    return dto.RequirementView(
        **dto.RequirementHeader.model_validate(revision).model_dump(),
        scope=AcademicScope.model_validate(revision.scope_json),
        content=CONTENT.validate_python(revision.content_json),
    ).model_dump(mode="json")


def listing(db, identity, institution_id, kind, cursor, limit):
    require_school(db, identity, institution_id)
    statement = select(AcademicRequirementRevision).where(
        AcademicRequirementRevision.institution_id == institution_id
    )
    if kind:
        statement = statement.where(AcademicRequirementRevision.kind == kind)
    if cursor:
        statement = statement.where(AcademicRequirementRevision.id > cursor)
    rows = list(db.scalars(statement.order_by(AcademicRequirementRevision.id).limit(limit + 1)))
    return {"items": rows[:limit], "next_cursor": rows[limit - 1].id if len(rows) > limit else None}


def resolve_context(db, identity, school, classification_id, curriculum_id):
    if curriculum_id:
        curriculum = scoped_record(db, identity, AcademicCurriculumRevision, curriculum_id)
        if curriculum.institution_id != school or curriculum.status != "published":
            invalid("curriculum_revision_id", "Choose a published curriculum from this school")
        if classification_id and classification_id != curriculum.classification_revision_id:
            invalid("classification_revision_id", "Use the curriculum classification revision")
        classification_id = curriculum.classification_revision_id
    if classification_id:
        curricula.classification(db, identity, classification_id, school)
    return classification_id


def scopes_in(content):
    for node in dto.content_nodes(content):
        scope = getattr(node, "scope", None)
        if scope is not None:
            yield scope


def references(db, identity, revision, scope, content, classification_id):
    departments, tracks = curricula.validate_scope(db, identity, revision.institution_id, scope)
    for local in scopes_in(content):
        deps, paths = curricula.validate_scope(db, identity, revision.institution_id, local)
        departments |= deps
        tracks |= paths
    classification_nodes = set()
    if isinstance(content, dto.CreditContent):
        classification_nodes = {
            h.classification_node_id for h in content.headers if h.classification_node_id
        }
        if classification_nodes:
            if classification_id is None:
                invalid(
                    "classification_revision_id",
                    "Select the school classification before mapping columns",
                )
            available = curricula.nodes_for(db, classification_id)
            if not classification_nodes.issubset(available):
                invalid("content.headers", "Use classification nodes from this revision")
    return departments, tracks, classification_nodes


def store_references(db, revision, refs):
    departments, tracks, nodes = refs
    for model in (
        AcademicRequirementDepartmentRef,
        AcademicRequirementTrackRef,
        AcademicRequirementNodeRef,
    ):
        db.execute(delete(model).where(model.requirement_revision_id == revision.id))
    for model, key, values in [
        (AcademicRequirementDepartmentRef, "department_id", departments),
        (AcademicRequirementTrackRef, "track_id", tracks),
        (AcademicRequirementNodeRef, "node_id", nodes),
    ]:
        for value in values:
            extra = (
                {"classification_revision_id": revision.classification_revision_id}
                if model is AcademicRequirementNodeRef
                else {}
            )
            db.add(
                model(
                    requirement_revision_id=revision.id,
                    institution_id=revision.institution_id,
                    **{key: value},
                    **extra,
                )
            )


def create(db, request, payload):
    def action(identity):
        classification_id = resolve_context(
            db,
            identity,
            payload.institution_id,
            payload.classification_revision_id,
            payload.curriculum_revision_id,
        )
        content = CONTENT.validate_python({"kind": payload.kind})
        scope = AcademicScope()
        legacy = None
        if payload.legacy_rule_id:
            if payload.kind != "checklist":
                invalid("legacy_rule_id", "Legacy descriptions are imported into a checklist")
            legacy = scoped_record(db, identity, GraduationRule, payload.legacy_rule_id)
            if legacy.institution_id != payload.institution_id:
                invalid("legacy_rule_id", "Use a rule from this school")
            content = dto.ChecklistContent(
                kind="checklist", lines=[dto.ChecklistLine(text=legacy.definition)]
            )
            scope = AcademicScope(clauses=[AcademicScopeClause(department_id=legacy.department_id)])
        effective_from = payload.effective_from or (legacy.effective_from if legacy else None)
        effective_to = payload.effective_to or (legacy.effective_to if legacy else None)
        if effective_from and effective_to and effective_from > effective_to:
            invalid("effective_to", "Effective dates are reversed")
        revision = AcademicRequirementRevision(
            institution_id=payload.institution_id,
            lineage_id=uuid4(),
            revision=1,
            name=payload.name,
            kind=payload.kind,
            scope_json=scope.model_dump(mode="json"),
            content_json=content.model_dump(mode="json"),
            classification_revision_id=classification_id,
            curriculum_revision_id=payload.curriculum_revision_id,
            legacy_rule_id=legacy.id if legacy else None,
            legacy_rule_version=legacy.version if legacy else None,
            effective_from=effective_from,
            effective_to=effective_to,
            created_by=identity.user.id,
            updated_by=identity.user.id,
        )
        db.add(revision)
        db.flush()
        store_references(
            db, revision, references(db, identity, revision, scope, content, classification_id)
        )
        return view(db, revision)

    return mutate(db, request, payload.institution_id, payload, "requirement_create", action)


def replace(db, request, identity, record_id, payload):
    revision = scoped_record(db, identity, AcademicRequirementRevision, record_id)

    def action(actor):
        if revision.status != "draft" or revision.version != payload.expected_version:
            raise conflict()
        if payload.content.kind != revision.kind:
            invalid("content.kind", "A document cannot change its kind")
        classification_id = resolve_context(
            db,
            actor,
            revision.institution_id,
            payload.classification_revision_id,
            payload.curriculum_revision_id,
        )
        refs = references(db, actor, revision, payload.scope, payload.content, classification_id)
        # Remove reference rows before changing the aggregate's pinned classification.
        for model in (
            AcademicRequirementDepartmentRef,
            AcademicRequirementTrackRef,
            AcademicRequirementNodeRef,
        ):
            db.execute(delete(model).where(model.requirement_revision_id == revision.id))
        revision.name = payload.name
        revision.scope_json = payload.scope.model_dump(mode="json")
        revision.content_json = payload.content.model_dump(mode="json")
        revision.classification_revision_id = classification_id
        revision.curriculum_revision_id = payload.curriculum_revision_id
        revision.effective_from = payload.effective_from
        revision.effective_to = payload.effective_to
        revision.version += 1
        revision.updated_by = actor.user.id
        revision.updated_at = datetime.now(UTC)
        db.flush()
        store_references(db, revision, refs)
        return view(db, revision)

    return mutate(
        db, request, revision.institution_id, payload, f"requirement_replace:{record_id}", action
    )


def scope_intersection(first, second):
    clauses = []
    unique = set()
    for a in first.clauses:
        for b in second.clauses:
            if a.department_id and b.department_id and a.department_id != b.department_id:
                continue
            start, end = (
                max(a.admission_from or 1000, b.admission_from or 1000),
                min(a.admission_to or 9999, b.admission_to or 9999),
            )
            if start > end:
                continue
            selected = a.track_mode == "selected" or b.track_mode == "selected"
            if a.track_mode == b.track_mode == "selected":
                tracks = set(a.track_ids) & set(b.track_ids)
            else:
                tracks = set(a.track_ids or b.track_ids)
            if selected and not tracks:
                continue
            key = (
                a.department_id or b.department_id,
                start,
                end,
                selected,
                tuple(sorted(tracks, key=str)),
            )
            if key in unique:
                continue
            unique.add(key)
            if len(unique) > 100:
                invalid("scope", "Reduce overlapping scope combinations to at most one hundred")
            clauses.append(
                AcademicScopeClause(
                    department_id=a.department_id or b.department_id,
                    admission_from=start,
                    admission_to=end,
                    track_mode="selected" if selected else "all",
                    track_ids=sorted(tracks, key=str),
                )
            )
    return AcademicScope(clauses=clauses)


def publication_issues(content, scope):
    issues = []
    if not scope.clauses:
        issues.append("적용 대상을 하나 이상 지정하세요.")

    def check_scope(local, parent):
        effective = scope_intersection(parent, local) if local is not None else parent
        if not effective.clauses:
            issues.append("하위 요건의 적용 대상이 공통 적용 대상과 겹치지 않습니다.")
        return effective

    if isinstance(content, dto.ChecklistContent):
        if not content.lines:
            issues.append("한 줄 요건을 하나 이상 작성하세요.")
        for line in content.lines:
            if not line.text.strip():
                issues.append("빈 요건 문장을 입력하거나 제거하세요.")
            check_scope(line.scope, scope)
    elif isinstance(content, dto.CertificationContent):
        if not content.groups:
            issues.append("인증 요건의 영역을 하나 이상 작성하세요.")

        def check_groups(groups, parent):
            for group in groups:
                effective = check_scope(group.scope, parent)
                count = len(group.items) + len(group.groups)
                if not group.label.strip() or count == 0:
                    issues.append("인증 영역의 이름과 기준을 작성하세요.")
                if group.choice == "pickN" and (
                    group.pick_count is None or not 1 <= group.pick_count <= count
                ):
                    issues.append("택 N의 개수를 기준과 하위 영역 개수 안에서 지정하세요.")
                for item in group.items:
                    if not item.label.strip():
                        issues.append("인증 기준을 입력하거나 제거하세요.")
                    check_scope(item.scope, effective)
                if any(not text.strip() for text in group.exemptions):
                    issues.append("면제 설명을 작성하거나 빈 항목을 제거하세요.")
                check_groups(group.groups, effective)

        check_groups(content.groups, scope)
    else:
        if not content.headers or not content.rows:
            issues.append("학점표의 열과 행을 작성하세요.")
        parents = {h.parent_id for h in content.headers if h.parent_id}
        for header in content.headers:
            if not header.label.strip():
                issues.append("학점표 열 이름을 입력하세요.")
            if (header.role == "group") != (header.id in parents):
                issues.append("열 묶음은 하위 열을 가지며 숫자 열은 잎 열이어야 합니다.")
        for row in content.rows:
            if not row.label.strip():
                issues.append("학점표 행 이름을 입력하세요.")
            check_scope(row.scope, scope)
    return list(dict.fromkeys(issues))


def preview(db, identity, record_id, payload):
    revision = scoped_record(db, identity, AcademicRequirementRevision, record_id)
    if revision.status != "draft" or revision.version != payload.expected_version:
        raise conflict()
    content = CONTENT.validate_python(revision.content_json)
    scope = AcademicScope.model_validate(revision.scope_json)
    resolve_context(
        db,
        identity,
        revision.institution_id,
        revision.classification_revision_id,
        revision.curriculum_revision_id,
    )
    references(db, identity, revision, scope, content, revision.classification_revision_id)
    if revision.curriculum_revision_id:
        curriculum = db.get(AcademicCurriculumRevision, revision.curriculum_revision_id)
        scope = scope_intersection(scope, AcademicScope.model_validate(curriculum.scope_json))
    return {
        "id": revision.id,
        "version": revision.version,
        "digest": digest(view(db, revision)),
        "issues": publication_issues(content, scope),
    }


def publish(db, request, identity, record_id, payload):
    revision = scoped_record(db, identity, AcademicRequirementRevision, record_id)

    def action(actor):
        result = preview(db, actor, record_id, payload)
        if result["issues"] or result["digest"] != payload.expected_digest:
            raise academic.failure("미완성 항목 또는 변경된 내용을 다시 확인하세요.")
        revision.status = "published"
        revision.published_at = datetime.now(UTC)
        revision.published_by = actor.user.id
        revision.digest = payload.expected_digest
        revision.review_note = payload.review_note
        revision.version += 1
        revision.updated_by = actor.user.id
        revision.updated_at = datetime.now(UTC)
        return view(db, revision)

    return mutate(
        db, request, revision.institution_id, payload, f"requirement_publish:{record_id}", action
    )


def copy_revision(db, request, identity, record_id, payload):
    source = scoped_record(db, identity, AcademicRequirementRevision, record_id)

    def action(actor):
        if source.version != payload.expected_version or source.status != "published":
            raise conflict()
        if db.scalar(
            select(AcademicRequirementRevision.id).where(
                AcademicRequirementRevision.lineage_id == source.lineage_id,
                AcademicRequirementRevision.status == "draft",
            )
        ):
            raise academic.failure("작성 중인 졸업요건 초안이 있습니다.")
        last = db.scalar(
            select(func.max(AcademicRequirementRevision.revision)).where(
                AcademicRequirementRevision.lineage_id == source.lineage_id
            )
        )
        revision = AcademicRequirementRevision(
            institution_id=source.institution_id,
            lineage_id=source.lineage_id,
            revision=last + 1,
            name=source.name,
            kind=source.kind,
            classification_revision_id=source.classification_revision_id,
            curriculum_revision_id=source.curriculum_revision_id,
            legacy_rule_id=source.legacy_rule_id,
            legacy_rule_version=source.legacy_rule_version,
            scope_json=source.scope_json,
            content_json=source.content_json,
            effective_from=source.effective_from,
            effective_to=source.effective_to,
            created_by=actor.user.id,
            updated_by=actor.user.id,
        )
        db.add(revision)
        db.flush()
        for model, key in [
            (AcademicRequirementDepartmentRef, "department_id"),
            (AcademicRequirementTrackRef, "track_id"),
            (AcademicRequirementNodeRef, "node_id"),
        ]:
            for ref in db.scalars(select(model).where(model.requirement_revision_id == source.id)):
                extra = (
                    {"classification_revision_id": source.classification_revision_id}
                    if model is AcademicRequirementNodeRef
                    else {}
                )
                db.add(
                    model(
                        requirement_revision_id=revision.id,
                        institution_id=source.institution_id,
                        **{key: getattr(ref, key)},
                        **extra,
                    )
                )
        from app.services.academic_credit_bindings import copy_data

        copy_data(db, source, revision, actor)
        return view(db, revision)

    return mutate(
        db, request, source.institution_id, payload, f"requirement_copy:{record_id}", action
    )


def withdraw(db, request, identity, record_id, payload):
    revision = scoped_record(db, identity, AcademicRequirementRevision, record_id)

    def action(actor):
        if revision.status != "published" or revision.version != payload.expected_version:
            raise conflict()
        revision.status = "withdrawn"
        revision.withdrawn_at = datetime.now(UTC)
        revision.withdrawal_reason = payload.reason
        revision.version += 1
        revision.updated_by = actor.user.id
        revision.updated_at = datetime.now(UTC)
        return view(db, revision)

    return mutate(
        db, request, revision.institution_id, payload, f"requirement_withdraw:{record_id}", action
    )
