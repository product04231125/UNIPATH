"""Evaluate only reviewed rules and owner-bound school records under the identity lock."""

from datetime import UTC, datetime
from uuid import UUID, uuid4, uuid5

from pydantic import ValidationError
from sqlalchemy import func, select

from app.core.auth_errors import AuthError, conflict
from app.models.graduation import GraduationAudit as Audit
from app.models.graduation import GraduationCatalogReview as Review
from app.models.official_records import OfficialRecordBatch as Batch
from app.models.rule_programs import RuleProgram
from app.rules import contracts as core
from app.rules.engine import evaluate_official
from app.schemas import graduation as dto
from app.schemas.auth import StrictModel
from app.schemas.common import ErrorCode
from app.services import access, official_records, rule_programs
from app.services import graduation_catalogs as catalogs

MAX_AUDITS = 200
MAX_OWNER_BYTES = 64 * 1024 * 1024
MAX_AUDIT_BYTES = 4 * 1024 * 1024


class AuditPayload(StrictModel):
    id: UUID
    owner_id: UUID
    client_id: UUID
    context: dto.GraduationContext
    catalog_digest: str
    catalog_complete: bool
    unresolved_catalog: bool
    catalog_review_id: UUID | None
    catalog_review_version: int | None
    criteria: list[dto.AuditedProgram]
    records: list[dto.AuditedBatch]
    record_evidence: list[dto.AuditRecordEvidence]
    issues: list[dto.AuditIssue]
    core_rules: list[core.RuleSet]
    core_input: core.Snapshot
    evaluation: core.Evaluation


def record_kinds(programs):
    kinds = {
        "minimum_credits": "academics",
        "required_courses": "academics",
        "minimum_volunteer_hours": "volunteers",
        "any_certificate": "certificates",
        "thesis": "theses",
    }
    return {
        kinds[rule.kind] for program in programs for rule in program.rules if rule.kind in kinds
    }


def criteria(programs):
    return [
        dto.AuditedProgram(
            **{
                key: getattr(p, key)
                for key in ("id", "version", "rule_set_id", "rule_id", "source_version", "name")
            },
            rules=[
                dto.AuditedRule(
                    rule_id=r.rule_id,
                    source_version=r.source_version,
                    title=r.title,
                    condition=r.condition,
                    evidence=[dto.AuditEvidence.from_evidence(e) for e in r.evidence],
                    references=r.references,
                )
                for r in p.rules
            ],
        )
        for p in programs
    ]


def batch_references(db, identifiers):
    return [
        dto.AuditedBatch(
            **{
                key: getattr(row, key)
                for key in (
                    "id",
                    "version",
                    "kind",
                    "data_digest",
                    "source_id",
                    "source_version",
                    "source_sha256",
                )
            }
        )
        for row in db.scalars(select(Batch).where(Batch.id.in_(identifiers)).order_by(Batch.kind))
    ]


def current_records(db, identity, scope, on, programs):
    inputs, ids, problems = official_records.owned_snapshot(
        db, identity, core.AcademicContext(**scope.model_dump()), on, kinds=record_kinds(programs)
    )
    issues = [dto.AuditIssue(kind=kind or "records", reason=reason) for kind, reason in problems]
    return inputs, batch_references(db, ids), issues


def record_evidence(db, references):
    result = []
    for reference in references:
        batch = db.get(Batch, reference.id)
        data = official_records.load_data(batch)
        result.extend(
            dto.AuditRecordEvidence(
                record_id=uuid5(batch.id, str(record.client_id)),
                batch_id=batch.id,
                client_id=record.client_id,
                kind=batch.kind,
                source_page=record.source_page,
            )
            for record in data.records
        )
    return result


def header(row):
    return dto.GraduationAuditHeader(
        **{
            key: getattr(row, key)
            for key in (
                "id",
                "owner_id",
                "client_id",
                "version",
                "created_at",
                "status",
                "reason",
                "catalog_complete",
                "eligible_as_of",
            )
        },
        context=catalogs.context(row),
        evaluated_on=row.as_of,
    )


def load(row):
    try:
        data = AuditPayload.model_validate(row.payload_json)
        if (
            official_records.digest(data) != row.payload_digest
            or len(official_records.encoded(data)) != row.payload_bytes
            or any(
                (
                    data.id != row.id,
                    data.owner_id != row.owner_id,
                    data.client_id != row.client_id,
                    data.context != catalogs.context(row),
                    data.evaluation.evaluated_on != row.as_of,
                    data.evaluation.status != row.status,
                    data.evaluation.reason != row.reason,
                    data.evaluation.official is not True,
                    data.catalog_complete != row.catalog_complete,
                    data.catalog_review_id != row.catalog_review_id,
                    data.catalog_review_version != row.catalog_review_version,
                )
            )
        ):
            raise catalogs.corrupt()
        # The stored inputs must reproduce the historical result, independently
        # of live documents, records, later revocation or master changes.
        reproduced = evaluate_official(
            tuple(data.core_rules),
            data.core_input,
            core.AcademicContext(**data.context.model_dump()),
            as_of=row.as_of,
            catalog_complete=data.catalog_complete,
            unresolved_catalog=data.unresolved_catalog,
        )
        if reproduced != data.evaluation:
            raise catalogs.corrupt()
        return data
    except (ValidationError, ValueError, TypeError):
        raise catalogs.corrupt() from None


def read(db, identity, identifier):
    row = db.get(Audit, identifier)
    if row is None or row.owner_id != identity.user.id:
        raise AuthError(404, ErrorCode.NOT_FOUND, "요청한 본인 졸업요건 감사를 찾을 수 없습니다.")
    return row


def current_issues(db, identity, row, data):
    issues = []
    if not row.catalog_complete or row.catalog_review_id is None:
        issues.append(dto.AuditIssue(kind="catalog", reason="catalog_review_required"))
    else:
        review = db.get(Review, row.catalog_review_id)
        if (
            review is None
            or review.version != row.catalog_review_version
            or catalogs.context(review) != data.context
            or review.as_of != row.as_of
            or review.snapshot_digest != data.catalog_digest
        ):
            issues.append(dto.AuditIssue(kind="catalog", reason="catalog_review_unavailable"))
        else:
            try:
                issues.extend(
                    dto.AuditIssue(kind="catalog", reason=reason)
                    for reason in catalogs.usability(db, review)
                )
            except AuthError as error:
                if error.status != 503:
                    raise
                issues.append(
                    dto.AuditIssue(kind="catalog", reason="catalog_integrity_unavailable")
                )
    try:
        _, current, record_issues = current_records(
            db, identity, data.context, row.as_of, data.core_rules
        )
        issues.extend(record_issues)
        if current != data.records:
            issues.append(dto.AuditIssue(kind="records", reason="approved_records_changed"))
    except AuthError as error:
        if error.status != 503:
            raise
        issues.append(dto.AuditIssue(kind="records", reason="record_integrity_unavailable"))
    if any(rule.kind == "manual_review" for group in data.core_rules for rule in group.rules):
        issues.append(dto.AuditIssue(kind="catalog", reason="manual_requirement"))
    return issues


def view(db, identity, row):
    data = load(row)
    issues = current_issues(db, identity, row, data)
    return dto.GraduationAuditView(
        **header(row).model_dump(),
        catalog_review_id=data.catalog_review_id,
        catalog_review_version=data.catalog_review_version,
        catalog_digest=data.catalog_digest,
        criteria=data.criteria,
        records=data.records,
        record_evidence=data.record_evidence,
        results=[
            dto.AuditResultItem.model_validate(r.model_dump(exclude={"rule_code"}))
            for r in data.evaluation.results
        ],
        issues=data.issues,
        current_usable=not issues,
        current_issues=issues,
    )


def create(db, request, payload):
    with official_records.writes(db):
        identity = access.locked_identity(db, request)
        creation = official_records.digest(payload)
        existing = db.scalar(
            select(Audit).where(
                Audit.owner_id == identity.user.id, Audit.client_id == payload.client_id
            )
        )
        if existing:
            if existing.creation_digest != creation:
                raise conflict()
            return view(db, identity, existing)
        selected = catalogs.preview(db, payload.context, payload.as_of)
        review = catalogs.active(db, payload.context, payload.as_of)
        review_issues = (
            ["catalog_review_required"]
            if review is None
            else catalogs.usability(db, review, selected)
        )
        complete = not review_issues and selected.reviewable
        unresolved = selected.reason == "rule_catalog_limit_exceeded" or any(
            issue.reason != "manual_requirement" for issue in selected.issues
        )
        programs = [
            rule_programs.as_core(
                db,
                db.get(RuleProgram, p.id),
                payload.context.track,
                payload.as_of,
                strict_references=True,
            )
            for p in selected.programs
        ]
        inputs, refs, issues = current_records(
            db, identity, payload.context, payload.as_of, programs
        )
        issues.extend(dto.AuditIssue(kind="catalog", reason=reason) for reason in review_issues)
        issues.extend(dto.AuditIssue(kind="catalog", reason=i.reason) for i in selected.issues)
        result = evaluate_official(
            tuple(programs),
            inputs,
            core.AcademicContext(**payload.context.model_dump()),
            as_of=payload.as_of,
            catalog_complete=complete,
            unresolved_catalog=unresolved,
        )
        identifier = uuid4()
        data = AuditPayload(
            id=identifier,
            owner_id=identity.user.id,
            client_id=payload.client_id,
            context=payload.context,
            catalog_digest=selected.snapshot_digest,
            catalog_complete=complete,
            unresolved_catalog=unresolved,
            catalog_review_id=review.id if review else None,
            catalog_review_version=review.version if review else None,
            criteria=criteria(selected.programs),
            records=refs,
            record_evidence=record_evidence(db, refs),
            issues=issues,
            core_rules=programs,
            core_input=inputs,
            evaluation=result,
        )
        size = len(official_records.encoded(data))
        count, used = db.execute(
            select(func.count(), func.coalesce(func.sum(Audit.payload_bytes), 0)).where(
                Audit.owner_id == identity.user.id
            )
        ).one()
        if size > MAX_AUDIT_BYTES:
            raise AuthError(413, ErrorCode.HTTP_ERROR, "졸업요건 감사 근거는 최대 4 MiB입니다.")
        if count >= MAX_AUDITS or used + size > MAX_OWNER_BYTES:
            raise conflict()
        row = Audit(
            id=identifier,
            owner_id=identity.user.id,
            client_id=payload.client_id,
            creation_digest=creation,
            payload_digest=official_records.digest(data),
            payload_bytes=size,
            payload_json=official_records.wire(data),
            version=1,
            as_of=payload.as_of,
            status=result.status,
            reason=result.reason,
            catalog_complete=complete,
            eligible_as_of=result.status == core.Status.SATISFIED and complete,
            catalog_review_id=data.catalog_review_id,
            catalog_review_version=data.catalog_review_version,
            created_at=datetime.now(UTC),
            **payload.context.model_dump(),
        )
        db.add(row)
        access.audit(
            db,
            identity.user.id,
            "graduation_audit_created",
            row.id,
            request_id=request.state.request_id,
            institution_id=row.institution_id,
        )
        db.commit()
        db.refresh(row)
        return view(db, identity, row)


def listing(db, identity, *, institution_id=None, cursor=None, limit=20):
    statement = select(Audit).where(Audit.owner_id == identity.user.id)
    if institution_id:
        statement = statement.where(Audit.institution_id == institution_id)
    if cursor:
        statement = statement.where(Audit.id > cursor)
    rows = list(db.scalars(statement.order_by(Audit.id).limit(limit + 1)))
    return {
        "items": [header(row) for row in rows[:limit]],
        "next_cursor": rows[limit - 1].id if len(rows) > limit else None,
    }
