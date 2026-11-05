"""Typed global qualification catalogue; possession records remain private and separate."""

from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Query, Request

from app.api.auth import CurrentIdentity, Database
from app.models.certificates import Certificate, CertificateProvider
from app.schemas import certificates as dto
from app.services import certificates as service

router = APIRouter(prefix="/admin", tags=["certificate registry"])
public_router = APIRouter(prefix="/catalog", tags=["certificate catalog"])
Limit = Annotated[int, Query(ge=1, le=100)]


def add_resource(path, model, create_type, view_type, list_type):
    def listing(
        db: Database,
        identity: CurrentIdentity,
        provider_id: UUID | None = None,
        status: Literal["active", "inactive"] | None = None,
        query: Annotated[str, Query(max_length=128)] = "",
        cursor: UUID | None = None,
        limit: Limit = 100,
    ):
        rows = service.listing(
            db,
            model,
            identity=identity,
            provider_id=provider_id,
            status=status,
            query=query,
            cursor=cursor,
            limit=limit,
        )
        return {
            "items": rows[:limit],
            "next_cursor": rows[limit - 1].id if len(rows) > limit else None,
        }

    def detail(record_id: UUID, db: Database, identity: CurrentIdentity):
        return service.get(db, model, record_id, identity=identity)

    def create(payload: create_type, request: Request, db: Database, identity: CurrentIdentity):
        return service.create(db, request, model, payload)

    def change(
        record_id: UUID,
        payload: dto.RegistryUpdate,
        request: Request,
        db: Database,
        identity: CurrentIdentity,
    ):
        return service.update(db, request, model, record_id, payload)

    def activate(
        record_id: UUID,
        payload: dto.RegistryVersion,
        request: Request,
        db: Database,
        identity: CurrentIdentity,
    ):
        return service.status(db, request, model, record_id, payload, active=True)

    def deactivate(
        record_id: UUID,
        payload: dto.RegistryVersion,
        request: Request,
        db: Database,
        identity: CurrentIdentity,
    ):
        return service.status(db, request, model, record_id, payload, active=False)

    def references(record_id: UUID, db: Database, identity: CurrentIdentity):
        return {"items": service.references(db, identity, model, record_id)}

    for suffix, endpoint, methods, response, code in [
        ("", listing, ["GET"], list_type, 200),
        ("", create, ["POST"], view_type, 201),
        ("/{record_id}", detail, ["GET"], view_type, 200),
        ("/{record_id}", change, ["PATCH"], view_type, 200),
        ("/{record_id}/activate", activate, ["POST"], view_type, 200),
        ("/{record_id}/deactivate", deactivate, ["POST"], view_type, 200),
        ("/{record_id}/references", references, ["GET"], dto.RegistryReferences, 200),
    ]:
        router.add_api_route(
            "/" + path + suffix,
            endpoint,
            methods=methods,
            response_model=response,
            status_code=code,
            name=f"{path}_{endpoint.__name__}",
        )

    def public_listing(
        db: Database,
        identity: CurrentIdentity,
        provider_id: UUID | None = None,
        query: Annotated[str, Query(max_length=128)] = "",
        cursor: UUID | None = None,
        limit: Limit = 100,
    ):
        rows = service.listing(
            db, model, public=True, provider_id=provider_id, query=query, cursor=cursor, limit=limit
        )
        return {
            "items": rows[:limit],
            "next_cursor": rows[limit - 1].id if len(rows) > limit else None,
        }

    def public_detail(record_id: UUID, db: Database, identity: CurrentIdentity):
        return service.get(db, model, record_id, public=True)

    public_router.add_api_route(
        "/" + path,
        public_listing,
        methods=["GET"],
        response_model=list_type,
        name=f"catalog_{path}_list",
    )
    public_router.add_api_route(
        "/" + path + "/{record_id}",
        public_detail,
        methods=["GET"],
        response_model=view_type,
        name=f"catalog_{path}_detail",
    )


add_resource(
    "certificate-providers",
    CertificateProvider,
    dto.ProviderCreate,
    dto.ProviderView,
    dto.ProviderList,
)
add_resource(
    "certificates", Certificate, dto.CertificateCreate, dto.CertificateView, dto.CertificateList
)
