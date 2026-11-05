"""Account and initial receipt commit together; school and access require review."""

import hashlib
from datetime import UTC, datetime
from uuid import UUID

from argon2.exceptions import VerificationError
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.auth_errors import AuthError, conflict, forbidden, unauthenticated
from app.models.admin_signups import SchoolAdminSignup as Signup
from app.models.identity import AdminScope, Institution, Role, User
from app.schemas import admin_signups as dto
from app.schemas.common import ErrorCode
from app.services import access, auth


def view(db, row, *, admin=False):
    values = {
        name: getattr(row, name)
        for name in dto.SchoolAdminSignupView.model_fields
        if name != "institution_name"
    }
    school = db.get(Institution, row.institution_id) if row.institution_id else None
    values["institution_name"] = school.name if school else None
    if admin:
        values["applicant"] = dto.SchoolAdminApplicant.model_validate(
            access.target_user(db, row.applicant_id), from_attributes=True
        )
        return dto.SchoolAdminSignupReviewView(**values)
    return dto.SchoolAdminSignupView(**values)


def read(db, identity, signup_id, *, admin=False):
    if admin:
        access.require_super(db, identity)
    query = select(Signup).where(Signup.id == signup_id)
    if not admin:
        query = query.where(Signup.applicant_id == identity.user.id)
    row = db.scalar(query)
    if row is None:
        raise AuthError(404, ErrorCode.NOT_FOUND, "가입·학교 신청을 찾을 수 없습니다.")
    return row


def listing(db, identity, *, admin=False, status=None, cursor=None, limit=30):
    if admin:
        access.require_super(db, identity)
    query = select(Signup)
    if not admin:
        query = query.where(Signup.applicant_id == identity.user.id)
    if status is not None:
        query = query.where(Signup.status == status)
    if cursor is not None:
        query = query.where(Signup.id > cursor)
    rows = list(db.scalars(query.order_by(Signup.id).limit(limit + 1)))
    model = dto.SchoolAdminSignupReviewList if admin else dto.SchoolAdminSignupList
    return model(
        items=[view(db, row, admin=admin) for row in rows[:limit]],
        next_cursor=rows[limit - 1].id if len(rows) > limit else None,
    )


def _fingerprint(payload):
    return hashlib.sha256(payload.model_dump_json().encode()).hexdigest()


def _create(db, user, payload, request_id):
    existing = db.scalar(
        select(Signup).where(Signup.applicant_id == user.id, Signup.client_id == payload.client_id)
    )
    fingerprint = _fingerprint(payload)
    if existing is not None:
        if existing.payload_hash != fingerprint:
            raise conflict()
        return existing
    if user.role == Role.SUPER_ADMIN:
        raise forbidden()
    key = payload.school_name.casefold()
    if db.scalar(
        select(Signup.id).where(
            Signup.applicant_id == user.id, Signup.school_key == key, Signup.status == "pending"
        )
    ):
        raise conflict()
    total = db.scalar(
        select(func.count()).select_from(Signup).where(Signup.applicant_id == user.id)
    )
    pending = db.scalar(
        select(func.count())
        .select_from(Signup)
        .where(Signup.applicant_id == user.id, Signup.status == "pending")
    )
    if total >= 100 or pending >= 5:
        raise AuthError(
            429, ErrorCode.RATE_LIMITED, "가입·학교 신청 보관 또는 대기 한도에 도달했습니다."
        )
    row = Signup(
        applicant_id=user.id, payload_hash=fingerprint, school_key=key, **payload.model_dump()
    )
    db.add(row)
    db.flush()
    access.audit(db, user.id, "school_signup_submitted", row.id, request_id)
    return row


def register(db: Session, request, payload):
    auth.check_origin(request, cookie=payload.session_mode == "cookie")
    auth.throttle(db, "register:" + payload.email, limit=3)
    access.lock_identity(db)
    user = db.scalar(select(User).where(User.email == payload.email).with_for_update())
    details = dto.SchoolAdminSignupDetails.model_validate(payload.model_dump(), extra="ignore")
    if user is not None:
        row = db.scalar(
            select(Signup).where(
                Signup.applicant_id == user.id, Signup.client_id == payload.client_id
            )
        )
        if (
            row is None
            or row.payload_hash != _fingerprint(details)
            or user.display_name != payload.display_name
        ):
            raise conflict()
        try:
            valid = auth.PASSWORDS.verify(user.password_hash, payload.password.get_secret_value())
        except VerificationError:
            valid = False
        if not valid or user.account_status != "active":
            raise unauthenticated()
    else:
        user = auth.create_user(db, payload)
        row = _create(db, user, details, request.state.request_id)
    result, token = auth.establish(
        db, user, payload.session_mode, request.app.state.settings, request
    )
    return dto.SchoolAdminSignupResponse(**result.model_dump(), signup=view(db, row)), token


def submit(db, request, payload):
    identity = access.locked_identity(db, request)
    row = _create(db, identity.user, payload, request.state.request_id)
    db.commit()
    return view(db, row)


def decide(db, request, signup_id: UUID, payload, *, decision):
    identity = access.locked_identity(db, request)
    admin = decision != "cancelled"
    if admin:
        access.require_super(db, identity)
    row = read(db, identity, signup_id, admin=admin)
    if row.status != "pending" or row.version != payload.expected_version:
        raise conflict()
    if admin and row.applicant_id == identity.user.id:
        raise forbidden()
    if decision == "approved":
        user = db.scalar(select(User).where(User.id == row.applicant_id).with_for_update())
        if (
            user.account_status != "active"
            or user.role == Role.SUPER_ADMIN
            or user.version != payload.expected_user_version
        ):
            raise conflict()
        if payload.new_institution is not None:
            school = Institution(**payload.new_institution.model_dump())
            db.add(school)
            try:
                db.flush()
            except IntegrityError:
                db.rollback()
                raise conflict() from None
            access.audit(
                db,
                identity.user.id,
                "institution_created",
                school.id,
                request.state.request_id,
                school.id,
            )
        else:
            school = db.get(Institution, payload.institution_id)
            if (
                school is None
                or school.deleted_at is not None
                or school.version != payload.expected_institution_version
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
            reason=f"승인된 최초·학교 신청 {row.id}",
            granted_by=identity.user.id,
        )
        db.add(scope)
        db.flush()
        user.role = Role.SCHOOL_ADMIN
        user.version += 1
        user.updated_at = datetime.now(UTC)
        row.institution_id = school.id
        row.granted_scope_id = scope.id
        row.identity_verified = row.affiliation_verified = True
        access.audit(
            db, identity.user.id, "scope_granted", scope.id, request.state.request_id, school.id
        )
    row.status = decision
    row.version += 1
    row.reviewed_at = row.updated_at = datetime.now(UTC)
    row.reviewed_by = identity.user.id
    row.review_note = payload.review_note if admin else ""
    access.audit(
        db,
        identity.user.id,
        "school_signup_" + decision,
        row.id,
        request.state.request_id,
        row.institution_id,
    )
    db.commit()
    return view(db, row, admin=admin)
