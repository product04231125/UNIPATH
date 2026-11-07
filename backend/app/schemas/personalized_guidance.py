"""School evidence and personal records stay in separate fields, including in answers."""

from enum import StrEnum
from typing import Literal
from uuid import UUID

from pydantic import Field, model_validator

from app.schemas.auth import StrictModel
from app.schemas.job_analysis import PersonalEvidenceCitation
from app.schemas.knowledge import KnowledgeQuery, KnowledgeSearchResponse
from app.schemas.personalization import PersonalizationContext, PersonalizationRequest


class PersonalizedGuidanceRequest(KnowledgeQuery, PersonalizationRequest):
    external_processing_consent: bool = Field(default=False, strict=True)


class PersonalizedGuidanceStatus(StrEnum):
    GROUNDED = "grounded"
    EVIDENCE_ONLY = "evidence_only"
    NEEDS_USER_INPUT = "needs_user_input"
    INSUFFICIENT_EVIDENCE = "insufficient_evidence"
    FAILED = "failed"


class PersonalizedGuidanceReason(StrEnum):
    GENERATED_FROM_SEPARATED_EVIDENCE = "generated_from_separated_evidence"
    GENERATOR_NOT_CONFIGURED = "generator_not_configured"
    SCHOOL_EVIDENCE_UNAVAILABLE = "school_evidence_unavailable"
    PERSONAL_RECORDS_REQUIRED = "personal_records_required"
    EXTERNAL_PROCESSING_CONSENT_REQUIRED = "external_processing_consent_required"
    GENERATOR_REPORTED_INSUFFICIENT_EVIDENCE = "generator_reported_insufficient_evidence"
    GENERATION_FAILED = "generation_failed"


class PersonalizedGuidanceResponse(StrictModel):
    query_id: UUID
    status: PersonalizedGuidanceStatus
    reason: PersonalizedGuidanceReason
    official: Literal[False] = False
    answer: str | None = None
    # The same retrieval result as /me/school-searches; never includes personal records.
    school: KnowledgeSearchResponse
    # Redacted text: exactly what is eligible to leave this service.
    personal: PersonalizationContext
    school_chunk_ids: list[UUID] = Field(default_factory=list, max_length=10)
    personal_citations: list[PersonalEvidenceCitation] = Field(default_factory=list, max_length=20)
    missing_fields: list[Literal["records", "external_processing_consent"]] = Field(
        default_factory=list, max_length=2
    )

    @model_validator(mode="after")
    def grounded_answer(self):
        grounded = self.status == PersonalizedGuidanceStatus.GROUNDED
        if grounded and (not self.answer or not self.school_chunk_ids):
            raise ValueError("A grounded answer must cite school evidence")
        if not grounded and (self.answer or self.school_chunk_ids or self.personal_citations):
            raise ValueError("Only grounded responses contain an answer or citations")
        return self
