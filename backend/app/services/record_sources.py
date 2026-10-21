"""Owner-submitted, immutable PDF evidence with scoped, serialized manual review."""

import hashlib
import re
from datetime import UTC, datetime

from sqlalchemy import exists, func, select

from app.core.auth_errors import AuthError, conflict, forbidden
from app.models.identity import AdminScope, Institution, Role
from app.models.record_sources import OfficialRecordSource as Source
from app.models.record_sources import OfficialRecordSourceEvent as Event
from app.schemas import record_sources as dto
from app.schemas.common import ErrorCode
from app.services import academic, access, catalog

MAX_OWNER_FILES = 40
MAX_OWNER_BYTES = 32 * 1024 * 1024


def invalid():
    return AuthError(
        422, ErrorCode.VALIDATION_ERROR, "PDF 원본·학교·발급일과 검토 확인을 확인해 주세요."
    )


def missing():
    return AuthError(404, ErrorCode.NOT_FOUND, "요청한 제출 자료를 찾을 수 없습니다.")


def too_large():
    return AuthError(413, ErrorCode.HTTP_ERROR, "PDF는 최대 2 MiB까지 제출할 수 있습니다.")


def validate_pdf(data):
    if len(data) > dto.MAX_FILE_BYTES:
        raise too_large()
    # A bounded format check only. Authenticity/subject matching requires manual
    # issuer verification; no PDF scripts, OCR or extraction are executed here.
    if not re.match(rb"%PDF-(?:1\.[0-7]|2\.0)[\r\n ]", data) or not re.search(
        rb"%%EOF[\r\n\t ]*\Z", data[-1024:]
    ):
        raise invalid()


def owner_read(db, identity, source_id):
    item = db.get(Source, source_id)
    if item is None or item.owner_id != identity.user.id:
        raise missing()
    return item


def admin_read(db, identity, source_id):
    if identity.user.role not in (Role.SUPER_ADMIN, Role.SCHOOL_ADMIN):
        raise forbidden()
    item = db.get(Source, source_id)
    if item is None or item.status == "withdrawn":
        raise missing()
    academic.school(db, identity, item.institution_id)
    return item


def listing(db, identity, *, admin=False, institution_id=None, status=None, cursor=None, limit=100):
    statement = select(Source)
    if admin:
        if identity.user.role not in (Role.SUPER_ADMIN, Role.SCHOOL_ADMIN):
            raise forbidden()
        statement = statement.join(Institution).where(
            Institution.deleted_at.is_(None), Source.status != "withdrawn"
        )
        if institution_id:
            academic.school(db, identity, institution_id)
        if identity.user.role == Role.SCHOOL_ADMIN:
            statement = statement.where(
                exists().where(
                    AdminScope.user_id == identity.user.id,
                    AdminScope.institution_id == Source.institution_id,
                    AdminScope.status == "active",
                )
            )
    else:
        statement = statement.where(Source.owner_id == identity.user.id)
    if institution_id:
        statement = statement.where(Source.institution_id == institution_id)
    if status:
        statement = statement.where(Source.status == status)
    if cursor:
        statement = statement.where(Source.id > cursor)
    rows = list(db.scalars(statement.order_by(Source.id).limit(limit + 1)))
    return {"items": rows[:limit], "next_cursor": rows[limit - 1].id if len(rows) > limit else None}


def event(db, request, identity, item, action, reason=""):
    db.add(
        Event(
            source_id=item.id,
            actor_id=identity.user.id,
            version=item.version,
            action=action,
            reason=reason,
        )
    )
    # No filename, file bytes, subject data or review reasons in shared audit logs.
    access.audit(
        db,
        identity.user.id,
        "record_source_" + action,
        item.id,
        request_id=getattr(request.state, "request_id", None),
        institution_id=item.institution_id,
    )


def upload(db, request, metadata, data):
    validate_pdf(data)
    identity = access.locked_identity(db, request)
    if metadata.issued_on > datetime.now(UTC).date():
        raise invalid()
    institution, department, curriculum = catalog.context(
        db, metadata.institution_id, metadata.department_id, metadata.curriculum_id
    )
    digest = hashlib.sha256(data).hexdigest()
    fields = metadata.model_dump(exclude={"review_consent_confirmed"})
    fields.update(institution_id=institution, department_id=department, curriculum_id=curriculum)
    existing = db.scalar(
        select(Source).where(
            Source.owner_id == identity.user.id, Source.client_id == metadata.client_id
        )
    )
    if existing is not None:
        if existing.sha256 != digest or any(
            getattr(existing, key) != value for key, value in fields.items()
        ):
            raise conflict()
        # A replay never recreates withdrawn evidence or a second review event.
        return existing
    count, size = db.execute(
        select(func.count(), func.coalesce(func.sum(Source.byte_count), 0)).where(
            Source.owner_id == identity.user.id
        )
    ).one()
    if count >= MAX_OWNER_FILES or size + len(data) > MAX_OWNER_BYTES:
        raise conflict()
    item = Source(
        owner_id=identity.user.id, **fields, sha256=digest, byte_count=len(data), file_data=data
    )
    db.add(item)
    db.flush()
    event(db, request, identity, item, "submitted")
    db.commit()
    db.refresh(item)
    return item


def transition(db, request, source_id, payload, action):
    identity = access.locked_identity(db, request)
    item = (owner_read if action == "withdrawn" else admin_read)(db, identity, source_id)
    if item.version != payload.expected_version:
        raise conflict()
    allowed = {
        "verified": {"submitted"},
        "rejected": {"submitted"},
        "revoked": {"verified"},
        "withdrawn": {"submitted", "verified", "rejected", "revoked"},
    }
    if item.status not in allowed[action]:
        raise conflict()
    if action == "verified":
        if item.sha256 != payload.expected_sha256:
            raise conflict()
        if item.owner_id == identity.user.id:
            raise forbidden()
        if hashlib.sha256(item.file_data).hexdigest() != item.sha256:
            raise AuthError(503, ErrorCode.SERVICE_UNAVAILABLE, "자료 무결성을 확인할 수 없습니다.")
    item.status = action
    item.version += 1
    item.updated_at = datetime.now(UTC)
    event(db, request, identity, item, action, getattr(payload, "reason", ""))
    db.commit()
    db.refresh(item)
    return item


def events(db, item):
    return {
        "items": list(
            db.scalars(select(Event).where(Event.source_id == item.id).order_by(Event.version))
        )
    }


def download(db, request, source_id, *, admin):
    identity = access.locked_identity(db, request)
    item = (admin_read if admin else owner_read)(db, identity, source_id)
    data = item.file_data
    if hashlib.sha256(data).hexdigest() != item.sha256:
        raise AuthError(503, ErrorCode.SERVICE_UNAVAILABLE, "자료 무결성을 확인할 수 없습니다.")
    filename = item.filename
    db.rollback()
    return data, filename
