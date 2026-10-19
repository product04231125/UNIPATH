"""Authenticated, owner-only APIs for personal planning and draft records."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query, Request
from pydantic import create_model

from app.api.auth import CurrentIdentity, Database
from app.schemas import personal as dto
from app.schemas.academic import ReferenceList
from app.services import personal as service

router = APIRouter(prefix="/me", tags=["personal records"])
Limit = Annotated[int, Query(ge=1, le=100)]


@router.get("/planning-profile", response_model=dto.ProfileView)
def profile(db: Database, identity: CurrentIdentity):
    return service.profile(db, identity.user.id)


@router.patch("/planning-profile", response_model=dto.ProfileView)
def save_profile(
    payload: dto.ProfilePatch, request: Request, db: Database, identity: CurrentIdentity
):
    return service.save_profile(db, request, payload)


def add_resource(path, model, prefix):
    create = getattr(dto, prefix + "Create")
    patch = getattr(dto, prefix + "Patch")
    view = getattr(dto, prefix + "View")
    page = create_model(prefix + "List", items=(list[view], ...), next_cursor=(UUID | None, None))

    def listing(
        db: Database,
        identity: CurrentIdentity,
        query: Annotated[str, Query(max_length=128)] = "",
        cursor: UUID | None = None,
        limit: Limit = 100,
        client_id: UUID | None = None,
        curriculum_id: UUID | None = None,
        starts_before: dto.Instant | None = None,
        ends_after: dto.Instant | None = None,
    ):
        items = service.listing(
            db,
            identity.user.id,
            model,
            query=query,
            cursor=cursor,
            limit=limit,
            client_id=client_id,
            curriculum_id=curriculum_id,
            starts_before=starts_before,
            ends_after=ends_after,
        )
        return {
            "items": [service.view(db, item, prefix) for item in items[:limit]],
            "next_cursor": items[limit - 1].id if len(items) > limit else None,
        }

    def insert(payload, request: Request, db: Database, identity: CurrentIdentity):
        return service.save(db, request, path, payload)

    def detail(record_id: UUID, db: Database, identity: CurrentIdentity):
        return service.view(db, service.get(db, identity.user.id, model, record_id), prefix)

    def update(record_id: UUID, payload, request: Request, db: Database, identity: CurrentIdentity):
        return service.save(db, request, path, payload, record_id)

    def remove(
        record_id: UUID,
        request: Request,
        db: Database,
        identity: CurrentIdentity,
        expected_version: Annotated[int, Query(ge=1)],
    ):
        service.remove(db, request, path, record_id, expected_version)

    def references(record_id: UUID, db: Database, identity: CurrentIdentity):
        rows = service.references(db, identity.user.id, model, record_id)
        return {"items": rows, "total": len(rows)}

    insert.__annotations__["payload"] = create
    update.__annotations__["payload"] = patch
    for method, route, handler, response, status in [
        ("GET", "", listing, page, 200),
        ("POST", "", insert, view, 201),
        ("GET", "/{record_id}", detail, view, 200),
        ("PATCH", "/{record_id}", update, view, 200),
        ("DELETE", "/{record_id}", remove, None, 204),
        ("GET", "/{record_id}/references", references, ReferenceList, 200),
    ]:
        router.add_api_route(
            "/" + path + route,
            handler,
            methods=[method],
            response_model=response,
            status_code=status,
            name=prefix + "_" + handler.__name__,
        )


for path, (model, prefix) in service.RESOURCES.items():
    add_resource(path, model, prefix)
