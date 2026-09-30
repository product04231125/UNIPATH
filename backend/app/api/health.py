from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.dependencies import get_session
from app.schemas.common import ErrorResponse
from app.schemas.health import HealthResponse, HealthStatus, ReadyResponse
from app.services.health import check_database

router = APIRouter(prefix="/health", tags=["health"])


@router.get("", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(status=HealthStatus.OK)


@router.get("/ready", response_model=ReadyResponse, responses={503: {"model": ErrorResponse}})
def ready(session: Annotated[Session, Depends(get_session)]) -> ReadyResponse:
    return check_database(session)
