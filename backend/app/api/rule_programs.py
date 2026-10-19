"""Separate execution review avoids changing the existing metadata editor contract."""

from datetime import UTC, datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Query, Request

from app.api.auth import CurrentIdentity, Database
from app.schemas import rule_programs as dto
from app.schemas.assistant import StudyTrack
from app.schemas.personal import Day
from app.services import rule_programs as service

router = APIRouter(prefix="/admin/rule-programs", tags=["official execution review"])
public_router = APIRouter(prefix="/catalog/rule-programs", tags=["official execution catalog"])


@router.post("", response_model=dto.ProgramView, status_code=201)
def create(payload: dto.ProgramCreate, request: Request, db: Database, identity: CurrentIdentity):
    return service.create(db, request, payload)


@router.get("", response_model=dto.ProgramList)
def listing(
    db: Database,
    identity: CurrentIdentity,
    institution_id: UUID | None = None,
    rule_set_id: UUID | None = None,
    rule_id: UUID | None = None,
    status: Literal["draft", "approved", "revoked"] | None = None,
    cursor: UUID | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 100,
):
    rows = service.listing(
        db, identity, institution_id, status, rule_set_id, rule_id, cursor, limit
    )
    return {"items": rows[:limit], "next_cursor": rows[limit - 1].id if len(rows) > limit else None}


@router.get("/{record_id}", response_model=dto.ProgramView)
def detail(record_id: UUID, db: Database, identity: CurrentIdentity):
    return service.view(db, service.admin_read(db, identity, record_id))


@router.put("/{record_id}", response_model=dto.ProgramView)
def replace(
    record_id: UUID,
    payload: dto.ProgramReplace,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return service.replace(db, request, record_id, payload)


@router.post("/{record_id}/approve", response_model=dto.ProgramView)
def approve(
    record_id: UUID,
    payload: dto.ProgramApprove,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return service.approve(db, request, record_id, payload)


@router.post("/{record_id}/revoke", response_model=dto.ProgramView)
def revoke(
    record_id: UUID,
    payload: dto.ProgramRevoke,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return service.revoke(db, request, record_id, payload)


@router.delete("/{record_id}", status_code=204)
def remove(
    record_id: UUID,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
    expected_version: Annotated[int, Query(ge=1)],
):
    service.remove(db, request, record_id, expected_version)


@public_router.get("", response_model=dto.ProgramSelection)
def selection(
    db: Database,
    identity: CurrentIdentity,
    institution_id: UUID,
    department_id: UUID,
    curriculum_id: UUID,
    admission_year: Annotated[int, Query(ge=1000, le=9999)],
    track: StudyTrack,
    on: Day | None = None,
):
    context = dto.SelectionContext(
        institution_id=institution_id,
        department_id=department_id,
        curriculum_id=curriculum_id,
        admission_year=admission_year,
        track=track,
    )
    return service.selection(db, context, on or datetime.now(UTC).date())


@public_router.get("/{record_id}", response_model=dto.PublicProgram)
def public_detail(record_id: UUID, db: Database, identity: CurrentIdentity, on: Day | None = None):
    return service.public_detail(db, record_id, on or datetime.now(UTC).date())
