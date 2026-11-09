"""Typed resource routes share scoped service behavior, not arbitrary JSON payloads."""

from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Query, Request, Response
from pydantic import AwareDatetime, create_model

from app.api.auth import CurrentIdentity, Database
from app.models.identity import Institution
from app.schemas import academic as dto
from app.schemas.auth import InstitutionUpdate, InstitutionView
from app.services import academic as service

router = APIRouter(prefix="/admin", tags=["academic catalog"])
Limit = Annotated[int, Query(ge=1, le=100)]


def add_resource(path, create_type, update_type, view_type):
    model, kind = service.RESOURCES[path]
    list_type = create_model(
        f"{view_type.__name__}List", items=(list[view_type], ...), next_cursor=(UUID | None, None)
    )

    def listing(
        db: Database,
        identity: CurrentIdentity,
        institution_id: UUID | None = None,
        query: Annotated[str, Query(max_length=128)] = "",
        status: Literal["active", "inactive", "draft", "applied"] | None = None,
        cursor: UUID | None = None,
        limit: Limit = 100,
    ):
        rows = service.list_records(
            db, identity, model, institution_id, query, status, cursor, limit
        )
        return {
            "items": rows[:limit],
            "next_cursor": rows[limit - 1].id if len(rows) > limit else None,
        }

    def detail(record_id: UUID, db: Database, identity: CurrentIdentity):
        return service.read(db, identity, model, record_id)

    def create(payload: create_type, request: Request, db: Database, identity: CurrentIdentity):
        return service.save(db, request, model, kind, payload)

    def change(
        record_id: UUID,
        payload: update_type,
        request: Request,
        db: Database,
        identity: CurrentIdentity,
    ):
        return service.save(db, request, model, kind, payload, record_id)

    def remove(
        record_id: UUID,
        request: Request,
        db: Database,
        identity: CurrentIdentity,
        expected_version: Annotated[int, Query(ge=1)],
    ):
        service.remove(db, request, model, kind, record_id, expected_version)
        return Response(status_code=204)

    def references(record_id: UUID, db: Database, identity: CurrentIdentity):
        rows = service.references(db, identity, model, record_id)
        return {"items": rows, "total": len(rows)}

    for suffix, endpoint, methods, response, status in [
        ("", listing, ["GET"], list_type, 200),
        ("", create, ["POST"], view_type, 201),
        ("/{record_id}", detail, ["GET"], view_type, 200),
        ("/{record_id}", change, ["PATCH"], view_type, 200),
        ("/{record_id}", remove, ["DELETE"], None, 204),
        ("/{record_id}/references", references, ["GET"], dto.ReferenceList, 200),
    ]:
        router.add_api_route(
            "/" + path + suffix,
            endpoint,
            methods=methods,
            response_model=response,
            status_code=status,
            name=f"{path}_{endpoint.__name__}",
        )

    if model in service.VERSIONED:

        def apply(
            record_id: UUID,
            payload: dto.ExpectedVersion,
            request: Request,
            db: Database,
            identity: CurrentIdentity,
        ):
            return service.review(db, request, model, kind, record_id, payload.expected_version)

        def draft(
            record_id: UUID,
            payload: dto.ExpectedVersion,
            request: Request,
            db: Database,
            identity: CurrentIdentity,
        ):
            return service.review(
                db, request, model, kind, record_id, payload.expected_version, new_draft=True
            )

        router.add_api_route(
            "/" + path + "/{record_id}/apply",
            apply,
            methods=["POST"],
            response_model=view_type,
            name=f"{path}_apply",
        )
        router.add_api_route(
            "/" + path + "/{record_id}/drafts",
            draft,
            methods=["POST"],
            response_model=view_type,
            status_code=201,
            name=f"{path}_draft",
        )


@router.post(
    "/course-placements",
    response_model=dto.CoursePlacementView,
    status_code=201,
    responses={200: {"model": dto.CoursePlacementView, "description": "Earlier submission"}},
)
def place_course(
    payload: dto.CoursePlacementCreate,
    request: Request,
    response: Response,
    db: Database,
    identity: CurrentIdentity,
):
    """Create a course and its curriculum link in one transaction.

    Retrying the same client_id with the same body returns the committed result with 200
    and replayed=true; a different body is 409. Nothing is saved if either part fails.
    """
    result = service.place_course(db, request, payload)
    if result.replayed:
        response.status_code = 200
    return result


@router.get("/course-placements/{client_id}", response_model=dto.CoursePlacementView)
def read_placement(client_id: UUID, request: Request, db: Database, identity: CurrentIdentity):
    """After a lost response: 200 if the submission was committed, 404 if it was not."""
    return service.read_placement(db, request, client_id)


for path, prefix in [
    ("departments", "Department"),
    ("curricula", "Curriculum"),
    ("courses", "Course"),
    ("curriculum-courses", "CurriculumCourse"),
    ("rule-sets", "RuleSet"),
    ("rules", "Rule"),
    ("documents", "Document"),
]:
    add_resource(
        path,
        getattr(dto, prefix + "Create"),
        getattr(dto, prefix + "Update"),
        getattr(dto, prefix + "View"),
    )


@router.patch("/institutions/{institution_id}", response_model=InstitutionView)
def institution_update(
    institution_id: UUID,
    payload: InstitutionUpdate,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return service.update_institution(db, request, institution_id, payload)


@router.delete("/institutions/{institution_id}", status_code=204)
def institution_remove(
    institution_id: UUID,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
    expected_version: Annotated[int, Query(ge=1)],
):
    service.remove(db, request, Institution, "institution", institution_id, expected_version)


@router.get("/institutions/{institution_id}/references", response_model=dto.ReferenceList)
def institution_references(institution_id: UUID, db: Database, identity: CurrentIdentity):
    rows = service.references(db, identity, Institution, institution_id)
    return {"items": rows, "total": len(rows)}


AuditList = create_model(
    "AcademicAuditList", items=(list[dto.AuditView], ...), next_cursor=(UUID | None, None)
)


@router.get("/audit-logs", response_model=AuditList)
def audit_history(
    db: Database,
    identity: CurrentIdentity,
    institution_id: UUID | None = None,
    target_id: UUID | None = None,
    actor_id: UUID | None = None,
    kind: dto.AuditKind | None = None,
    action: Annotated[str, Query(min_length=1, max_length=40)] | None = None,
    occurred_from: Annotated[AwareDatetime | None, Query()] = None,
    occurred_to: Annotated[AwareDatetime | None, Query()] = None,
    cursor: UUID | None = None,
    limit: Limit = 100,
):
    """Filters combine with AND. The period includes occurred_from and excludes occurred_to."""
    if occurred_from and occurred_to and occurred_from >= occurred_to:
        raise service.failure("기간의 시작이 끝보다 앞서야 합니다.", 422)
    filters = {
        "target_id": target_id,
        "actor_id": actor_id,
        "kind": kind,
        "action": action,
        "occurred_from": occurred_from,
        "occurred_to": occurred_to,
    }
    rows = service.history(db, identity, institution_id, cursor, limit, filters)
    return {
        "items": rows[:limit],
        "next_cursor": rows[limit - 1]["id"] if len(rows) > limit else None,
    }
