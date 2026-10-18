from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query, Request, Response
from sqlalchemy import select

from app.api.auth import CurrentIdentity, Database
from app.core.auth_errors import forbidden
from app.models.identity import AdminScope, Role, User
from app.schemas.auth import (
    InstitutionCreate,
    InstitutionList,
    InstitutionView,
    RoleChange,
    ScopeCreate,
    ScopeList,
    ScopeRevoke,
    ScopeView,
    StatusChange,
    UserList,
    UserView,
)
from app.services import access

router = APIRouter(prefix="/admin", tags=["identity administration"])


@router.get("/users", response_model=UserList)
def users(
    db: Database,
    identity: CurrentIdentity,
    response: Response,
    cursor: UUID | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 30,
):
    access.require_super(db, identity)
    response.headers["Cache-Control"] = "no-store"
    query = select(User).order_by(User.id).limit(limit + 1)
    if cursor is not None:
        query = query.where(User.id > cursor)
    result = list(db.scalars(query))
    return UserList(
        items=result[:limit], next_cursor=result[limit - 1].id if len(result) > limit else None
    )


@router.patch("/users/{user_id}/role", response_model=UserView)
def role(
    user_id: UUID, payload: RoleChange, request: Request, db: Database, identity: CurrentIdentity
):
    return access.change_user(db, identity, user_id, payload, request.state.request_id)


@router.patch("/users/{user_id}/status", response_model=UserView)
def status(
    user_id: UUID, payload: StatusChange, request: Request, db: Database, identity: CurrentIdentity
):
    return access.change_user(db, identity, user_id, payload, request.state.request_id)


@router.get("/institutions", response_model=InstitutionList)
def institutions(
    db: Database,
    identity: CurrentIdentity,
    query: Annotated[str, Query(max_length=128)] = "",
    cursor: UUID | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 100,
):
    result = access.institutions(db, identity, query, cursor, limit)
    return InstitutionList(
        items=result[:limit], next_cursor=result[limit - 1].id if len(result) > limit else None
    )


@router.post("/institutions", response_model=InstitutionView, status_code=201)
def create_institution(
    payload: InstitutionCreate, request: Request, db: Database, identity: CurrentIdentity
):
    return access.create_institution(db, identity, payload.name, request.state.request_id)


@router.get("/institutions/{institution_id}", response_model=InstitutionView)
def institution(institution_id: UUID, db: Database, identity: CurrentIdentity):
    return access.get_institution(db, identity, institution_id)


@router.get("/scopes", response_model=ScopeList)
def scopes(
    db: Database,
    identity: CurrentIdentity,
    user_id: UUID | None = None,
    cursor: UUID | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 100,
):
    if identity.user.role not in (Role.SCHOOL_ADMIN, Role.SUPER_ADMIN):
        raise forbidden()
    query = select(AdminScope).order_by(AdminScope.id)
    if identity.user.role == Role.SCHOOL_ADMIN:
        query = query.where(AdminScope.user_id == identity.user.id)
    elif user_id is not None:
        query = query.where(AdminScope.user_id == user_id)
    if cursor is not None:
        query = query.where(AdminScope.id > cursor)
    result = list(db.scalars(query.limit(limit + 1)))
    return ScopeList(
        items=result[:limit], next_cursor=result[limit - 1].id if len(result) > limit else None
    )


@router.post("/scopes", response_model=ScopeView, status_code=201)
def grant(payload: ScopeCreate, request: Request, db: Database, identity: CurrentIdentity):
    return access.grant_scope(db, identity, payload, request.state.request_id)


@router.post("/scopes/{scope_id}/revoke", response_model=ScopeView)
def revoke(
    scope_id: UUID, payload: ScopeRevoke, request: Request, db: Database, identity: CurrentIdentity
):
    return access.revoke_scope(
        db, identity, scope_id, payload.expected_version, request.state.request_id
    )
