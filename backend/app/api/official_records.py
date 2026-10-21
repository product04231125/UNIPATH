"""School staff review normalized records; owners read only approved history."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query, Request

from app.api.auth import CurrentIdentity, Database
from app.schemas import official_records as dto
from app.services import official_records as service

router = APIRouter(prefix="/admin/official-record-batches", tags=["school record normalization"])
owner_router = APIRouter(prefix="/me/official-record-batches", tags=["own school-reviewed records"])


def add_read_routes(target, *, admin):
    def listing(
        db: Database,
        identity: CurrentIdentity,
        source_id: UUID | None = None,
        institution_id: UUID | None = None,
        kind: dto.RecordKind | None = None,
        status: dto.BatchStatus | None = None,
        cursor: UUID | None = None,
        limit: Annotated[int, Query(ge=1, le=50)] = 20,
    ):
        return service.listing(
            db,
            identity,
            admin=admin,
            source_id=source_id,
            institution_id=institution_id,
            kind=kind,
            status=status,
            cursor=cursor,
            limit=limit,
        )

    def detail(batch_id: UUID, db: Database, identity: CurrentIdentity):
        return service.view(db, service.read(db, identity, batch_id, admin=admin), detail=True)

    def events(batch_id: UUID, db: Database, identity: CurrentIdentity):
        return service.events(db, service.read(db, identity, batch_id, admin=admin))

    for path, handler, model in [
        ("", listing, dto.BatchList),
        ("/{batch_id}", detail, dto.BatchView),
        ("/{batch_id}/events", events, dto.BatchEventList),
    ]:
        target.add_api_route(
            path,
            handler,
            response_model=model,
            name=f"official_records_{'admin' if admin else 'owner'}_{handler.__name__}",
        )


add_read_routes(router, admin=True)
add_read_routes(owner_router, admin=False)


@router.post("", response_model=dto.BatchView, status_code=201)
def create(payload: dto.BatchCreate, request: Request, db: Database, identity: CurrentIdentity):
    return service.create(db, request, payload)


@router.put("/{batch_id}", response_model=dto.BatchView)
def replace(
    batch_id: UUID,
    payload: dto.BatchReplace,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return service.replace(db, request, batch_id, payload)


@router.post("/{batch_id}/approve", response_model=dto.BatchView)
def approve(
    batch_id: UUID,
    payload: dto.BatchApprove,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return service.approve(db, request, batch_id, payload)


@router.post("/{batch_id}/revoke", response_model=dto.BatchView)
def revoke(
    batch_id: UUID,
    payload: dto.BatchRevoke,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return service.end(db, request, batch_id, payload)


@router.post("/{batch_id}/discard", response_model=dto.BatchView)
def discard(
    batch_id: UUID,
    payload: dto.BatchRevoke,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return service.end(db, request, batch_id, payload, discard=True)
