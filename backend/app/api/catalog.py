"""Authenticated students read catalog metadata, never administrator drafts."""

from datetime import UTC, datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query
from pydantic import create_model

from app.api.auth import CurrentIdentity, Database
from app.models.identity import Institution
from app.schemas import catalog as dto
from app.schemas.auth import InstitutionView
from app.schemas.personal import Day
from app.services import catalog as service
from app.services.academic import RESOURCES

router = APIRouter(prefix="/catalog", tags=["student catalog"])


def add_resource(path, model, view):
    page = create_model(
        view.__name__ + "List", items=(list[view], ...), next_cursor=(UUID | None, None)
    )

    def listing(
        db: Database,
        identity: CurrentIdentity,
        institution_id: UUID | None = None,
        department_id: UUID | None = None,
        curriculum_id: UUID | None = None,
        rule_set_id: UUID | None = None,
        as_of: Day | None = None,
        query: Annotated[str, Query(max_length=128)] = "",
        cursor: UUID | None = None,
        limit: Annotated[int, Query(ge=1, le=100)] = 100,
    ):
        rows = service.listing(
            db,
            model,
            on=as_of or datetime.now(UTC).date(),
            institution_id=institution_id,
            department_id=department_id,
            curriculum_id=curriculum_id,
            rule_set_id=rule_set_id,
            query=query,
            cursor=cursor,
            limit=limit,
        )
        return {
            "items": rows[:limit],
            "next_cursor": rows[limit - 1].id if len(rows) > limit else None,
        }

    def detail(record_id: UUID, db: Database, identity: CurrentIdentity, as_of: Day | None = None):
        return service.detail(db, model, record_id, as_of or datetime.now(UTC).date())

    router.add_api_route("/" + path, listing, response_model=page, name=view.__name__ + "_list")
    router.add_api_route(
        "/" + path + "/{record_id}", detail, response_model=view, name=view.__name__ + "_detail"
    )


add_resource("institutions", Institution, InstitutionView)
for path, (model, kind) in RESOURCES.items():
    prefix = {"ruleSet": "RuleSet", "curriculumCourse": "CurriculumCourse"}.get(kind, kind.title())
    add_resource(path, model, getattr(dto, prefix + "PublicView"))
