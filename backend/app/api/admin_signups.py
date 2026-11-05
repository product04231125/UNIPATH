"""Owned initial/unregistered school receipts and explicit super-administrator review."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query, Request, Response

from app.api.auth import CurrentIdentity, Database
from app.schemas import admin_signups as dto
from app.services import admin_signups as service

router = APIRouter(prefix="/me/school-admin-signups", tags=["own administrator applications"])
admin_router = APIRouter(
    prefix="/admin/school-admin-signups", tags=["administrator application review"]
)


@router.post("", response_model=dto.SchoolAdminSignupView, status_code=201)
def submit(
    payload: dto.SchoolAdminSignupDetails,
    request: Request,
    response: Response,
    db: Database,
    identity: CurrentIdentity,
):
    response.headers["Cache-Control"] = "no-store"
    return service.submit(db, request, payload)


@router.get("", response_model=dto.SchoolAdminSignupList)
def own_list(
    response: Response,
    db: Database,
    identity: CurrentIdentity,
    status: dto.ApplicationStatus | None = None,
    cursor: UUID | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 30,
):
    response.headers["Cache-Control"] = "no-store"
    return service.listing(db, identity, status=status, cursor=cursor, limit=limit)


@router.get("/{application_id}", response_model=dto.SchoolAdminSignupView)
def own_detail(application_id: UUID, response: Response, db: Database, identity: CurrentIdentity):
    response.headers["Cache-Control"] = "no-store"
    return service.view(db, service.read(db, identity, application_id))


@router.post("/{application_id}/cancel", response_model=dto.SchoolAdminSignupView)
def cancel(
    application_id: UUID,
    payload: dto.SchoolAdminSignupCancel,
    request: Request,
    response: Response,
    db: Database,
    identity: CurrentIdentity,
):
    response.headers["Cache-Control"] = "no-store"
    return service.decide(db, request, application_id, payload, decision="cancelled")


@admin_router.get("", response_model=dto.SchoolAdminSignupReviewList)
def review_list(
    response: Response,
    db: Database,
    identity: CurrentIdentity,
    status: dto.ApplicationStatus | None = None,
    cursor: UUID | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 30,
):
    response.headers["Cache-Control"] = "no-store"
    return service.listing(
        db,
        identity,
        admin=True,
        status=status,
        cursor=cursor,
        limit=limit,
    )


@admin_router.get("/{application_id}", response_model=dto.SchoolAdminSignupReviewView)
def review_detail(
    application_id: UUID, response: Response, db: Database, identity: CurrentIdentity
):
    response.headers["Cache-Control"] = "no-store"
    return service.view(db, service.read(db, identity, application_id, admin=True), admin=True)


@admin_router.post("/{application_id}/approve", response_model=dto.SchoolAdminSignupReviewView)
def approve(
    application_id: UUID,
    payload: dto.SchoolAdminSignupApprove,
    request: Request,
    response: Response,
    db: Database,
    identity: CurrentIdentity,
):
    response.headers["Cache-Control"] = "no-store"
    return service.decide(db, request, application_id, payload, decision="approved")


@admin_router.post("/{application_id}/reject", response_model=dto.SchoolAdminSignupReviewView)
def reject(
    application_id: UUID,
    payload: dto.SchoolAdminSignupReject,
    request: Request,
    response: Response,
    db: Database,
    identity: CurrentIdentity,
):
    response.headers["Cache-Control"] = "no-store"
    return service.decide(db, request, application_id, payload, decision="rejected")
