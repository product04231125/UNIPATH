"""Server authorization. The identity lock serializes privilege-changing transactions."""

from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import exists, func, select, text, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.auth_errors import AuthError, conflict, forbidden, unauthenticated
from app.models.identity import AdminScope, AuthSession, IdentityAudit, Institution, Role, User
from app.schemas.auth import RoleChange, ScopeCreate, StatusChange, UserAccessChange
from app.schemas.common import ErrorCode
from app.services.auth import Identity, current_identity, require_institution


def lock_identity(db: Session):
    db.execute(text("SELECT pg_advisory_xact_lock(867420)"))


def locked_identity(db: Session, request):
    """Recheck the session after serializing with privilege changes."""
    lock_identity(db)
    db.expire_all()
    return current_identity(request, db)


def require_super(db: Session, identity: Identity, *, lock: bool = False):
    if lock:
        lock_identity(db)
        session = db.scalar(
            select(AuthSession)
            .where(AuthSession.token_hash == identity.session.token_hash)
            .execution_options(populate_existing=True)
        )
        if (
            session is None
            or session.revoked_at is not None
            or session.expires_at <= datetime.now(UTC)
        ):
            raise unauthenticated()
    # Reload after acquiring the lock; the dependency may predate another change.
    actor = db.scalar(
        select(User).where(User.id == identity.user.id).execution_options(populate_existing=True)
    )
    if actor is None or actor.role != Role.SUPER_ADMIN or actor.account_status != "active":
        raise forbidden()


def audit(
    db: Session,
    actor: UUID,
    action: str,
    target: UUID,
    request_id: UUID | None = None,
    institution_id: UUID | None = None,
):
    db.add(
        IdentityAudit(
            actor_id=actor,
            action=action,
            target_id=target,
            request_id=request_id,
            institution_id=institution_id,
        )
    )


def target_user(db: Session, user_id: UUID) -> User:
    user = db.get(User, user_id)
    if user is None:
        raise AuthError(404, ErrorCode.NOT_FOUND, "요청한 계정을 찾을 수 없습니다.")
    return user


def change_user(
    db: Session,
    identity: Identity,
    user_id: UUID,
    payload: RoleChange | StatusChange | UserAccessChange,
    request_id: UUID,
):
    require_super(db, identity, lock=True)
    user = target_user(db, user_id)
    if user.id == identity.user.id:
        raise forbidden()
    if user.version != payload.expected_version:
        raise conflict()
    if user.role == Role.SUPER_ADMIN and user.account_status == "active":
        remaining = db.scalar(
            select(func.count())
            .select_from(User)
            .where(
                User.role == Role.SUPER_ADMIN, User.account_status == "active", User.id != user.id
            )
        )
        if not remaining:
            raise conflict()
    if isinstance(payload, RoleChange):
        user.role = payload.role
        action = "role_changed"
        if payload.role != Role.SCHOOL_ADMIN:
            db.execute(
                update(AdminScope)
                .where(AdminScope.user_id == user.id, AdminScope.status == "active")
                .values(
                    status="revoked",
                    revoked_by=identity.user.id,
                    revoked_at=datetime.now(UTC),
                    version=AdminScope.version + 1,
                )
            )
    if isinstance(payload, (StatusChange, UserAccessChange)):
        user.account_status = payload.account_status
        action = "account_status_changed"
        if payload.account_status == "suspended":
            db.execute(
                update(AuthSession)
                .where(AuthSession.user_id == user.id)
                .values(revoked_at=datetime.now(UTC))
            )
    if isinstance(payload, UserAccessChange):
        action = "access_changed"
    user.version += 1
    user.updated_at = datetime.now(UTC)
    audit(db, identity.user.id, action, user.id, request_id)
    db.commit()
    return user


def institutions(
    db: Session, identity: Identity, query: str, cursor: UUID | None = None, limit: int = 100
):
    if identity.user.role not in (Role.SCHOOL_ADMIN, Role.SUPER_ADMIN):
        raise forbidden()
    statement = select(Institution).where(Institution.deleted_at.is_(None))
    if identity.user.role == Role.SCHOOL_ADMIN:
        statement = statement.where(
            exists().where(
                AdminScope.institution_id == Institution.id,
                AdminScope.user_id == identity.user.id,
                AdminScope.status == "active",
            )
        )
    if query:
        statement = statement.where(Institution.name.icontains(query, autoescape=True))
    if cursor is not None:
        statement = statement.where(Institution.id > cursor)
    return list(db.scalars(statement.order_by(Institution.id).limit(limit + 1)))


def create_institution(
    db: Session,
    identity: Identity,
    name: str,
    request_id: UUID,
    country_code: str = "",
    official_url: str = "",
):
    require_super(db, identity, lock=True)
    school = Institution(name=name, country_code=country_code, official_url=official_url)
    db.add(school)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise conflict() from None
    audit(db, identity.user.id, "institution_created", school.id, request_id, school.id)
    db.commit()
    return school


def grant_scope(db: Session, identity: Identity, payload: ScopeCreate, request_id: UUID):
    require_super(db, identity, lock=True)
    user = target_user(db, payload.user_id)
    if user.account_status != "active" or user.role == Role.SUPER_ADMIN:
        raise conflict()
    institution = db.get(Institution, payload.institution_id)
    if institution is None or institution.deleted_at is not None:
        raise AuthError(404, ErrorCode.NOT_FOUND, "학교를 찾을 수 없습니다.")
    scope = AdminScope(
        user_id=user.id,
        institution_id=payload.institution_id,
        reason=payload.reason.strip(),
        granted_by=identity.user.id,
    )
    db.add(scope)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise conflict() from None
    user.role = Role.SCHOOL_ADMIN
    user.version += 1
    user.updated_at = datetime.now(UTC)
    audit(db, identity.user.id, "scope_granted", scope.id, request_id, payload.institution_id)
    db.commit()
    return scope


def revoke_scope(
    db: Session,
    identity: Identity,
    scope_id: UUID,
    version: int,
    request_id: UUID,
    reason: str = "",
):
    require_super(db, identity, lock=True)
    scope = db.get(AdminScope, scope_id)
    if scope is None:
        raise AuthError(404, ErrorCode.NOT_FOUND, "관리 범위를 찾을 수 없습니다.")
    if scope.status != "active" or scope.version != version:
        raise conflict()
    scope.status, scope.revoked_by, scope.revoked_at = (
        "revoked",
        identity.user.id,
        datetime.now(UTC),
    )
    scope.version += 1
    scope.revocation_reason = reason.strip()
    user = target_user(db, scope.user_id)
    user.version += 1
    user.updated_at = datetime.now(UTC)
    audit(db, identity.user.id, "scope_revoked", scope.id, request_id, scope.institution_id)
    db.commit()
    return scope


def get_institution(db: Session, identity: Identity, institution_id: UUID):
    require_institution(db, identity, institution_id)
    school = db.get(Institution, institution_id)
    if school is None or school.deleted_at is not None:
        raise AuthError(404, ErrorCode.NOT_FOUND, "학교를 찾을 수 없습니다.")
    return school
