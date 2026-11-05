"""Personal calculation endpoints; no school-official graduation claim."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query, Request

from app.api.auth import CurrentIdentity, Database
from app.schemas.evaluations import (
    PersonalEvaluationCreate,
    PersonalEvaluationList,
    PersonalEvaluationView,
)
from app.services import evaluations as service

router = APIRouter(prefix="/me/personal-evaluations", tags=["personal calculations"])


@router.post("", response_model=PersonalEvaluationView, status_code=201)
def create(
    payload: PersonalEvaluationCreate, request: Request, db: Database, identity: CurrentIdentity
):
    return service.create(db, request, payload)


@router.get("", response_model=PersonalEvaluationList)
def listing(
    db: Database,
    identity: CurrentIdentity,
    curriculum_id: UUID | None = None,
    cursor: UUID | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 100,
):
    rows = service.listing(db, identity.user.id, curriculum_id, cursor, limit)
    return {
        "items": [service.summary(item) for item in rows[:limit]],
        "next_cursor": rows[limit - 1].id if len(rows) > limit else None,
    }


@router.get("/{evaluation_id}", response_model=PersonalEvaluationView)
def detail(evaluation_id: UUID, db: Database, identity: CurrentIdentity):
    return service.view(service.detail(db, identity.user.id, evaluation_id))


@router.delete("/{evaluation_id}", status_code=204)
def remove(
    evaluation_id: UUID,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
    expected_version: Annotated[int, Query(ge=1)],
):
    service.remove(db, request, evaluation_id, expected_version)
