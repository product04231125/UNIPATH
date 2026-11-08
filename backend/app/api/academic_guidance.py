"""Structured guidance menus and collected public documents, without LLM generation."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query, Request
from fastapi.responses import FileResponse

from app.api.auth import CurrentIdentity, Database
from app.schemas.academic_guidance import AcademicGuidance, AssetId, NodeId
from app.schemas.guidance_bindings import (
    GuidanceBindingSave,
    GuidanceBindingView,
    GuidanceBundleList,
    StudentGuidanceBinding,
)
from app.services import academic_guidance, guidance_bindings

router = APIRouter(prefix="/me/academic-guidance", tags=["academic guidance"])
MEDIA_TYPES = {".pdf": "application/pdf", ".jpg": "image/jpeg"}


@router.get("/nodes/{node_id}", response_model=AcademicGuidance)
def node(
    node_id: NodeId,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
    audit_id: UUID | None = None,
    institution_id: UUID | None = None,
):
    """institution_id defaults to the profile school; students may only name that school."""
    return academic_guidance.read_node(db, request, node_id, audit_id, institution_id)


@router.get("/binding", response_model=StudentGuidanceBinding)
def binding(
    request: Request,
    db: Database,
    identity: CurrentIdentity,
    institution_id: UUID | None = None,
):
    return guidance_bindings.student_binding(db, request, institution_id)


@router.get(
    "/assets/{asset_id}",
    response_class=FileResponse,
    responses={
        200: {"content": {"application/pdf": {}, "image/jpeg": {}}, "description": "Public source"}
    },
)
def asset(
    asset_id: AssetId,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
    institution_id: UUID | None = None,
):
    path = academic_guidance.read_asset(db, request, asset_id, institution_id)
    return FileResponse(
        path,
        media_type=MEDIA_TYPES[path.suffix],
        headers={"Content-Disposition": "inline", "X-Content-Type-Options": "nosniff"},
    )


admin = APIRouter(prefix="/admin", tags=["academic guidance"])


@admin.get("/academic-guidance-bundles", response_model=GuidanceBundleList)
def bundles(request: Request, db: Database, identity: CurrentIdentity):
    return guidance_bindings.list_bundles(db, request)


@admin.get("/institutions/{institution_id}/academic-guidance", response_model=GuidanceBindingView)
def school_binding(institution_id: UUID, request: Request, db: Database, identity: CurrentIdentity):
    return guidance_bindings.read(db, request, institution_id)


@admin.put("/institutions/{institution_id}/academic-guidance", response_model=GuidanceBindingView)
def bind(
    institution_id: UUID,
    payload: GuidanceBindingSave,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    """expected_version is 0 to create a link and the current version to replace it."""
    return guidance_bindings.save(db, request, institution_id, payload)


@admin.delete(
    "/institutions/{institution_id}/academic-guidance", response_model=GuidanceBindingView
)
def unbind(
    institution_id: UUID,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
    expected_version: Annotated[int, Query(ge=1)],
):
    return guidance_bindings.remove(db, request, institution_id, expected_version)
