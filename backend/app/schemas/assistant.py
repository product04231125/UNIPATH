from datetime import date
from enum import StrEnum
from typing import Annotated
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, HttpUrl, StringConstraints, model_validator

SchoolName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=128)]
Question = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=4000)]
StudyTrack = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=64)]


class SchoolQueryContext(BaseModel):
    model_config = ConfigDict(extra="forbid")

    institution: SchoolName | None = None
    department: SchoolName | None = None
    admission_year: Annotated[int, Field(strict=True, ge=1000, le=9999)] | None = None
    track: StudyTrack | None = None


class AssistantQueryRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    question: Question
    context: SchoolQueryContext = Field(default_factory=SchoolQueryContext)


class AssistantStatus(StrEnum):
    GROUNDED = "grounded"
    INSUFFICIENT_EVIDENCE = "insufficient_evidence"
    NEEDS_USER_INPUT = "needs_user_input"
    FAILED = "failed"


class AssistantReason(StrEnum):
    EMPTY_QUESTION = "empty_question"
    SCHOOL_CONTEXT_REQUIRED = "school_context_required"
    ACADEMIC_SCOPE_REQUIRED = "academic_scope_required"
    CONFLICTING_ADMISSION_YEAR = "conflicting_admission_year"
    RULE_ENGINE_REQUIRED = "rule_engine_required"
    NO_APPROVED_MATCHING_EVIDENCE = "no_approved_matching_evidence"
    DOCUMENT_CONTEXT_NOT_APPROVED_OR_INCOMPLETE = "document_context_not_approved_or_incomplete"
    ANSWER_GENERATOR_NOT_CONFIGURED = "answer_generator_not_configured"
    INVALID_GENERATOR_OUTPUT = "invalid_generator_output"
    INVALID_GENERATOR_CITATIONS = "invalid_generator_citations"
    GENERATOR_REPORTED_INSUFFICIENT_EVIDENCE = "generator_reported_insufficient_evidence"
    RAG_PROCESSING_FAILED = "rag_processing_failed"
    GENERATED_FROM_EVIDENCE = "generated_from_evidence"


class MissingContextField(StrEnum):
    QUESTION = "question"
    INSTITUTION = "institution"
    DEPARTMENT = "department"
    ADMISSION_YEAR = "admission_year"
    TRACK = "track"
    GRADUATION_AUDIT = "graduation_audit"


class CitationApplicability(BaseModel):
    institution_id: UUID
    department_id: UUID | None
    curriculum_id: UUID | None
    source_version: Annotated[int, Field(ge=1)]
    knowledge_document_id: UUID
    knowledge_version: Annotated[int, Field(ge=1)]
    effective_from: date | None
    effective_to: date | None
    source_checked_on: date
    admission_years: list[int]
    tracks: list[str]


class AssistantCitation(BaseModel):
    chunk_id: UUID
    document_id: UUID
    title: str
    source_url: HttpUrl
    page: Annotated[int, Field(ge=1)]
    excerpt: str
    applicability: CitationApplicability | None = None


class AssistantQueryResponse(BaseModel):
    query_id: UUID
    status: AssistantStatus
    reason: AssistantReason
    answer: str | None = None
    citations: list[AssistantCitation] = Field(default_factory=list)
    missing_fields: list[MissingContextField] = Field(default_factory=list)

    @model_validator(mode="after")
    def validate_grounding(self):
        if self.status == AssistantStatus.GROUNDED:
            if not self.answer or not self.answer.strip() or not self.citations:
                raise ValueError("A grounded answer must include an answer and citations")
        elif self.answer is not None or self.citations:
            raise ValueError("Unconfirmed answers cannot contain an answer or citations")
        return self
