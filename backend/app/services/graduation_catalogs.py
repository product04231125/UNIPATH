"""Explicit, dated human attestation of the complete applicable rule catalogue."""

from datetime import UTC, datetime
from uuid import uuid4

from pydantic import ValidationError
from sqlalchemy import exists, func, select

from app.core.auth_errors import AuthError, conflict, forbidden
from app.models.graduation import GraduationCatalogReview as Review
from app.models.graduation import GraduationCatalogReviewEvent as Event
from app.models.identity import AdminScope, Institution, Role
from app.schemas import graduation as dto
from app.schemas.common import ErrorCode
from app.services import academic, access, official_records, rule_programs

SCOPE = ("institution_id", "department_id", "curriculum_id", "admission_year", "track")
MAX_SNAPSHOT_BYTES = 4 * 1024 * 1024
MAX_SCHOOL_REVIEWS = 1000


def missing():
    return AuthError(404, ErrorCode.NOT_FOUND, "요청한 졸업요건 검토를 찾을 수 없습니다.")


def corrupt():
    return AuthError(
        503, ErrorCode.SERVICE_UNAVAILABLE, "졸업요건 감사 근거의 무결성을 확인할 수 없습니다."
    )


def context(row):
    return dto.GraduationContext(**{key: getattr(row, key) for key in SCOPE})


def check_date(on):
    if on > datetime.now(UTC).date():
        raise AuthError(
            422, ErrorCode.VALIDATION_ERROR, "미래 날짜의 졸업요건 감사를 실행할 수 없습니다."
        )


def preview(db, scope, on):
    check_date(on)
    selected = rule_programs.selection(db, scope, on, strict_references=True)
    body = selected.model_dump(exclude={"catalog_complete"})
    reviewable = (
        bool(selected.programs)
        and all(issue.reason == "manual_requirement" for issue in selected.issues)
        and selected.reason != "rule_catalog_limit_exceeded"
    )
    if len(official_records.encoded(body)) > MAX_SNAPSHOT_BYTES:
        raise AuthError(413, ErrorCode.HTTP_ERROR, "졸업요건 검토 근거는 최대 4 MiB입니다.")
    return dto.CatalogPreview(
        **body, snapshot_digest=official_records.digest(body), reviewable=reviewable
    )


def admin_preview(db, identity, scope, on):
    if identity.user.role not in (Role.SUPER_ADMIN, Role.SCHOOL_ADMIN):
        raise forbidden()
    academic.school(db, identity, scope.institution_id)
    return preview(db, scope, on)


def header(row):
    return dto.CatalogReviewHeader(
        **{
            key: getattr(row, key)
            for key in (
                "id",
                "client_id",
                "as_of",
                "status",
                "version",
                "snapshot_digest",
                "created_at",
                "updated_at",
            )
        },
        context=context(row),
    )


def snapshot(row):
    try:
        data = dto.CatalogPreview.model_validate(row.snapshot_json)
        body = data.model_dump(exclude={"snapshot_digest", "reviewable"})
        if (
            data.snapshot_digest != row.snapshot_digest
            or official_records.digest(body) != row.snapshot_digest
            or data.context != context(row)
            or data.as_of != row.as_of
            or not data.reviewable
        ):
            raise corrupt()
        return data
    except (ValidationError, ValueError, TypeError):
        raise corrupt() from None


def active(db, scope, on):
    return db.scalar(
        select(Review).where(
            *(getattr(Review, key) == getattr(scope, key) for key in SCOPE),
            Review.as_of == on,
            Review.status == "approved",
        )
    )


def read(db, identity, identifier):
    return academic.read(db, identity, Review, identifier)


def usability(db, row, current=None):
    snapshot(row)
    if row.status != "approved":
        return ["catalog_review_unavailable"]
    try:
        current = current or preview(db, context(row), row.as_of)
    except AuthError as error:
        if error.status == 404:
            return ["catalog_unavailable"]
        raise
    return (
        []
        if current.reviewable and current.snapshot_digest == row.snapshot_digest
        else ["catalog_changed"]
    )


def view(db, row):
    issues = usability(db, row)
    return dto.CatalogReviewView(
        **header(row).model_dump(),
        reviewed_by=row.reviewed_by,
        review_note=row.review_note,
        snapshot=snapshot(row),
        usable=not issues,
        issues=issues,
    )


def listing(db, identity, *, institution_id=None, status=None, cursor=None, limit=20):
    if identity.user.role not in (Role.SUPER_ADMIN, Role.SCHOOL_ADMIN):
        raise forbidden()
    statement = select(Review).join(Institution).where(Institution.deleted_at.is_(None))
    if institution_id:
        academic.school(db, identity, institution_id)
        statement = statement.where(Review.institution_id == institution_id)
    if identity.user.role == Role.SCHOOL_ADMIN:
        statement = statement.where(
            exists().where(
                AdminScope.user_id == identity.user.id,
                AdminScope.institution_id == Review.institution_id,
                AdminScope.status == "active",
            )
        )
    if status:
        statement = statement.where(Review.status == status)
    if cursor:
        statement = statement.where(Review.id > cursor)
    rows = list(db.scalars(statement.order_by(Review.id).limit(limit + 1)))
    return {
        "items": [header(row) for row in rows[:limit]],
        "next_cursor": rows[limit - 1].id if len(rows) > limit else None,
    }


def event(db, request, identity, row, action, reason=""):
    db.add(
        Event(
            review_id=row.id,
            actor_id=identity.user.id,
            version=row.version,
            action=action,
            reason=reason,
        )
    )
    access.audit(
        db,
        identity.user.id,
        "graduation_catalog_" + action,
        row.id,
        request_id=request.state.request_id,
        institution_id=row.institution_id,
    )


def create(db, request, payload):
    with official_records.writes(db):
        identity = access.locked_identity(db, request)
        if identity.user.role not in (Role.SUPER_ADMIN, Role.SCHOOL_ADMIN):
            raise forbidden()
        academic.school(db, identity, payload.context.institution_id)
        creation = official_records.digest(payload)
        existing = db.scalar(
            select(Review).where(
                Review.reviewed_by == identity.user.id, Review.client_id == payload.client_id
            )
        )
        if existing:
            if existing.creation_digest != creation:
                raise conflict()
            return view(db, existing)
        current = preview(db, payload.context, payload.as_of)
        if not current.reviewable or current.snapshot_digest != payload.expected_catalog_digest:
            raise conflict()
        count = db.scalar(
            select(func.count())
            .select_from(Review)
            .where(Review.institution_id == payload.context.institution_id)
        )
        if count >= MAX_SCHOOL_REVIEWS:
            raise conflict()
        previous = active(db, payload.context, payload.as_of)
        if previous is None:
            if payload.replaces_review_id is not None:
                raise conflict()
        else:
            if (
                previous.id != payload.replaces_review_id
                or previous.version != payload.expected_replaced_version
            ):
                raise conflict()
            previous.status = "superseded"
            previous.version += 1
            previous.updated_at = datetime.now(UTC)
            event(db, request, identity, previous, "superseded")
            db.flush()
        row = Review(
            id=uuid4(),
            client_id=payload.client_id,
            reviewed_by=identity.user.id,
            creation_digest=creation,
            snapshot_digest=current.snapshot_digest,
            snapshot_json=official_records.wire(current),
            review_note=payload.review_note,
            version=1,
            status="approved",
            as_of=payload.as_of,
            **payload.context.model_dump(),
        )
        db.add(row)
        db.flush()
        event(db, request, identity, row, "approved")
        db.commit()
        db.refresh(row)
        return view(db, row)


def revoke(db, request, identifier, payload):
    with official_records.writes(db):
        identity = access.locked_identity(db, request)
        row = read(db, identity, identifier)
        if row.version != payload.expected_version or row.status != "approved":
            raise conflict()
        row.status = "revoked"
        row.version += 1
        row.updated_at = datetime.now(UTC)
        event(db, request, identity, row, "revoked", payload.reason)
        db.commit()
        db.refresh(row)
        return view(db, row)


def events(db, row):
    return {
        "items": list(
            db.scalars(select(Event).where(Event.review_id == row.id).order_by(Event.version))
        )
    }
