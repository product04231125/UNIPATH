import hashlib
import re
import secrets
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID

from argon2 import PasswordHasher
from argon2.exceptions import VerificationError
from fastapi import Request
from sqlalchemy import case, select, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.auth_errors import AuthError, conflict, forbidden, unauthenticated
from app.core.config import Environment, Settings
from app.models.identity import AdminScope, AuthSession, AuthThrottle, Role, User
from app.schemas.auth import LoginRequest, LoginResponse, MeResponse, RegisterRequest, SessionMode
from app.schemas.common import ErrorCode

PASSWORDS = PasswordHasher(time_cost=2, memory_cost=19456, parallelism=1)
_DUMMY_HASH = PASSWORDS.hash(secrets.token_urlsafe(32))


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def cookie_name(config: Settings) -> str:
    return "unipath_session" if config.app_env == Environment.LOCAL else "__Host-unipath_session"


def check_origin(request: Request, *, cookie: bool = False):
    origin = request.headers.get("origin")
    if (origin is not None and origin not in request.app.state.settings.cors_origins) or (
        cookie and origin is None
    ):
        raise forbidden()


def throttle(db: Session, key: str, *, limit: int):
    """Atomic PostgreSQL bucket; committed attempts survive failed authentication."""
    now = datetime.now(UTC)
    stale = AuthThrottle.window_start <= now - timedelta(minutes=15)
    count = db.scalar(
        insert(AuthThrottle)
        .values(bucket=token_hash(key), window_start=now, attempts=1)
        .on_conflict_do_update(
            index_elements=[AuthThrottle.bucket],
            set_={
                "window_start": case((stale, now), else_=AuthThrottle.window_start),
                "attempts": case((stale, 1), else_=AuthThrottle.attempts + 1),
            },
        )
        .returning(AuthThrottle.attempts)
    )
    db.commit()
    if count > limit:
        raise AuthError(
            429, ErrorCode.RATE_LIMITED, "시도 횟수가 많습니다. 15분 후 다시 시도해 주세요."
        )


@dataclass
class Identity:
    user: User
    session: AuthSession


def current_identity(request: Request, db: Session) -> Identity:
    config = request.app.state.settings
    authorization = request.headers.get("authorization")
    mode = SessionMode.COOKIE
    token = request.cookies.get(cookie_name(config), "")
    if authorization is not None:
        mode = SessionMode.BEARER
        scheme, separator, credential = authorization.partition(" ")
        if scheme.lower() != "bearer" or not separator:
            raise unauthenticated()
        token = credential
    if not re.fullmatch(r"[a-zA-Z0-9_-]{43}", token):
        raise unauthenticated()
    row = db.execute(
        select(User, AuthSession)
        .join(AuthSession, AuthSession.user_id == User.id)
        .where(
            AuthSession.token_hash == token_hash(token),
            AuthSession.mode == mode,
            AuthSession.expires_at > datetime.now(UTC),
            AuthSession.revoked_at.is_(None),
            User.account_status == "active",
        )
    ).first()
    if row is None:
        raise unauthenticated()
    if request.method not in ("GET", "HEAD", "OPTIONS"):
        check_origin(request, cookie=mode == SessionMode.COOKIE)
    return Identity(*row)


def me(db: Session, identity: Identity) -> MeResponse:
    scopes = (
        list(
            db.scalars(
                select(AdminScope)
                .where(AdminScope.user_id == identity.user.id, AdminScope.status == "active")
                .order_by(AdminScope.id)
            )
        )
        if identity.user.role == Role.SCHOOL_ADMIN
        else []
    )
    return MeResponse(
        user=identity.user,
        admin_scopes=scopes,
        permission_version=identity.user.version,
        session_expires_at=identity.session.expires_at,
    )


def establish(db: Session, user: User, mode: SessionMode, config: Settings, request: Request):
    token = secrets.token_urlsafe(32)
    expires = datetime.now(UTC) + timedelta(hours=config.auth_session_hours)
    session = AuthSession(
        token_hash=token_hash(token), user_id=user.id, mode=mode, expires_at=expires
    )
    db.add(session)
    if mode == SessionMode.COOKIE:
        previous = request.cookies.get(cookie_name(config))
        if previous:
            db.execute(
                update(AuthSession)
                .where(AuthSession.token_hash == token_hash(previous), AuthSession.mode == "cookie")
                .values(revoked_at=datetime.now(UTC))
            )
    db.commit()
    result = LoginResponse(**me(db, Identity(user, session)).model_dump())
    if mode == SessionMode.BEARER:
        result.access_token, result.token_type = token, "Bearer"
    return result, token


def login(db: Session, payload: LoginRequest, config: Settings, request: Request):
    check_origin(request, cookie=payload.session_mode == SessionMode.COOKIE)
    throttle(db, "login:" + payload.email, limit=8)
    # Serialize session issuance with suspension. A login that read the old active
    # state must not create an unrevoked session after the suspension transaction.
    user = db.scalar(select(User).where(User.email == payload.email).with_for_update())
    try:
        valid = PASSWORDS.verify(
            user.password_hash if user else _DUMMY_HASH, payload.password.get_secret_value()
        )
    except VerificationError:
        valid = False
    if not valid or user is None or user.account_status != "active":
        raise unauthenticated()
    if PASSWORDS.check_needs_rehash(user.password_hash):
        user.password_hash = PASSWORDS.hash(payload.password.get_secret_value())
    return establish(db, user, payload.session_mode, config, request)


def register(db: Session, payload: RegisterRequest, config: Settings, request: Request):
    check_origin(request, cookie=payload.session_mode == SessionMode.COOKIE)
    throttle(db, "register:" + payload.email, limit=3)
    user = User(
        email=payload.email,
        display_name=payload.display_name,
        password_hash=PASSWORDS.hash(payload.password.get_secret_value()),
        role=Role.USER,
    )
    db.add(user)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise conflict() from None
    return establish(db, user, payload.session_mode, config, request)


def logout(db: Session, identity: Identity, *, all_sessions: bool = False):
    query = update(AuthSession).where(AuthSession.user_id == identity.user.id)
    if not all_sessions:
        query = query.where(AuthSession.token_hash == identity.session.token_hash)
    db.execute(query.values(revoked_at=datetime.now(UTC)))
    db.commit()


def require_institution(db: Session, identity: Identity, institution_id: UUID):
    if identity.user.role == Role.SUPER_ADMIN:
        return
    if identity.user.role != Role.SCHOOL_ADMIN or not db.scalar(
        select(AdminScope.id).where(
            AdminScope.user_id == identity.user.id,
            AdminScope.institution_id == institution_id,
            AdminScope.status == "active",
        )
    ):
        raise forbidden()
