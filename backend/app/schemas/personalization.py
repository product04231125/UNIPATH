"""Explicit, owner-scoped personal evidence; never official school knowledge."""

from typing import Literal
from uuid import UUID

from pydantic import Field, model_validator

from app.schemas.auth import Name, StrictModel
from app.schemas.personal import RecordKind


class PersonalEvidenceSelection(StrictModel):
    kind: RecordKind
    record_id: UUID
    expected_version: int = Field(ge=1, strict=True)


class PersonalizationRequest(StrictModel):
    records: list[PersonalEvidenceSelection] = Field(default_factory=list, max_length=20)

    @model_validator(mode="after")
    def unique_records(self):
        keys = [(item.kind, item.record_id) for item in self.records]
        if len(keys) != len(set(keys)):
            raise ValueError("Select each personal record once")
        return self


class PersonalEvidence(StrictModel):
    kind: RecordKind
    record_id: UUID
    version: int = Field(ge=1, strict=True)
    origin: Literal["personal"] = "personal"
    official: Literal[False] = False
    title: Name
    text: str = Field(min_length=1, max_length=8000)
    truncated: bool


class PersonalizationContext(StrictModel):
    records: list[PersonalEvidence] = Field(max_length=20)
    official: Literal[False] = False
