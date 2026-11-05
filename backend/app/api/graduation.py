"""Scope-reviewed catalogue completeness and authenticated owner-only graduation audits."""

from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Request

from app.api.auth import CurrentIdentity, Database
from app.schemas import graduation as dto
from app.schemas.assistant import StudyTrack
from app.schemas.personal import Day
from app.services import graduation_audits as audits
from app.services import graduation_catalogs as catalogs

router = APIRouter(prefix="/admin/graduation-catalog-reviews", tags=["graduation catalogue review"])
owner_router = APIRouter(prefix="/me/graduation-audits", tags=["own graduation audits"])


def context_query(
    institution_id: UUID,
    department_id: UUID,
    curriculum_id: UUID,
    admission_year: Annotated[int, Query(ge=1000, le=9999)],
    track: StudyTrack,
):
    return dto.GraduationContext(
        institution_id=institution_id,
        department_id=department_id,
        curriculum_id=curriculum_id,
        admission_year=admission_year,
        track=track,
    )


@router.get("/preview", response_model=dto.CatalogPreview)
def preview(
    db: Database,
    identity: CurrentIdentity,
    context: Annotated[dto.GraduationContext, Depends(context_query)],
    as_of: Day,
):
    return catalogs.admin_preview(db, identity, context, as_of)


@router.post("", response_model=dto.CatalogReviewView, status_code=201)
def create_review(
    payload: dto.CatalogReviewCreate, request: Request, db: Database, identity: CurrentIdentity
):
    return catalogs.create(db, request, payload)


@router.get("", response_model=dto.CatalogReviewList)
def reviews(
    db: Database,
    identity: CurrentIdentity,
    institution_id: UUID | None = None,
    status: Literal["approved", "revoked", "superseded"] | None = None,
    cursor: UUID | None = None,
    limit: Annotated[int, Query(ge=1, le=50)] = 20,
):
    return catalogs.listing(
        db, identity, institution_id=institution_id, status=status, cursor=cursor, limit=limit
    )


@router.get("/{review_id}", response_model=dto.CatalogReviewView)
def review(review_id: UUID, db: Database, identity: CurrentIdentity):
    return catalogs.view(db, catalogs.read(db, identity, review_id))


@router.get("/{review_id}/events", response_model=dto.CatalogReviewEvents)
def review_events(review_id: UUID, db: Database, identity: CurrentIdentity):
    return catalogs.events(db, catalogs.read(db, identity, review_id))


@router.post("/{review_id}/revoke", response_model=dto.CatalogReviewView)
def revoke_review(
    review_id: UUID,
    payload: dto.CatalogReviewRevoke,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return catalogs.revoke(db, request, review_id, payload)


@owner_router.post("", response_model=dto.GraduationAuditView, status_code=201)
def create_audit(
    payload: dto.GraduationAuditCreate, request: Request, db: Database, identity: CurrentIdentity
):
    return audits.create(db, request, payload)


@owner_router.get("", response_model=dto.GraduationAuditList)
def audit_history(
    db: Database,
    identity: CurrentIdentity,
    institution_id: UUID | None = None,
    cursor: UUID | None = None,
    limit: Annotated[int, Query(ge=1, le=50)] = 20,
):
    return audits.listing(db, identity, institution_id=institution_id, cursor=cursor, limit=limit)


@owner_router.get("/{audit_id}", response_model=dto.GraduationAuditView)
def audit(audit_id: UUID, db: Database, identity: CurrentIdentity):
    return audits.view(db, identity, audits.read(db, identity, audit_id))


@owner_router.get("/{audit_id}/guidance", response_model=dto.GraduationGuidance)
def guidance(audit_id: UUID, db: Database, identity: CurrentIdentity):
    from app.services.graduation_guidance import render

    return render(audits.view(db, identity, audits.read(db, identity, audit_id)))
