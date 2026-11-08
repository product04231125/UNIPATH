"""The three administrator graduation editors; no student data endpoints."""

from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Query, Request

from app.api.auth import CurrentIdentity, Database
from app.models.academic_workspace import AcademicRequirementRevision
from app.schemas import academic_requirements as dto
from app.schemas.academic_workspace import (
    AcademicCopyInput,
    PublicationInput,
    PublicationPreview,
    VersionInput,
)
from app.services import academic_requirements as service
from app.services.academic_workspace import scoped_record

router = APIRouter(
    prefix="/admin/academic/requirement-revisions", tags=["administrator graduation requirements"]
)


@router.get("", response_model=dto.RequirementList)
def listing(
    db: Database,
    identity: CurrentIdentity,
    institution_id: UUID,
    kind: Literal["checklist", "certification", "credit_table"] | None = None,
    cursor: UUID | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
):
    return service.listing(db, identity, institution_id, kind, cursor, limit)


@router.post("", response_model=dto.RequirementView, status_code=201)
def create(
    payload: dto.RequirementCreate, request: Request, db: Database, identity: CurrentIdentity
):
    return service.create(db, request, payload)


@router.get("/{record_id}", response_model=dto.RequirementView)
def detail(record_id: UUID, db: Database, identity: CurrentIdentity):
    return service.view(db, scoped_record(db, identity, AcademicRequirementRevision, record_id))


@router.put("/{record_id}", response_model=dto.RequirementView)
def replace(
    record_id: UUID,
    payload: dto.RequirementReplace,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return service.replace(db, request, identity, record_id, payload)


@router.post("/{record_id}/preview-publication", response_model=PublicationPreview)
def preview(record_id: UUID, payload: VersionInput, db: Database, identity: CurrentIdentity):
    return service.preview(db, identity, record_id, payload)


@router.post("/{record_id}/publish", response_model=dto.RequirementView)
def publish(
    record_id: UUID,
    payload: PublicationInput,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return service.publish(db, request, identity, record_id, payload)


@router.post("/{record_id}/drafts", response_model=dto.RequirementView, status_code=201)
def copy(
    record_id: UUID,
    payload: AcademicCopyInput,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return service.copy_revision(db, request, identity, record_id, payload)


@router.post("/{record_id}/withdraw", response_model=dto.RequirementView)
def withdraw(
    record_id: UUID,
    payload: dto.RequirementWithdrawal,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return service.withdraw(db, request, identity, record_id, payload)
