"""Student-readable catalog DTOs exclude administrator actor/audit identifiers."""

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, create_model

from app.schemas import academic


class PublicRecord(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    version: int


class AppliedRecord(PublicRecord):
    status: Literal["applied"]
    lineage_id: UUID
    revision: int
    applied_at: datetime


for prefix in (
    "Department",
    "Curriculum",
    "Course",
    "CurriculumCourse",
    "RuleSet",
    "Rule",
    "Document",
):
    metadata = AppliedRecord if prefix in ("RuleSet", "Rule", "Document") else PublicRecord
    globals()[prefix + "PublicView"] = create_model(
        prefix + "PublicView", __base__=(getattr(academic, prefix + "Create"), metadata)
    )
