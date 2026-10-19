"""Translate reviewed source metadata and explicit criteria into immutable programs."""

from datetime import UTC, datetime
from uuid import uuid4, uuid5

from pydantic import ValidationError
from sqlalchemy import delete, exists, func, or_, select

from app.core.auth_errors import AuthError, conflict, forbidden
from app.models.academic import Course, GraduationRule, OfficialDocument, RuleSet
from app.models.certificates import CertificateProvider
from app.models.identity import AdminScope, Institution, Role
from app.models.knowledge import KnowledgeChunk, KnowledgeDocument
from app.models.rule_programs import (
    ProgramCertificateRef,
    ProgramCourseRef,
    ProgramEvidence,
    ProgramRule,
    RuleProgram,
)
from app.rules import contracts as core
from app.schemas import rule_programs as dto
from app.schemas.common import ErrorCode
from app.services import academic, access, catalog, certificates

KINDS = {
    "credits": "minimum_credits",
    "required_course": "required_courses",
    "volunteer": "minimum_volunteer_hours",
    "certificate": "any_certificate",
    "thesis": "thesis",
    "custom": "manual_review",
}
MAX_TARGETS = 100
MAX_SELECTED_RULES = 500
MAX_SELECTED_EVIDENCE = 2000


def invalid(message="적용된 기준·실행 조건·출처의 범위와 버전을 확인해 주세요."):
    return AuthError(422, ErrorCode.VALIDATION_ERROR, message)


def source(db, rule_set_id, rule_id):
    model, identifier = (RuleSet, rule_set_id) if rule_set_id else (GraduationRule, rule_id)
    parent = db.get(model, identifier)
    if parent is None:
        raise catalog.missing()
    if isinstance(parent, GraduationRule) and parent.rule_set_id is not None:
        raise invalid("묶음에 속한 요건은 전체 규칙 묶음에서 검토해 주세요.")
    children = (
        list(
            db.scalars(
                select(GraduationRule)
                .where(GraduationRule.rule_set_id == parent.id)
                .order_by(GraduationRule.id)
                .limit(101)
            )
        )
        if model is RuleSet
        else [parent]
    )
    if len(children) > 100 or not children:
        raise invalid("내용이 있는 적용 기준을 최대 100개 요건 단위로 검토해 주세요.")
    if parent.status != "applied" or any(child.status != "applied" for child in children):
        raise conflict()
    return parent, {row.id: row for row in children}


def admin_read(db, identity, identifier):
    return academic.read(db, identity, RuleProgram, identifier)


def listing(
    db,
    identity,
    institution_id=None,
    status=None,
    rule_set_id=None,
    rule_id=None,
    cursor=None,
    limit=100,
):
    if identity.user.role not in (Role.SUPER_ADMIN, Role.SCHOOL_ADMIN):
        raise forbidden()
    statement = select(RuleProgram).join(Institution).where(Institution.deleted_at.is_(None))
    if institution_id:
        academic.school(db, identity, institution_id)
        statement = statement.where(RuleProgram.institution_id == institution_id)
    if identity.user.role == Role.SCHOOL_ADMIN:
        statement = statement.where(
            exists().where(
                AdminScope.user_id == identity.user.id,
                AdminScope.institution_id == RuleProgram.institution_id,
                AdminScope.status == "active",
            )
        )
    for name, value in [("status", status), ("rule_set_id", rule_set_id), ("rule_id", rule_id)]:
        if value is not None:
            statement = statement.where(getattr(RuleProgram, name) == value)
    if cursor:
        statement = statement.where(RuleProgram.id > cursor)
    return list(db.scalars(statement.order_by(RuleProgram.id).limit(limit + 1)))


def _scope_covers(record, program):
    return record.institution_id == program.institution_id and all(
        getattr(record, name) is None or getattr(record, name) == getattr(program, name)
        for name in ("department_id", "curriculum_id")
    )


def evidence_records(db, identifiers):
    rows = db.execute(
        select(KnowledgeChunk, KnowledgeDocument, OfficialDocument)
        .join(KnowledgeDocument, KnowledgeDocument.id == KnowledgeChunk.knowledge_document_id)
        .join(OfficialDocument, OfficialDocument.id == KnowledgeDocument.source_document_id)
        .where(KnowledgeChunk.id.in_(set(identifiers)))
    )
    return {chunk.id: (chunk, document, meta) for chunk, document, meta in rows}


def _source_chain(db, document):
    result = [document]
    if document.rule_id is not None:
        rule = db.get(GraduationRule, document.rule_id)
        if rule is None:
            raise invalid()
        result.append(rule)
        if rule.rule_set_id is not None:
            group = db.get(RuleSet, rule.rule_set_id)
            if group is None:
                raise invalid()
            result.append(group)
    return result


def validate_data(db, item, payload, *, complete=False):
    parent, required = source(db, item.rule_set_id, item.rule_id)
    if parent.version != item.source_version or any(
        getattr(parent, name) != getattr(item, name)
        for name in ("institution_id", "department_id", "curriculum_id")
    ):
        raise conflict()
    selected = {rule.rule_id for rule in payload.rules}
    if not selected <= required.keys():
        raise invalid("기준에 속한 적용 요건만 실행 조건으로 선택해 주세요.")
    if complete and selected != required.keys():
        raise invalid("모든 적용 요건의 실행 조건을 먼저 등록해 주세요.")
    evidence = evidence_records(
        db, [identifier for rule in payload.rules for identifier in rule.evidence_chunk_ids]
    )
    dates, definitions = [parent, *required.values()], []
    for entry in payload.rules:
        meta = required[entry.rule_id]
        if meta.version != entry.expected_version:
            raise conflict()
        condition = entry.condition
        if KINDS[meta.rule_type] != condition.kind:
            raise invalid("요건 종류와 실행 조건 종류를 일치시켜 주세요.")
        identifier = uuid5(item.id, str(meta.id))
        rule = ProgramRule(
            id=identifier,
            program_id=item.id,
            institution_id=item.institution_id,
            rule_id=meta.id,
            source_version=meta.version,
            title=meta.name,
            kind=condition.kind,
            condition_json=condition.model_dump(mode="json"),
        )
        refs, sources = [], []
        for chunk_id in entry.evidence_chunk_ids:
            records = evidence.get(chunk_id)
            if records is None:
                raise catalog.missing()
            chunk, document, source_doc = records
            if (
                chunk.is_blank
                or chunk.institution_id != item.institution_id
                or document.status != "approved"
                or document.source_document_version != source_doc.version
                or not set(range(payload.admission_year_from, payload.admission_year_to + 1))
                <= set(chunk.admission_years or [])
                or not set(payload.tracks) <= set(chunk.tracks or [])
                or chunk.warnings
            ):
                raise invalid(
                    "모든 적용 연도·이수경로를 포함하는 승인된 본문 청크를 선택해 주세요."
                )
            chain = _source_chain(db, source_doc)
            if any(
                record.status != "applied" or not _scope_covers(record, item) for record in chain
            ):
                raise invalid("출처와 연결된 기준의 학교·학과·교육과정 범위를 확인해 주세요.")
            dates.extend(chain)
            sources.append(
                ProgramEvidence(
                    program_rule_id=identifier,
                    chunk_id=chunk.id,
                    institution_id=item.institution_id,
                    knowledge_version=document.version,
                    content_hash=chunk.content_hash,
                )
            )
        if isinstance(condition, dto.CourseCriterion):
            for requirement in condition.courses:
                course = db.get(Course, requirement.course_id)
                if course is None or course.institution_id != item.institution_id:
                    raise catalog.missing()
                if course.version != requirement.expected_version:
                    raise conflict()
                refs.append(
                    ProgramCourseRef(
                        program_rule_id=identifier,
                        course_id=course.id,
                        institution_id=item.institution_id,
                        catalog_version=course.version,
                        code=course.code,
                        name=course.name,
                    )
                )
        elif isinstance(condition, dto.CertificateCriterion):
            for choice in condition.certificates:
                certificate = certificates.active_certificate(db, choice.certificate_id)
                if certificate.version != choice.expected_version:
                    raise conflict()
                provider = db.get(CertificateProvider, certificate.provider_id)
                refs.append(
                    ProgramCertificateRef(
                        program_rule_id=identifier,
                        certificate_id=certificate.id,
                        institution_id=item.institution_id,
                        catalog_version=certificate.version,
                        code=certificate.code,
                        name=certificate.name,
                        provider_name=provider.name,
                    )
                )
        definitions.append((rule, sources, refs))
    starts = [record.effective_from for record in dates if record.effective_from]
    ends = [record.effective_to for record in dates if record.effective_to]
    start, end = max(starts, default=None), min(ends, default=None)
    if start and end and start > end:
        raise invalid("출처와 실행 기준의 적용 기간이 겹치지 않습니다.")
    return definitions, start, end


def _audit(db, identity, action, item, request):
    access.audit(
        db,
        identity.user.id,
        "rule_program:" + action,
        item.id,
        request.state.request_id,
        item.institution_id,
    )


def _write(db, item, payload, definitions, start, end):
    item.admission_year_from, item.admission_year_to = (
        payload.admission_year_from,
        payload.admission_year_to,
    )
    item.tracks = sorted(payload.tracks)
    item.effective_from, item.effective_to = start, end
    db.execute(delete(ProgramRule).where(ProgramRule.program_id == item.id))
    db.add_all([rule for rule, _, _ in definitions])
    db.flush()
    db.add_all([row for _, evidence, references in definitions for row in [*evidence, *references]])
    db.flush()


def create(db, request, payload):
    identity = access.locked_identity(db, request)
    model, identifier = (
        (RuleSet, payload.rule_set_id) if payload.rule_set_id else (GraduationRule, payload.rule_id)
    )
    academic.read(db, identity, model, identifier)
    parent, _ = source(db, payload.rule_set_id, payload.rule_id)
    academic.school(db, identity, parent.institution_id)
    if parent.version != payload.expected_source_version:
        raise conflict()
    item = RuleProgram(
        id=uuid4(),
        institution_id=parent.institution_id,
        department_id=parent.department_id,
        curriculum_id=parent.curriculum_id,
        name=parent.name,
        version=1,
        rule_set_id=payload.rule_set_id,
        rule_id=payload.rule_id,
        source_version=parent.version,
        admission_year_from=payload.admission_year_from,
        admission_year_to=payload.admission_year_to,
        tracks=sorted(payload.tracks),
        created_by=identity.user.id,
        updated_by=identity.user.id,
    )
    definitions, start, end = validate_data(db, item, payload)
    db.add(item)
    db.flush()
    _write(db, item, payload, definitions, start, end)
    _audit(db, identity, "create", item, request)
    result = view(db, item)
    academic.commit(db)
    return result


def _mutate(db, request, identifier, expected_version, status):
    identity = access.locked_identity(db, request)
    item = admin_read(db, identity, identifier)
    if item.version != expected_version or item.status != status:
        raise conflict()
    return identity, item


def _touch(item, identity):
    item.version += 1
    item.updated_by, item.updated_at = identity.user.id, datetime.now(UTC)


def replace(db, request, identifier, payload):
    identity, item = _mutate(db, request, identifier, payload.expected_version, "draft")
    definitions, start, end = validate_data(db, item, payload)
    _write(db, item, payload, definitions, start, end)
    _touch(item, identity)
    _audit(db, identity, "replace", item, request)
    db.flush()
    result = view(db, item)
    academic.commit(db)
    return result


def inputs(db, item):
    values = []
    for rule in db.scalars(
        select(ProgramRule).where(ProgramRule.program_id == item.id).order_by(ProgramRule.rule_id)
    ):
        evidence = list(
            db.scalars(
                select(ProgramEvidence.chunk_id)
                .where(ProgramEvidence.program_rule_id == rule.id)
                .order_by(ProgramEvidence.chunk_id)
            )
        )
        values.append(
            dto.ProgramRuleInput(
                rule_id=rule.rule_id,
                expected_version=rule.source_version,
                condition=rule.condition_json,
                evidence_chunk_ids=evidence,
            )
        )
    return dto.ProgramData(
        admission_year_from=item.admission_year_from,
        admission_year_to=item.admission_year_to,
        tracks=item.tracks,
        rules=values,
    )


def _period_overlaps(first, second):
    return not (
        first.effective_to
        and second.effective_from
        and first.effective_to < second.effective_from
        or second.effective_to
        and first.effective_from
        and second.effective_to < first.effective_from
    )


def approve(db, request, identifier, payload):
    identity, item = _mutate(db, request, identifier, payload.expected_version, "draft")
    try:
        data = inputs(db, item)
    except ValidationError:
        raise conflict() from None
    _, start, end = validate_data(db, item, data, complete=True)
    item.effective_from, item.effective_to = start, end
    candidates = db.scalars(
        select(RuleProgram).where(
            RuleProgram.id != item.id,
            RuleProgram.rule_set_id == item.rule_set_id,
            RuleProgram.rule_id == item.rule_id,
            RuleProgram.status == "approved",
            RuleProgram.admission_year_from <= item.admission_year_to,
            RuleProgram.admission_year_to >= item.admission_year_from,
        )
    )
    if any(
        set(other.tracks) & set(item.tracks) and _period_overlaps(item, other)
        for other in candidates
    ):
        raise AuthError(
            409, ErrorCode.CONFLICT, "같은 기준·연도·이수경로·기간의 승인 실행본이 이미 있습니다."
        )
    item.status, item.approved_by, item.approved_at = (
        "approved",
        identity.user.id,
        datetime.now(UTC),
    )
    item.review_note = payload.review_note
    _touch(item, identity)
    _audit(db, identity, "approve", item, request)
    db.flush()
    result = view(db, item)
    academic.commit(db)
    return result


def revoke(db, request, identifier, payload):
    identity, item = _mutate(db, request, identifier, payload.expected_version, "approved")
    item.status, item.revoked_by, item.revoked_at = "revoked", identity.user.id, datetime.now(UTC)
    item.revocation_reason = payload.reason
    _touch(item, identity)
    _audit(db, identity, "revoke", item, request)
    db.flush()
    result = view(db, item)
    academic.commit(db)
    return result


def remove(db, request, identifier, version):
    identity, item = _mutate(db, request, identifier, version, "draft")
    _audit(db, identity, "delete_draft", item, request)
    db.delete(item)
    academic.commit(db)


def _dependencies_valid(db, item, on):
    if (
        item.status != "approved"
        or item.effective_from
        and item.effective_from > on
        or item.effective_to
        and item.effective_to < on
    ):
        return False
    try:
        parent, required = source(db, item.rule_set_id, item.rule_id)
        if parent.version != item.source_version:
            return False
        if (
            db.scalar(
                catalog.statement(
                    type(parent), on, item.institution_id, item.department_id, item.curriculum_id
                ).where(type(parent).id == parent.id)
            )
            is None
        ):
            return False
        rows = list(db.scalars(select(ProgramRule).where(ProgramRule.program_id == item.id)))
        if {row.rule_id for row in rows} != required.keys():
            return False
        for row in rows:
            if (
                row.source_version != required[row.rule_id].version
                or row.kind != KINDS[required[row.rule_id].rule_type]
            ):
                return False
            condition = dto.condition_adapter.validate_python(row.condition_json)
            refs = list(
                db.scalars(select(ProgramEvidence).where(ProgramEvidence.program_rule_id == row.id))
            )
            records = evidence_records(db, [ref.chunk_id for ref in refs])
            if not refs:
                return False
            for ref in refs:
                chunk, document, meta = records[ref.chunk_id]
                if (
                    chunk.is_blank
                    or document.status != "approved"
                    or document.version != ref.knowledge_version
                    or chunk.content_hash != ref.content_hash
                    or document.source_document_version != meta.version
                    or not _scope_covers(meta, item)
                ):
                    return False
                if (
                    db.scalar(
                        catalog.statement(
                            OfficialDocument,
                            on,
                            item.institution_id,
                            item.department_id,
                            item.curriculum_id,
                        ).where(OfficialDocument.id == meta.id)
                    )
                    is None
                ):
                    return False
            if isinstance(condition, dto.CourseCriterion):
                references = list(
                    db.scalars(
                        select(ProgramCourseRef).where(ProgramCourseRef.program_rule_id == row.id)
                    )
                )
                if {(ref.course_id, ref.catalog_version) for ref in references} != {
                    (c.course_id, c.expected_version) for c in condition.courses
                }:
                    return False
            if isinstance(condition, dto.CertificateCriterion):
                references = list(
                    db.scalars(
                        select(ProgramCertificateRef).where(
                            ProgramCertificateRef.program_rule_id == row.id
                        )
                    )
                )
                if {(ref.certificate_id, ref.catalog_version) for ref in references} != {
                    (c.certificate_id, c.expected_version) for c in condition.certificates
                }:
                    return False
                for ref in references:
                    certificates.active_certificate(db, ref.certificate_id)
        return True
    except (AuthError, ValidationError, ValueError, KeyError):
        return False


def rule_views(db, item):
    result = []
    for rule in db.scalars(
        select(ProgramRule).where(ProgramRule.program_id == item.id).order_by(ProgramRule.rule_id)
    ):
        references, sources = [], []
        evidence = list(
            db.scalars(
                select(ProgramEvidence)
                .where(ProgramEvidence.program_rule_id == rule.id)
                .order_by(ProgramEvidence.chunk_id)
            )
        )
        records = evidence_records(db, [value.chunk_id for value in evidence])
        for ref in evidence:
            chunk, document, meta = records[ref.chunk_id]
            sources.append(
                dto.EvidenceView(
                    chunk_id=chunk.id,
                    knowledge_document_id=document.id,
                    knowledge_version=ref.knowledge_version,
                    document_id=meta.id,
                    document_version=meta.version,
                    title=meta.name,
                    source_url=meta.source_url,
                    page=chunk.page,
                    content_hash=ref.content_hash,
                    document_hash=document.document_hash,
                    excerpt=chunk.content[:800],
                )
            )
        for ref in db.scalars(
            select(ProgramCourseRef)
            .where(ProgramCourseRef.program_rule_id == rule.id)
            .order_by(ProgramCourseRef.course_id)
        ):
            references.append(
                dto.ReferenceSnapshot(
                    kind="course",
                    record_id=ref.course_id,
                    version=ref.catalog_version,
                    code=ref.code,
                    name=ref.name,
                )
            )
        for ref in db.scalars(
            select(ProgramCertificateRef)
            .where(ProgramCertificateRef.program_rule_id == rule.id)
            .order_by(ProgramCertificateRef.certificate_id)
        ):
            references.append(
                dto.ReferenceSnapshot(
                    kind="certificate",
                    record_id=ref.certificate_id,
                    version=ref.catalog_version,
                    code=ref.code,
                    name=ref.name,
                    provider_name=ref.provider_name,
                )
            )
        result.append(
            dto.ProgramRuleView(
                rule_id=rule.rule_id,
                source_version=rule.source_version,
                title=rule.title,
                condition=rule.condition_json,
                evidence=sources,
                references=references,
            )
        )
    return result


def view(db, item):
    header = dto.ProgramHeader.model_validate(item).model_dump()
    _, required = source(db, item.rule_set_id, item.rule_id)
    rules = rule_views(db, item)
    return dto.ProgramView(
        **header,
        approved_by=item.approved_by,
        review_note=item.review_note,
        revoked_by=item.revoked_by,
        revocation_reason=item.revocation_reason,
        rules=rules,
        missing_rule_ids=sorted(required.keys() - {row.rule_id for row in rules}),
        usable=_dependencies_valid(db, item, datetime.now(UTC).date()),
    )


def public_detail(db, identifier, on):
    item = db.get(RuleProgram, identifier)
    if item is None or not _dependencies_valid(db, item, on):
        raise catalog.missing()
    return dto.PublicProgram(
        **dto.ProgramHeader.model_validate(item).model_dump(), rules=rule_views(db, item)
    )


def selection(db, context, on):
    catalog.context(db, context.institution_id, context.department_id, context.curriculum_id)
    targets = []
    for model, kind in [(RuleSet, "rule_set"), (GraduationRule, "rule")]:
        statement = catalog.statement(
            model, on, context.institution_id, context.department_id, context.curriculum_id
        )
        if model is GraduationRule:
            statement = statement.where(GraduationRule.rule_set_id.is_(None))
        targets.extend(
            (kind, item) for item in db.scalars(statement.order_by(model.id).limit(MAX_TARGETS + 1))
        )

    def response(status, reason, programs=(), issues=()):
        return dto.ProgramSelection(
            context=context,
            as_of=on,
            status=status,
            reason=reason,
            programs=list(programs),
            issues=list(issues),
        )

    if len(targets) > MAX_TARGETS:
        return response("needs_review", "rule_catalog_limit_exceeded")
    if not targets:
        return response("not_applicable", "no_registered_rule_metadata")
    statement = select(RuleProgram).where(
        RuleProgram.status == "approved",
        RuleProgram.institution_id == context.institution_id,
        RuleProgram.admission_year_from <= context.admission_year,
        RuleProgram.admission_year_to >= context.admission_year,
        RuleProgram.tracks.contains([context.track]),
        *catalog.dates(RuleProgram, on),
        or_(
            RuleProgram.rule_set_id.in_([item.id for kind, item in targets if kind == "rule_set"]),
            RuleProgram.rule_id.in_([item.id for kind, item in targets if kind == "rule"]),
        ),
    )
    candidates = list(db.scalars(statement.order_by(RuleProgram.id).limit(MAX_TARGETS + 1)))
    identifiers = [item.id for item in candidates]
    count = db.scalar(
        select(func.count()).select_from(ProgramRule).where(ProgramRule.program_id.in_(identifiers))
    )
    evidence_count = db.scalar(
        select(func.count())
        .select_from(ProgramEvidence)
        .join(ProgramRule, ProgramRule.id == ProgramEvidence.program_rule_id)
        .where(ProgramRule.program_id.in_(identifiers))
    )
    if (
        len(candidates) > MAX_TARGETS
        or count > MAX_SELECTED_RULES
        or evidence_count > MAX_SELECTED_EVIDENCE
    ):
        return response("needs_review", "rule_catalog_limit_exceeded")
    programs, issues = [], []
    for kind, target in targets:
        matches = [
            p
            for p in candidates
            if (p.rule_set_id if kind == "rule_set" else p.rule_id) == target.id
        ]
        reason = None
        if not matches:
            reason = "execution_program_required"
        elif len(matches) > 1:
            reason = "ambiguous_rule_programs"
        elif not _dependencies_valid(db, matches[0], on):
            reason = "program_dependency_unavailable"
        else:
            item = matches[0]
            public = dto.PublicProgram(
                **dto.ProgramHeader.model_validate(item).model_dump(), rules=rule_views(db, item)
            )
            programs.append(public)
            if any(rule.condition.kind == "manual_review" for rule in public.rules):
                reason = "manual_requirement"
        if reason:
            issues.append(dto.SelectionIssue(kind=kind, record_id=target.id, reason=reason))
    return response(
        "needs_review" if issues else "available",
        "rule_program_review_required" if issues else "registered_programs_available",
        programs,
        issues,
    )


def as_core(db, item, track, on):
    """Internal rule adapter only; no trusted student record provider is implied."""
    if track not in item.tracks or not _dependencies_valid(db, item, on):
        raise conflict()
    parent, _ = source(db, item.rule_set_id, item.rule_id)
    public = rule_views(db, item)
    rules, evidence = [], {}
    for row in public:
        fields = {"id": row.rule_id, "code": "rule_" + row.rule_id.hex, "title": row.title}
        match row.condition:
            case dto.CreditCriterion():
                rule = core.CreditRule(
                    **fields, minimum=row.condition.minimum, category=row.condition.category
                )
            case dto.CourseCriterion():
                rule = core.CourseRule(
                    **fields,
                    courses=tuple(
                        core.CourseRequirement(**course.model_dump(exclude={"expected_version"}))
                        for course in row.condition.courses
                    ),
                )
            case dto.VolunteerCriterion():
                rule = core.VolunteerRule(**fields, minimum=row.condition.minimum)
            case dto.CertificateCriterion():
                rule = core.CertificateRule(
                    **fields,
                    certificate_ids=tuple(
                        value.certificate_id for value in row.condition.certificates
                    ),
                )
            case dto.ThesisCriterion():
                rule = core.ThesisRule(
                    **fields,
                    thesis_type=row.condition.thesis_type,
                    requires_approval=row.condition.requires_approval,
                    accepted_grades=tuple(row.condition.accepted_grades),
                )
            case dto.ManualCriterion():
                rule = core.ReviewRule(**fields, reason="manual_requirement")
        rules.append(rule)
        for ref in row.evidence:
            evidence[ref.document_id, ref.page] = core.Evidence(
                document_id=ref.document_id,
                title=ref.title,
                source_url=ref.source_url,
                page=ref.page,
            )
    scope_type = (
        "curriculum"
        if item.curriculum_id
        else "department"
        if item.department_id
        else "institution"
    )
    return core.RuleSet(
        id=item.id,
        code=("set_" if item.rule_set_id else "single_") + parent.lineage_id.hex,
        version=item.version,
        origin="official",
        approval_status="approved",
        rules=tuple(rules),
        effective_from=item.effective_from,
        effective_to=item.effective_to,
        evidence=tuple(evidence.values()),
        scope=core.Scope(
            scope_type=scope_type,
            institution_id=item.institution_id,
            department_id=item.department_id,
            curriculum_id=item.curriculum_id,
            admission_year_from=item.admission_year_from,
            admission_year_to=item.admission_year_to,
            track=track,
        ),
    )
