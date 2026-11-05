"""Source review verifies a file, not normalized academic records or graduation."""

from datetime import date, datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator

MAX_FILE_BYTES = 2 * 1024 * 1024
SourceStatus = Literal["submitted", "verified", "rejected", "revoked", "withdrawn"]
DocumentKind = Literal["transcript", "volunteer", "certificate", "thesis", "other"]
Filename = Annotated[str, Field(min_length=1, max_length=128)]
Reason = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=500)]


class Contract(BaseModel):
    model_config = ConfigDict(extra="forbid", from_attributes=True)


class SourceUpload(Contract):
    client_id: UUID
    institution_id: UUID
    department_id: UUID | None = None
    curriculum_id: UUID | None = None
    document_kind: DocumentKind
    issued_on: date
    filename: Filename
    review_consent_confirmed: Literal[True]

    @field_validator("review_consent_confirmed", mode="before")
    @classmethod
    def explicit_consent(cls, value):
        if type(value) is not bool:
            raise ValueError("Explicit boolean confirmation is required")
        return value

    @field_validator("filename")
    @classmethod
    def safe_filename(cls, value):
        if (
            not value.lower().endswith(".pdf")
            or value.startswith(".")
            or any(character in "/\\" or not character.isprintable() for character in value)
        ):
            raise ValueError("Use a PDF filename without paths or control characters")
        return value


class SourceExpectedVersion(Contract):
    expected_version: int = Field(ge=1, strict=True)


class SourceVerify(SourceExpectedVersion):
    expected_sha256: Annotated[str, Field(pattern=r"^[0-9a-f]{64}$")]
    school_issued_confirmed: Literal[True]
    subject_identity_confirmed: Literal[True]

    @field_validator("school_issued_confirmed", "subject_identity_confirmed", mode="before")
    @classmethod
    def explicit_confirmation(cls, value):
        if type(value) is not bool:
            raise ValueError("Explicit boolean confirmation is required")
        return value


class SourceReason(SourceExpectedVersion):
    reason: Reason


class SourceView(Contract):
    id: UUID
    owner_id: UUID
    client_id: UUID
    institution_id: UUID
    department_id: UUID | None
    curriculum_id: UUID | None
    document_kind: DocumentKind
    issued_on: date
    filename: str
    sha256: str
    byte_count: int
    status: SourceStatus
    version: int
    created_at: datetime
    updated_at: datetime
    graduation_eligible: Literal[False] = False


class SourceList(Contract):
    items: list[SourceView]
    next_cursor: UUID | None = None


class SourceEventView(Contract):
    id: UUID
    source_id: UUID
    actor_id: UUID | None
    version: int
    action: SourceStatus
    reason: str
    occurred_at: datetime


class SourceEventList(Contract):
    items: list[SourceEventView]
