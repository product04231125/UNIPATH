"""Structured guidance menus and collected public documents, without LLM generation."""

from uuid import UUID

from fastapi import APIRouter, Request
from fastapi.responses import FileResponse

from app.api.auth import CurrentIdentity, Database
from app.schemas.academic_guidance import AcademicGuidance, AssetId, NodeId
from app.services import academic_guidance

router = APIRouter(prefix="/me/academic-guidance", tags=["academic guidance"])
MEDIA_TYPES = {".pdf": "application/pdf", ".jpg": "image/jpeg"}


@router.get("/nodes/{node_id}", response_model=AcademicGuidance)
def node(
    node_id: NodeId,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
    audit_id: UUID | None = None,
):
    return academic_guidance.read_node(db, request, node_id, audit_id)


@router.get(
    "/assets/{asset_id}",
    response_class=FileResponse,
    responses={
        200: {"content": {"application/pdf": {}, "image/jpeg": {}}, "description": "Public source"}
    },
)
def asset(asset_id: AssetId, request: Request, db: Database, identity: CurrentIdentity):
    path = academic_guidance.read_asset(db, request, asset_id)
    return FileResponse(
        path,
        media_type=MEDIA_TYPES[path.suffix],
        headers={"Content-Disposition": "inline", "X-Content-Type-Options": "nosniff"},
    )
