"""Owner-only school requirements, explicit activation and self-reported responses."""

import copy
from datetime import UTC, datetime
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from app.core.auth_errors import conflict
from app.models.academic import Department
from app.models.academic_workspace import (
    AcademicCurriculumCourse,
    AcademicCurriculumRevision,
    AcademicRequirementRevision,
    ClassificationNode,
    StudyTrack,
)
from app.models.identity import Institution
from app.models.student_academic import (
    StudentAcademicActivation as Activation,
)
from app.models.student_academic import (
    StudentAcademicContext as Context,
)
from app.models.student_academic import (
    StudentAcademicCourseLink as CourseLink,
)
from app.models.student_academic import (
    StudentAcademicDocument as Document,
)
from app.models.student_academic import (
    StudentAcademicReceipt as Receipt,
)
from app.models.student_academic import (
    StudentAcademicResponse as Response,
)
from app.models.student_academic import (
    StudentAcademicWorkspace as Workspace,
)
from app.schemas import student_academic as dto
from app.schemas.academic_workspace import AcademicCurriculumCourseView
from app.services import access, personal
from app.services.academic_workspace import digest, invalid


def rows(db, model, owner):
    return list(db.scalars(select(model).where(model.owner_id == owner)))


def contexts(db, owner):
    return sorted((r for r in rows(db, Context, owner) if r.active), key=lambda c: c.position)


def scope_matches(scope, context):
    if scope is None:
        return True
    return any(
        (not c.get("department_id") or str(c["department_id"]) == str(context["department_id"]))
        and (
            c.get("admission_from") is None
            or c["admission_from"] <= context["admission_year"] <= c["admission_to"]
        )
        and (
            c.get("track_mode", "all") == "all"
            or str(context["track_id"]) in [str(t) for t in c["track_ids"]]
        )
        for c in scope.get("clauses", [])
    )


def context_data(row):
    return {
        key: str(getattr(row, key)) if key.endswith("_id") or key == "id" else getattr(row, key)
        for key in (
            "id",
            "institution_id",
            "department_id",
            "track_id",
            "curriculum_revision_id",
            "admission_year",
            "primary",
        )
    }


def profile_signature(db, owner):
    p = personal.profile(db, owner)
    return {
        k: str(p[k]) if p[k] is not None else None
        for k in ("institution_id", "department_id", "admission_year")
    }


def context_digest(db, owner):
    return digest(
        {
            "profile": profile_signature(db, owner),
            "contexts": [context_data(c) for c in contexts(db, owner)],
        }
    )


def workspace(db, owner, create=False):
    state = db.get(Workspace, owner)
    if state is None and create:
        state = Workspace(owner_id=owner, version=0)
        db.add(state)
        db.flush()
    return state


def context_issues(db, owner):
    p = personal.profile(db, owner)
    issues = []
    school = db.get(Institution, p["institution_id"]) if p["institution_id"] else None
    if (
        school is None
        or school.deleted_at is not None
        or not p["department_id"]
        or not p["admission_year"]
    ):
        issues.append("profile_incomplete")
    values = contexts(db, owner)
    if not values:
        issues.append("contexts_required")
    for c in values:
        if c.institution_id != p["institution_id"] or (
            c.primary and c.department_id != p["department_id"]
        ):
            issues.append("profile_context_changed")
        curriculum = db.get(AcademicCurriculumRevision, c.curriculum_revision_id)
        if curriculum.status != "published":
            issues.append("curriculum_unavailable")
        if not scope_matches(curriculum.scope_json, context_data(c)):
            issues.append("context_outside_curriculum")
    return list(dict.fromkeys(issues))


def context_view(db, c):
    curriculum = db.get(AcademicCurriculumRevision, c.curriculum_revision_id)
    return {
        **context_data(c),
        "department_name": db.get(Department, c.department_id).name,
        "track_name": db.get(StudyTrack, c.track_id).name,
        "curriculum_name": curriculum.name,
        "curriculum_revision": curriculum.revision,
        "courses": [
            {
                **AcademicCurriculumCourseView.model_validate(e).model_dump(mode="json"),
                "classification_label": classification_label(db, e.classification_node_id),
            }
            for e in db.scalars(
                select(AcademicCurriculumCourse)
                .where(AcademicCurriculumCourse.curriculum_revision_id == c.curriculum_revision_id)
                .order_by(AcademicCurriculumCourse.position)
            )
        ],
    }


def classification_label(db, node_id):
    labels, seen = [], set()
    while node_id and node_id not in seen:
        seen.add(node_id)
        node = db.get(ClassificationNode, node_id)
        labels.insert(0, node.label)
        node_id = node.parent_id
    return " / ".join(labels)


def read_contexts(db, owner):
    state = workspace(db, owner)
    return {
        "owner_id": str(owner),
        "version": state.version if state else 0,
        "institution_id": personal.profile(db, owner)["institution_id"],
        "contexts": [context_view(db, c) for c in contexts(db, owner)],
        "issues": context_issues(db, owner),
    }


def options(db, institution_id):
    school = db.get(Institution, institution_id)
    if school is None or school.deleted_at is not None:
        raise personal.missing()
    return {
        "institution_id": institution_id,
        "departments": [
            {"id": d.id, "name": d.name}
            for d in db.scalars(
                select(Department)
                .where(Department.institution_id == institution_id)
                .order_by(Department.name)
            )
        ],
        "tracks": [
            {"id": t.id, "name": t.name}
            for t in db.scalars(
                select(StudyTrack)
                .where(
                    StudyTrack.institution_id == institution_id, StudyTrack.inactive_at.is_(None)
                )
                .order_by(StudyTrack.name)
            )
        ],
        "curricula": [
            {
                "id": c.id,
                "name": c.name,
                "revision": c.revision,
                "lineage_id": c.lineage_id,
                "scope": c.scope_json,
            }
            for c in db.scalars(
                select(AcademicCurriculumRevision)
                .where(
                    AcademicCurriculumRevision.institution_id == institution_id,
                    AcademicCurriculumRevision.status == "published",
                )
                .order_by(AcademicCurriculumRevision.name, AcademicCurriculumRevision.revision)
            )
        ],
    }


def mutate(db, request, payload, operation, action):
    owner = access.locked_identity(db, request).user.id
    fingerprint = digest({"operation": operation, "body": payload.model_dump(mode="json")})
    receipt = db.get(Receipt, (owner, payload.client_id))
    if receipt:
        if receipt.request_digest != fingerprint:
            raise conflict()
        return receipt.response_json
    try:
        result = action(owner)
        # Canonical JSON also serializes Decimal/UUID through the response DTO.
        result = result.model_dump(mode="json")
        db.add(
            Receipt(
                owner_id=owner,
                client_id=payload.client_id,
                request_digest=fingerprint,
                response_json=result,
            )
        )
        db.commit()
        return result
    except IntegrityError:
        db.rollback()
        raise conflict() from None


def save_contexts(db, request, payload):
    def action(owner):
        state = workspace(db, owner, True)
        if state.version != payload.expected_version:
            raise conflict()
        p = personal.profile(db, owner)
        if not p["institution_id"] or not p["department_id"] or not p["admission_year"]:
            invalid("contexts", "먼저 등록 학교·주학과·입학연도를 저장하세요.")
        school = db.get(Institution, p["institution_id"])
        if school is None or school.deleted_at is not None:
            invalid("contexts", "학교를 다시 확인하세요.")
        old = {c.id: c for c in rows(db, Context, owner)}
        for c in old.values():
            c.active = False
        for index, value in enumerate(payload.contexts):
            department, track, curriculum = (
                db.get(m, k)
                for m, k in (
                    (Department, value.department_id),
                    (StudyTrack, value.track_id),
                    (AcademicCurriculumRevision, value.curriculum_revision_id),
                )
            )
            if any(
                r is None or r.institution_id != p["institution_id"]
                for r in (department, track, curriculum)
            ):
                invalid(f"contexts.{index}", "같은 학교의 학과·경로·교육과정을 선택하세요.")
            retained_track = value.id in old and old[value.id].track_id == value.track_id
            if curriculum.status != "published" or (
                track.inactive_at is not None and not retained_track
            ):
                invalid(f"contexts.{index}", "게시 교육과정과 사용 중인 이수 경로를 선택하세요.")
            if value.primary and value.department_id != p["department_id"]:
                invalid(
                    f"contexts.{index}.department_id", "주전공은 프로필의 주학과와 일치해야 합니다."
                )
            if not scope_matches(curriculum.scope_json, value.model_dump(mode="json")):
                invalid(f"contexts.{index}", "교육과정의 적용 대상과 일치하지 않습니다.")
            if value.id is not None and value.id not in old:
                raise personal.missing()
            c = old.get(value.id)
            if c is not None and c.institution_id != p["institution_id"]:
                invalid(f"contexts.{index}", "학교가 바뀌었으면 새 전공 연결을 만드세요.")
            if c is None:
                c = Context(id=uuid4(), owner_id=owner, institution_id=p["institution_id"])
                db.add(c)
            for key, data in value.model_dump(exclude={"id"}).items():
                setattr(c, key, data)
            c.active, c.position = True, index
        state.version += 1
        db.flush()
        return dto.StudentAcademicWorkspaceView.model_validate(read_contexts(db, owner))

    return mutate(db, request, payload, "contexts", action)


def filter_document(db, revision, values):
    today = datetime.now(UTC).date()
    if (revision.effective_from and today < revision.effective_from) or (
        revision.effective_to and today > revision.effective_to
    ):
        return None
    applicable = []
    for c in values:
        if c["institution_id"] != str(revision.institution_id):
            continue
        if (
            revision.curriculum_revision_id
            and str(revision.curriculum_revision_id) != c["curriculum_revision_id"]
        ):
            continue
        if scope_matches(revision.scope_json, c):
            applicable.append(c)
    if not applicable:
        return None
    content = copy.deepcopy(revision.content_json)
    mapping = {}

    def filter_items(items, parents, nested=False):
        selected = []
        for node in items:
            matched = [c for c in parents if scope_matches(node.get("scope"), c)]
            if not matched:
                continue
            mapping[node["id"]] = [c["id"] for c in matched]
            if nested:
                node["items"] = filter_items(node["items"], matched)
                node["groups"] = filter_items(node["groups"], matched, True)
                if not node["items"] and not node["groups"]:
                    mapping.pop(node["id"])
                    continue
            selected.append(node)
        return selected

    if revision.kind == "checklist":
        content["lines"] = filter_items(content["lines"], applicable)
    elif revision.kind == "certification":
        content["groups"] = filter_items(content["groups"], applicable, True)
        content["tables"] = [
            t
            for t in content.get("tables", [])
            if t.get("group_id") is None or t["group_id"] in mapping
        ]
    else:
        content["rows"] = filter_items(content["rows"], applicable)
        content["cells"] = [c for c in content["cells"] if c["row_id"] in mapping]
    if not mapping:
        return None
    return {
        "id": str(revision.id),
        "lineage_id": str(revision.lineage_id),
        "revision": revision.revision,
        "name": revision.name,
        "kind": revision.kind,
        "content": content,
        "context_ids": [c["id"] for c in applicable],
        "node_contexts": mapping,
        "status": "published",
        # Private comparison metadata, not returned by the student DTO.
        "scope": revision.scope_json,
        "effective_from": revision.effective_from.isoformat() if revision.effective_from else None,
        "effective_to": revision.effective_to.isoformat() if revision.effective_to else None,
    }


def documents(db, activation_id):
    if activation_id is None:
        return []
    return list(db.scalars(select(Document).where(Document.activation_id == activation_id)))


def public_document(snapshot):
    return dto.StudentAcademicDocumentView.model_validate(
        {
            key: snapshot[key]
            for key in dto.StudentAcademicDocumentView.model_fields
            if key in snapshot
        }
    )


def response_view(db, response):
    refs = []
    stale = response.needs_confirmation
    for ref in response.records_json:
        row = db.scalar(
            select(personal.RECORD_MODELS[ref["kind"]]).where(
                personal.RECORD_MODELS[ref["kind"]].id == UUID(ref["record_id"]),
                personal.RECORD_MODELS[ref["kind"]].owner_id == response.owner_id,
            )
        )
        stale |= row is None or row.version != ref["version"]
        refs.append(
            {**ref, "available": row is not None, "current_version": row.version if row else None}
        )
    return {
        "item_id": response.item_id,
        "value": response.value,
        "previous_value": response.previous_value,
        "version": response.version,
        "confirmed_at": response.confirmed_at,
        "stale": stale,
        "records": refs,
    }


def group_results(content, responses):
    if content["kind"] != "certification":
        return {}
    states = {str(r["item_id"]): r for r in responses}
    result = {}

    def walk(group):
        children = []
        for item in group["items"]:
            r = states.get(item["id"])
            children.append(None if r is None or r["stale"] else r["value"])
        children.extend(walk(g) for g in group["groups"])
        count = (
            len(children)
            if group["choice"] == "all"
            else 1
            if group["choice"] == "pickOne"
            else group["pick_count"]
        )
        yes, unknown = children.count(True), children.count(None)
        value = (
            None
            if not children or count is None or count > len(children)
            else True
            if yes >= count
            else None
            if yes + unknown >= count
            else False
        )
        result[group["id"]] = (
            "needs_review" if value is None else "satisfied" if value else "not_satisfied"
        )
        return value

    for g in content["groups"]:
        walk(g)
    return result


def active_issues(db, owner, activation):
    issues = context_issues(db, owner)
    if activation is not None and activation.context_digest != context_digest(db, owner):
        issues.append("context_changed")
    return list(dict.fromkeys(issues))


def read_requirements(db, owner, historical_id=None):
    state = workspace(db, owner)
    activation = (
        db.get(Activation, state.active_activation_id)
        if state and state.active_activation_id
        else None
    )
    if historical_id is not None:
        activation = personal.get(db, owner, Activation, historical_id)
    issues = active_issues(db, owner, activation)
    result = []
    for doc in documents(db, activation.id if activation else None):
        snap = copy.deepcopy(doc.snapshot_json)
        current = db.get(AcademicRequirementRevision, doc.requirement_revision_id)
        snap["status"] = current.status
        today = datetime.now(UTC).date()
        snap["usable"] = current.status == "published" and not (
            (current.effective_from and today < current.effective_from)
            or (current.effective_to and today > current.effective_to)
        )
        if current.status != "published":
            issues.append("requirement_withdrawn")
        if (current.effective_from and today < current.effective_from) or (
            current.effective_to and today > current.effective_to
        ):
            issues.append("requirement_expired")
        snap["responses"] = [
            response_view(db, r)
            for r in db.scalars(
                select(Response).where(
                    Response.owner_id == owner,
                    Response.activation_id == activation.id,
                    Response.requirement_revision_id == doc.requirement_revision_id,
                )
            )
        ]
        snap["group_results"] = group_results(snap["content"], snap["responses"])
        result.append(public_document(snap))
    return dto.StudentAcademicRequirements(
        owner_id=owner,
        workspace_version=state.version if state else 0,
        activation_id=activation.id if activation else None,
        issues=list(dict.fromkeys(issues)),
        documents=result,
    )


def history(db, owner):
    state = workspace(db, owner)
    return dto.StudentAcademicHistory(
        owner_id=owner,
        items=[
            dto.StudentAcademicHistoryItem(
                id=a.id,
                created_at=a.created_at,
                active=bool(state and state.active_activation_id == a.id),
                document_count=len(documents(db, a.id)),
            )
            for a in sorted(rows(db, Activation, owner), key=lambda a: a.created_at, reverse=True)
        ],
    )


def node_signatures(doc):
    result = {}
    common = {key: doc.get(key) for key in ("scope", "effective_from", "effective_to")}

    def walk(nodes, ancestors):
        for n in nodes:
            own = {k: v for k, v in n.items() if k not in ("items", "groups")}
            result[n["id"]] = digest(
                {
                    "common": common,
                    "ancestors": ancestors,
                    "node": own,
                    "contexts": doc["node_contexts"].get(n["id"], []),
                }
            )
            walk(n.get("items", []) + n.get("groups", []), [*ancestors, own])

    content = doc["content"]
    walk(content.get("lines", content.get("groups", content.get("rows", []))), [])
    return result


def preview_data(db, owner):
    state = workspace(db, owner)
    values = [context_data(c) for c in contexts(db, owner)]
    issues = context_issues(db, owner)
    candidates = []
    updates = []
    for context in contexts(db, owner):
        source = db.get(AcademicCurriculumRevision, context.curriculum_revision_id)
        for revision in db.scalars(
            select(AcademicCurriculumRevision)
            .where(
                AcademicCurriculumRevision.lineage_id == source.lineage_id,
                AcademicCurriculumRevision.status == "published",
                AcademicCurriculumRevision.revision > source.revision,
            )
            .order_by(AcademicCurriculumRevision.revision.desc())
        ):
            if scope_matches(revision.scope_json, context_data(context)):
                updates.append(
                    {
                        "context_id": str(context.id),
                        "current_revision_id": str(source.id),
                        "new_revision_id": str(revision.id),
                        "name": revision.name,
                        "revision": revision.revision,
                    }
                )
                break
    if not issues:
        all_rows = db.scalars(
            select(AcademicRequirementRevision)
            .where(
                AcademicRequirementRevision.institution_id == UUID(values[0]["institution_id"]),
                AcademicRequirementRevision.status == "published",
            )
            .order_by(
                AcademicRequirementRevision.lineage_id, AcademicRequirementRevision.revision.desc()
            )
        )
        chosen = set()
        for row in all_rows:
            remaining = [c for c in values if (row.lineage_id, c["id"]) not in chosen]
            doc = filter_document(db, row, remaining)
            if doc:
                chosen.update((row.lineage_id, key) for key in doc["context_ids"])
                candidates.append(doc)

    def selection_key(doc):
        return doc["lineage_id"] + ":" + ",".join(sorted(doc["context_ids"]))

    old = {
        selection_key(d.snapshot_json): d.snapshot_json
        for d in documents(db, state.active_activation_id if state else None)
    }
    new = {selection_key(d): d for d in candidates}
    changes = []
    for key in old.keys() | new.keys():
        before, after = old.get(key), new.get(key)
        if before is None:
            changes.append({"name": after["name"], "kind": "added", "detail": "새 적용 요건"})
        elif after is None:
            changes.append(
                {
                    "name": before["name"],
                    "kind": "removed",
                    "detail": "현재 대상·게시 상태에서 제외",
                }
            )
        elif (
            before["id"] != after["id"]
            or before["content"] != after["content"]
            or before["node_contexts"] != after["node_contexts"]
        ):
            a, b = node_signatures(before), node_signatures(after)
            changed = sum(a[k] != b[k] for k in a.keys() & b.keys())
            added, removed = len(b.keys() - a.keys()), len(a.keys() - b.keys())
            details = f"추가 {added} · 삭제 {removed} · 변경 {changed}"
            if before["kind"] == "credit_table":
                details += " · 표의 열·목표 학점·분류 변경을 확인하세요."
            changes.append({"name": after["name"], "kind": "changed", "detail": details})
    fingerprint = digest(
        {
            "context": context_digest(db, owner),
            "documents": candidates,
            "curriculum_updates": updates,
            "active": str(state.active_activation_id) if state else None,
        }
    )
    return candidates, dto.StudentAcademicPreview(
        owner_id=owner,
        workspace_version=state.version if state else 0,
        active_activation_id=state.active_activation_id if state else None,
        digest=fingerprint,
        issues=issues,
        documents=[public_document(d) for d in candidates],
        changes=changes,
        curriculum_updates=updates,
    )


def activate(db, request, payload):
    def action(owner):
        state = workspace(db, owner, True)
        candidates, preview = preview_data(db, owner)
        if state.version != payload.expected_version or preview.digest != payload.expected_digest:
            raise conflict()
        if preview.issues:
            invalid("expected_digest", "학업 기준의 누락·변경 사항을 먼저 확인하세요.")
        previous = documents(db, state.active_activation_id)
        activation = Activation(
            owner_id=owner,
            context_digest=context_digest(db, owner),
            selection_digest=preview.digest,
            contexts_json=[context_data(c) for c in contexts(db, owner)],
        )
        db.add(activation)
        db.flush()
        for doc in candidates:
            db.add(
                Document(
                    activation_id=activation.id,
                    requirement_revision_id=UUID(doc["id"]),
                    snapshot_json=doc,
                )
            )
        db.flush()
        for doc in candidates:
            matching = [d for d in previous if d.snapshot_json["lineage_id"] == doc["lineage_id"]]
            before = next(
                (d for d in matching if d.snapshot_json["context_ids"] == doc["context_ids"]),
                next(iter(matching), None),
            )
            if before is None:
                continue
            a, b = node_signatures(before.snapshot_json), node_signatures(doc)
            for old in db.scalars(
                select(Response).where(
                    Response.owner_id == owner,
                    Response.activation_id == before.activation_id,
                    Response.requirement_revision_id == before.requirement_revision_id,
                )
            ):
                item = str(old.item_id)
                if item not in b:
                    continue
                identical = a.get(item) == b[item]
                db.add(
                    Response(
                        owner_id=owner,
                        activation_id=activation.id,
                        requirement_revision_id=UUID(doc["id"]),
                        item_id=old.item_id,
                        value=old.value if identical else None,
                        previous_value=old.previous_value if identical else old.value,
                        needs_confirmation=old.needs_confirmation if identical else True,
                        version=1,
                        confirmed_at=old.confirmed_at,
                        records_json=old.records_json,
                    )
                )
        state.active_activation_id = activation.id
        state.version += 1
        db.flush()
        return read_requirements(db, owner)

    return mutate(db, request, payload, "activate", action)


def save_response(db, request, revision_id, item_id, payload):
    def action(owner):
        current = read_requirements(db, owner)
        if payload.activation_id != current.activation_id:
            raise conflict()
        if any(
            issue not in ("requirement_withdrawn", "requirement_expired")
            for issue in current.issues
        ):
            invalid("activation_id", "학업 기준의 변경·철회를 확인하고 다시 적용하세요.")
        doc = next((d for d in current.documents if d.id == revision_id), None)
        if doc is None or doc.kind == "credit_table":
            raise personal.missing()
        if not doc.usable:
            invalid("activation_id", "이 요건은 철회됐거나 유효기간이 지났습니다.")
        allowed = []
        if doc.kind == "checklist":
            allowed = [line.id for line in doc.content.lines]
        else:

            def items(groups):
                for group in groups:
                    yield from (i.id for i in group.items)
                    yield from items(group.groups)

            allowed = list(items(doc.content.groups))
        if item_id not in allowed:
            raise personal.missing()
        r = db.scalar(
            select(Response).where(
                Response.owner_id == owner,
                Response.activation_id == current.activation_id,
                Response.requirement_revision_id == revision_id,
                Response.item_id == item_id,
            )
        )
        if (r.version if r else 0) != payload.expected_version:
            raise conflict()
        if doc.kind == "checklist" and payload.records:
            invalid("records", "한 줄 요건에는 O/X만 저장하세요.")
        refs = []
        for ref in payload.records:
            record = personal.get(db, owner, personal.RECORD_MODELS[ref.kind], ref.record_id)
            if record.version != ref.expected_version:
                raise conflict()
            refs.append(
                {
                    "kind": ref.kind,
                    "record_id": str(ref.record_id),
                    "version": record.version,
                    "title": record.title,
                }
            )
        if r is None:
            r = Response(
                owner_id=owner,
                activation_id=current.activation_id,
                requirement_revision_id=revision_id,
                item_id=item_id,
                version=0,
            )
            db.add(r)
        r.value, r.records_json, r.needs_confirmation = payload.value, refs, False
        r.previous_value = None
        r.version += 1
        r.confirmed_at = datetime.now(UTC)
        db.flush()
        return read_requirements(db, owner)

    return mutate(db, request, payload, f"response:{revision_id}:{item_id}", action)


def course_link_view(link):
    return dto.StudentAcademicCourseView.model_validate(
        {k: getattr(link, k) for k in dto.StudentAcademicCourseView.model_fields}
    )


def save_course_link(db, request, record_id, payload):
    def action(owner):
        record = personal.get(db, owner, personal.RECORD_MODELS["course"], record_id)
        context = personal.get(db, owner, Context, payload.context_id)
        if not context.active:
            invalid("context_id", "현재 사용 중인 전공을 선택하세요.")
        if context_issues(db, owner):
            invalid("context_id", "학업 기준을 먼저 확인하세요.")
        entry = db.get(AcademicCurriculumCourse, payload.entry_id)
        if entry is None or entry.curriculum_revision_id != context.curriculum_revision_id:
            invalid("entry_id", "선택한 전공 교육과정의 과목을 선택하세요.")
        if record.version != payload.expected_record_version:
            raise conflict()
        if payload.earned_credits is not None and record.credits is None:
            invalid("earned_credits", "수강 기록의 학점을 먼저 확인하세요.")
        if payload.earned_credits is not None and payload.earned_credits > record.credits:
            invalid("earned_credits", "취득학점은 수강 기록의 학점을 초과할 수 없습니다.")
        link = db.scalar(
            select(CourseLink).where(
                CourseLink.owner_id == owner,
                CourseLink.course_record_id == record_id,
                CourseLink.context_id == context.id,
            )
        )
        if (link.version if link else 0) != payload.expected_version:
            raise conflict()
        if link is None:
            link = CourseLink(
                owner_id=owner, course_record_id=record_id, context_id=context.id, version=0
            )
            db.add(link)
        for key in ("entry_id", "result", "earned_credits", "included"):
            setattr(link, key, getattr(payload, key))
        link.record_version, link.version = record.version, link.version + 1
        db.flush()
        return course_link_view(link)

    return mutate(db, request, payload, f"course:{record_id}", action)
