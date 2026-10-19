from typing import Annotated

from fastapi import APIRouter, Depends, Request, Response
from fastapi.security import APIKeyCookie, HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.api.dependencies import get_session
from app.core.config import Environment
from app.schemas.auth import (
    LoginRequest,
    LoginResponse,
    MeResponse,
    PasswordChangeRequest,
    RegisterRequest,
    SessionMode,
)
from app.services import auth

router = APIRouter(prefix="/auth", tags=["authentication"])
Database = Annotated[Session, Depends(get_session)]


def get_identity(
    request: Request,
    db: Database,
    bearer: Annotated[HTTPAuthorizationCredentials | None, Depends(HTTPBearer(auto_error=False))],
    secure_cookie: Annotated[
        str | None, Depends(APIKeyCookie(name="__Host-unipath_session", auto_error=False))
    ],
    local_cookie: Annotated[
        str | None, Depends(APIKeyCookie(name="unipath_session", auto_error=False))
    ],
):
    return auth.current_identity(request, db)


CurrentIdentity = Annotated[auth.Identity, Depends(get_identity)]


def session_response(request: Request, response: Response, payload, result, token):
    config = request.app.state.settings
    response.headers["Cache-Control"] = "no-store"
    if payload.session_mode == SessionMode.COOKIE:
        response.set_cookie(
            auth.cookie_name(config),
            token,
            max_age=config.auth_session_hours * 3600,
            httponly=True,
            secure=config.app_env != Environment.LOCAL,
            samesite="strict",
            path="/",
        )
    return result


@router.post("/register", response_model=LoginResponse, status_code=201)
def register(payload: RegisterRequest, request: Request, response: Response, db: Database):
    result, token = auth.register(db, payload, request.app.state.settings, request)
    return session_response(request, response, payload, result, token)


@router.post("/login", response_model=LoginResponse)
def login(payload: LoginRequest, request: Request, response: Response, db: Database):
    result, token = auth.login(db, payload, request.app.state.settings, request)
    return session_response(request, response, payload, result, token)


@router.get("/me", response_model=MeResponse)
def me(response: Response, db: Database, identity: CurrentIdentity):
    response.headers["Cache-Control"] = "no-store"
    return auth.me(db, identity)


@router.post("/logout", status_code=204)
def logout(request: Request, response: Response, db: Database, identity: CurrentIdentity):
    auth.logout(db, identity)
    response.delete_cookie(
        auth.cookie_name(request.app.state.settings),
        path="/",
        secure=request.app.state.settings.app_env != Environment.LOCAL,
        httponly=True,
        samesite="strict",
    )
    response.headers["Cache-Control"] = "no-store"


@router.post("/logout-all", status_code=204)
def logout_all(request: Request, response: Response, db: Database, identity: CurrentIdentity):
    auth.logout(db, identity, all_sessions=True)
    response.delete_cookie(
        auth.cookie_name(request.app.state.settings),
        path="/",
        secure=request.app.state.settings.app_env != Environment.LOCAL,
        httponly=True,
        samesite="strict",
    )
    response.headers["Cache-Control"] = "no-store"


@router.post("/change-password", status_code=204)
def change_password(
    payload: PasswordChangeRequest,
    request: Request,
    response: Response,
    db: Database,
    identity: CurrentIdentity,
):
    auth.change_password(db, request, payload)
    response.delete_cookie(
        auth.cookie_name(request.app.state.settings),
        path="/",
        secure=request.app.state.settings.app_env != Environment.LOCAL,
        httponly=True,
        samesite="strict",
    )
