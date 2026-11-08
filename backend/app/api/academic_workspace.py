"""Administrator workspace only. No student catalog, records or evaluation routes."""

from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Query, Request

from app.api.auth import CurrentIdentity, Database
from app.models.academic_workspace import ClassificationRevision
from app.schemas import academic_workspace as dto
from app.services import academic_workspace as service

router = APIRouter(prefix="/admin/academic", tags=["administrator academic workspace"])
Limit = Annotated[int, Query(ge=1, le=100)]


@router.get("/classification-revisions", response_model=dto.ClassificationList)
def classifications(
    db: Database,
    identity: CurrentIdentity,
    institution_id: UUID,
    status: Literal["draft", "published", "withdrawn"] | None = None,
    cursor: UUID | None = None,
    limit: Limit = 50,
):
    return service.classification_list(db, identity, institution_id, status, cursor, limit)


@router.post("/classification-revisions", response_model=dto.ClassificationView, status_code=201)
def create_classification(
    payload: dto.ClassificationCreate,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return service.create_classification(db, request, payload)


@router.get("/classification-revisions/{record_id}", response_model=dto.ClassificationView)
def classification(record_id: UUID, db: Database, identity: CurrentIdentity):
    return service.classification_view(
        db, service.scoped_record(db, identity, ClassificationRevision, record_id)
    )


@router.put("/classification-revisions/{record_id}", response_model=dto.ClassificationView)
def replace_classification(
    record_id: UUID,
    payload: dto.ClassificationReplace,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return service.replace_classification(db, request, identity, record_id, payload)


@router.post(
    "/classification-revisions/{record_id}/preview-publication",
    response_model=dto.PublicationPreview,
)
def preview_classification(
    record_id: UUID, payload: dto.VersionInput, db: Database, identity: CurrentIdentity
):
    return service.preview_classification(db, identity, record_id, payload)


@router.post("/classification-revisions/{record_id}/publish", response_model=dto.ClassificationView)
def publish_classification(
    record_id: UUID,
    payload: dto.PublicationInput,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return service.publish_classification(db, request, identity, record_id, payload)


@router.get("/study-tracks", response_model=dto.TrackList)
def tracks(
    db: Database,
    identity: CurrentIdentity,
    institution_id: UUID,
    cursor: UUID | None = None,
    limit: Limit = 50,
):
    return service.track_list(db, identity, institution_id, cursor, limit)


@router.post("/study-tracks", response_model=dto.TrackView, status_code=201)
def create_track(
    payload: dto.TrackCreate, request: Request, db: Database, identity: CurrentIdentity
):
    return service.save_track(db, request, identity, payload)


@router.patch("/study-tracks/{record_id}", response_model=dto.TrackView)
def change_track(
    record_id: UUID,
    payload: dto.TrackUpdate,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return service.save_track(db, request, identity, payload, record_id)
