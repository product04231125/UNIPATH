"""An authenticated import is a personal append, never a school-data approval."""

from uuid import UUID

from fastapi import APIRouter, Request

from app.api.auth import CurrentIdentity, Database
from app.schemas import personal_imports as dto
from app.schemas.common import ErrorResponse
from app.services import personal_imports as service

router = APIRouter(prefix="/me/personal-imports", tags=["personal workspace import"])


@router.post(
    "",
    response_model=dto.PersonalImportView,
    status_code=201,
    responses={413: {"model": ErrorResponse}},
)
def create(
    payload: dto.PersonalImportCreate, request: Request, db: Database, identity: CurrentIdentity
):
    return service.create(db, request, payload)


@router.get("/{import_id}", response_model=dto.PersonalImportView)
def detail(import_id: UUID, db: Database, identity: CurrentIdentity):
    return service.detail(db, identity.user.id, import_id)
