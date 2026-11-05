"""Reviewed school records are separate from user-authored personal calculations."""

from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import ConfigDict, Field, StringConstraints, field_validator, model_validator

from app.schemas.assistant import StudyTrack
from app.schemas.auth import Name, StrictModel
from app.schemas.knowledge import Version, Year
from app.schemas.personal import Amount, Day

RecordKind = Literal["academics", "volunteers", "certificates", "theses"]
BatchStatus = Literal["draft", "approved", "revoked", "superseded", "discarded"]
BatchIssue = Literal[
    "source_unavailable",
    "source_changed",
    "reference_changed",
    "context_incomplete",
    "partial_records",
    "not_approved",
    "snapshot_date_mismatch",
]
Page = Annotated[int, Field(strict=True, ge=1, le=500)]


class RecordContract(StrictModel):
    @field_validator("*", mode="after")
    @classmethod
    def printable_labels(cls, value):
        if isinstance(value, str) and not value.isprintable():
            raise ValueError("Use printable single-line record labels")
        return value


class ReviewedContext(RecordContract):
    department_id: UUID | None = None
    curriculum_id: UUID | None = None
    admission_year: Year | None = None
    track: StudyTrack | None = None


class RecordBase(RecordContract):
    client_id: UUID
    source_page: Page


class AcademicRecord(RecordBase):
    course_id: UUID
    expected_course_version: Version
    completion_status: Literal["completed", "failed", "in_progress", "needs_review"]
    earned_credits: Amount | None = None
    category: Name | None = None
    original_grade: Name | None = None
    grade_points: Amount | None = None
    grade_scale: Name | None = None

    @model_validator(mode="after")
    def paired_numeric_grade(self):
        if (self.grade_points is None) != (self.grade_scale is None):
            raise ValueError("Numeric grades require an explicit, matching scale")
        return self


class VolunteerRecord(RecordBase):
    approval_status: Literal["approved", "pending", "rejected", "needs_review"]
    approved_hours: Amount | None = None


class CertificateRecord(RecordBase):
    certificate_id: UUID
    expected_certificate_version: Version
    approval_status: Literal["approved", "pending", "rejected", "needs_review"]
    expires_on: Day | None = None
    validity_known: bool = Field(default=False, strict=True)


class ThesisRecord(RecordBase):
    thesis_type: Name
    approval_status: Literal["approved", "pending", "rejected", "needs_review"]
    is_completed: bool | None = Field(strict=True)
    grade: Name | None = None


class RecordData(RecordContract):
    page_count: Page
    records_as_of: Day
    coverage: Literal["complete", "partial"]
    context: ReviewedContext

    @model_validator(mode="after")
    def bounded_provenance(self):
        records = self.records
        if len({record.client_id for record in records}) != len(records):
            raise ValueError("Duplicate source record identifiers")
        if any(record.source_page > self.page_count for record in records):
            raise ValueError("A source record page exceeds the reviewed original")
        return self


class AcademicData(RecordData):
    kind: Literal["academics"]
    records: list[AcademicRecord] = Field(max_length=500)


class VolunteerData(RecordData):
    kind: Literal["volunteers"]
    records: list[VolunteerRecord] = Field(max_length=500)


class CertificateData(RecordData):
    kind: Literal["certificates"]
    records: list[CertificateRecord] = Field(max_length=500)


class ThesisData(RecordData):
    kind: Literal["theses"]
    records: list[ThesisRecord] = Field(max_length=500)


Payload = Annotated[
    AcademicData | VolunteerData | CertificateData | ThesisData, Field(discriminator="kind")
]


class BatchCreate(StrictModel):
    source_id: UUID
    expected_source_version: Version
    client_id: UUID
    data: Payload


class BatchReplace(StrictModel):
    expected_version: Version
    data: Payload


class BatchApprove(StrictModel):
    expected_version: Version
    expected_source_sha256: Annotated[str, Field(pattern=r"^[0-9a-f]{64}$")]
    records_reviewed: bool = Field(strict=True)
    context_reviewed: bool = Field(strict=True)
    coverage_reviewed: bool = Field(strict=True)
    replaces_batch_id: UUID | None = None
    expected_replaced_version: Version | None = None

    @model_validator(mode="after")
    def explicit_review_and_replacement(self):
        if not all((self.records_reviewed, self.context_reviewed, self.coverage_reviewed)):
            raise ValueError("Explicit record, context and coverage review is required")
        if (self.replaces_batch_id is None) != (self.expected_replaced_version is None):
            raise ValueError("Replacement requires both the previous batch and its version")
        return self


class BatchRevoke(RecordContract):
    expected_version: Version
    reason: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=500)]


class RecordReferenceSnapshot(StrictModel):
    kind: Literal["course", "certificate"]
    id: UUID
    version: Version
    code: str
    name: str
    provider_id: UUID | None = None
    provider_version: Version | None = None
    provider_name: str | None = None


class BatchHeader(StrictModel):
    model_config = ConfigDict(extra="forbid", from_attributes=True)
    id: UUID
    owner_id: UUID
    source_id: UUID
    source_version: Version
    source_sha256: str
    institution_id: UUID
    client_id: UUID
    kind: RecordKind
    status: BatchStatus
    version: Version
    context: ReviewedContext
    coverage: Literal["complete", "partial"]
    page_count: Page
    records_as_of: Day
    record_count: int = Field(ge=0, le=500)
    usable_for_audit: bool
    issues: list[BatchIssue]
    graduation_eligible: Literal[False] = False
    created_at: datetime
    updated_at: datetime


class BatchView(BatchHeader):
    data: Payload
    references: list[RecordReferenceSnapshot]


class BatchList(StrictModel):
    items: list[BatchHeader]
    next_cursor: UUID | None = None


class BatchEventView(StrictModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    batch_id: UUID
    actor_id: UUID | None
    action: Literal[
        "created",
        "replaced",
        "approved",
        "revoked",
        "superseded",
        "source_revoked",
        "source_withdrawn",
        "discarded",
    ]
    version: Version
    reason: str
    occurred_at: datetime


class BatchEventList(StrictModel):
    items: list[BatchEventView]
