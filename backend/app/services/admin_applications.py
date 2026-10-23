"""Atomic requests and decisions under the existing identity authorization lock."""

import hashlib
from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.auth_errors import AuthError, conflict, forbidden
from app.models.admin_applications import SchoolAdminApplication as Application
from app.models.identity import AdminScope, Institution, Role, User
from app.schemas import admin_applications as dto
from app.schemas.common import ErrorCode
from app.services import access


def _missing():
    return AuthError(404, ErrorCode.NOT_FOUND, "신청을 찾을 수 없습니다.")


def read(db, identity, application_id: UUID, *, admin=False):
    if admin:
        access.require_super(db, identity)
    statement = select(Application).where(Application.id == application_id)
    if not admin:
        statement = statement.where(Application.applicant_id == identity.user.id)
    result = db.scalar(statement)
    if result is None:
        raise _missing()
    return result


def view(db, row, *, admin=False):
    school = db.get(Institution, row.institution_id)
    values = {
        name: getattr(row, name)
        for name in dto.SchoolAdminApplicationView.model_fields
        if name != "institution_name"
    }
    values["institution_name"] = school.name
    if admin:
        user = access.target_user(db, row.applicant_id)
        values["applicant"] = dto.SchoolAdminApplicant.model_validate(user, from_attributes=True)
        return dto.SchoolAdminApplicationReviewView(**values)
    return dto.SchoolAdminApplicationView(**values)


def listing(db, identity, *, admin=False, status=None, institution_id=None, cursor=None, limit=30):
    if admin:
        access.require_super(db, identity)
    statement = select(Application)
    if not admin:
        statement = statement.where(Application.applicant_id == identity.user.id)
    if status is not None:
        statement = statement.where(Application.status == status)
    if institution_id is not None:
        statement = statement.where(Application.institution_id == institution_id)
    if cursor is not None:
        statement = statement.where(Application.id > cursor)
    rows = list(db.scalars(statement.order_by(Application.id).limit(limit + 1)))
    result_type = dto.SchoolAdminApplicationReviewList if admin else dto.SchoolAdminApplicationList
    return result_type(
        items=[view(db, row, admin=admin) for row in rows[:limit]],
        next_cursor=rows[limit - 1].id if len(rows) > limit else None,
    )


def submit(db: Session, request, payload):
    identity = access.locked_identity(db, request)
    fingerprint = hashlib.sha256(payload.model_dump_json().encode()).hexdigest()
    existing = db.scalar(
        select(Application).where(
            Application.applicant_id == identity.user.id, Application.client_id == payload.client_id
        )
    )
    if existing is not None:
        if existing.payload_hash != fingerprint:
            raise conflict()
        return view(db, existing)
    if identity.user.role == Role.SUPER_ADMIN:
        raise forbidden()
    school = db.get(Institution, payload.institution_id)
    if school is None or school.deleted_at is not None:
        raise AuthError(404, ErrorCode.NOT_FOUND, "학교를 찾을 수 없습니다.")
    if db.scalar(
        select(AdminScope.id).where(
            AdminScope.user_id == identity.user.id,
            AdminScope.institution_id == school.id,
            AdminScope.status == "active",
        )
    ):
        raise conflict()
    if db.scalar(
        select(Application.id).where(
            Application.applicant_id == identity.user.id,
            Application.institution_id == school.id,
            Application.status == "pending",
        )
    ):
        raise conflict()
    total = db.scalar(
        select(func.count())
        .select_from(Application)
        .where(Application.applicant_id == identity.user.id)
    )
    pending = db.scalar(
        select(func.count())
        .select_from(Application)
        .where(Application.applicant_id == identity.user.id, Application.status == "pending")
    )
    if total >= 100 or pending >= 5:
        raise AuthError(
            429, ErrorCode.RATE_LIMITED, "관리자 신청 보관 또는 대기 한도에 도달했습니다."
        )
    row = Application(
        applicant_id=identity.user.id, payload_hash=fingerprint, **payload.model_dump()
    )
    db.add(row)
    db.flush()
    access.audit(
        db,
        identity.user.id,
        "admin_application_submitted",
        row.id,
        request.state.request_id,
        row.institution_id,
    )
    db.commit()
    return view(db, row)


def decide(db: Session, request, application_id, payload, *, decision):
    identity = access.locked_identity(db, request)
    admin = decision != "cancelled"
    if admin:
        access.require_super(db, identity)
    row = read(db, identity, application_id, admin=admin)
    if row.status != "pending" or row.version != payload.expected_version:
        raise conflict()
    if admin and row.applicant_id == identity.user.id:
        raise forbidden()
    if decision == "approved":
        user = db.scalar(select(User).where(User.id == row.applicant_id).with_for_update())
        school = db.get(Institution, row.institution_id)
        if (
            user.version != payload.expected_user_version
            or user.account_status != "active"
            or user.role == Role.SUPER_ADMIN
            or school.deleted_at is not None
        ):
            raise conflict()
        if db.scalar(
            select(AdminScope.id).where(
                AdminScope.user_id == user.id,
                AdminScope.institution_id == school.id,
                AdminScope.status == "active",
            )
        ):
            raise conflict()
        scope = AdminScope(
            user_id=user.id,
            institution_id=school.id,
            reason=f"승인된 관리자 신청 {row.id}",
            granted_by=identity.user.id,
        )
        db.add(scope)
        db.flush()
        user.role = Role.SCHOOL_ADMIN
        user.version += 1
        user.updated_at = datetime.now(UTC)
        row.granted_scope_id = scope.id
        row.identity_verified = row.affiliation_verified = True
        access.audit(
            db, identity.user.id, "scope_granted", scope.id, request.state.request_id, school.id
        )
    row.status = decision
    row.version += 1
    row.reviewed_by = identity.user.id
    row.reviewed_at = row.updated_at = datetime.now(UTC)
    row.review_note = payload.review_note if admin else ""
    access.audit(
        db,
        identity.user.id,
        "admin_application_" + decision,
        row.id,
        request.state.request_id,
        row.institution_id,
    )
    db.commit()
    return view(db, row, admin=admin)
