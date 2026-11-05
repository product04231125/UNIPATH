"""Provider-neutral contract for posting requirements and selected personal evidence."""

from enum import StrEnum
from typing import Annotated, Literal
from uuid import UUID

from pydantic import Field, StringConstraints, model_validator

from app.schemas.auth import StrictModel
from app.schemas.personal import RecordKind
from app.schemas.personalization import PersonalizationRequest

Text = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=2000)]


class JobAnalysisRequest(PersonalizationRequest):
    posting_text: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=20000)
    ]


class RequirementPriority(StrEnum):
    REQUIRED = "required"
    PREFERRED = "preferred"


class ComparisonStatus(StrEnum):
    SUPPORTED = "supported"
    PARTIALLY_SUPPORTED = "partially_supported"
    INSUFFICIENT_EVIDENCE = "insufficient_evidence"


class PostingEvidence(StrictModel):
    start: int = Field(ge=0, lt=20000, strict=True)
    end: int = Field(gt=0, le=20000, strict=True)
    excerpt: Text


class PersonalEvidenceCitation(StrictModel):
    kind: RecordKind
    record_id: UUID
    version: int = Field(ge=1, strict=True)
    excerpt: Text


class JobRequirementComparison(StrictModel):
    requirement_id: UUID
    priority: RequirementPriority
    requirement: Text
    posting_evidence: PostingEvidence
    status: ComparisonStatus
    personal_evidence: list[PersonalEvidenceCitation] = Field(default_factory=list, max_length=20)
    explanation: Text

    @model_validator(mode="after")
    def supporting_evidence(self):
        if self.status != ComparisonStatus.INSUFFICIENT_EVIDENCE and not self.personal_evidence:
            raise ValueError("Supported comparisons need selected personal evidence")
        return self


class JobAnalysisStatus(StrEnum):
    COMPLETED = "completed"
    NEEDS_USER_INPUT = "needs_user_input"
    NOT_CONFIGURED = "not_configured"
    INSUFFICIENT_EVIDENCE = "insufficient_evidence"
    FAILED = "failed"


class JobAnalysisReason(StrEnum):
    COMPARED_WITH_PERSONAL_EVIDENCE = "compared_with_personal_evidence"
    PERSONAL_RECORDS_REQUIRED = "personal_records_required"
    ANALYZER_NOT_CONFIGURED = "analyzer_not_configured"
    NO_REQUIREMENTS_FOUND = "no_requirements_found"
    ANALYSIS_FAILED = "analysis_failed"


class JobAnalysisResponse(StrictModel):
    analysis_id: UUID
    status: JobAnalysisStatus
    reason: JobAnalysisReason
    official: Literal[False] = False
    comparisons: list[JobRequirementComparison] = Field(default_factory=list, max_length=50)
    missing_fields: list[Literal["records"]] = Field(default_factory=list, max_length=1)

    @model_validator(mode="after")
    def completed_evidence(self):
        if bool(self.comparisons) != (self.status == JobAnalysisStatus.COMPLETED):
            raise ValueError("Only completed analyses contain grounded comparisons")
        identifiers = [item.requirement_id for item in self.comparisons]
        if len(identifiers) != len(set(identifiers)):
            raise ValueError("Duplicate posting requirements")
        return self
