"""Public contracts for explicit human review and catalogue-scoped retrieval."""

from datetime import date, datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, Field, StringConstraints, model_validator

from app.schemas.assistant import AssistantCitation, Question, StudyTrack
from app.schemas.auth import Name, StrictModel
from app.schemas.personal import Day

Digest = Annotated[str, StringConstraints(pattern=r"^[0-9a-f]{64}$")]
Version = Annotated[int, Field(ge=1, strict=True)]
Note = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=500)]
Year = Annotated[int, Field(ge=1000, le=9999, strict=True)]


class KnowledgeCreate(StrictModel):
    source_document_id: UUID
    expected_source_version: Version
    document_hash: Digest
    page_count: int = Field(ge=1, le=200, strict=True)
    extractor_version: Name
    source_checked_on: Day


class ChunkPart(StrictModel):
    # Preserve extraction offsets: trimming content would corrupt page reconstruction.
    content: str = Field(min_length=1, max_length=20000)
    admission_years: list[Year] | None = Field(default=None, min_length=1, max_length=200)
    tracks: list[StudyTrack] | None = Field(default=None, min_length=1, max_length=32)
    warnings: list[Name] = Field(default_factory=list, max_length=32)

    @model_validator(mode="after")
    def selections(self):
        if not self.content.strip() or "\x00" in self.content:
            raise ValueError("Page parts need readable text without NUL")
        for values in (self.admission_years, self.tracks, self.warnings):
            if values and len(set(values)) != len(values):
                raise ValueError("Duplicate scope values or warnings")
        return self


class PageReplace(StrictModel):
    expected_version: Version
    is_blank: bool = Field(default=False, strict=True)
    parts: list[ChunkPart] = Field(max_length=20)

    @model_validator(mode="after")
    def bounded_page(self):
        if self.is_blank != (len(self.parts) == 0):
            raise ValueError("Blank pages must be explicitly marked and cannot contain text parts")
        if sum(len(part.content) for part in self.parts) > 20000:
            raise ValueError("A page must contain at most 20000 characters")
        return self


class KnowledgeApprove(StrictModel):
    expected_version: Version
    reviewed_document_hash: Digest
    source_verified: bool = Field(strict=True)
    applicability_verified: bool = Field(strict=True)
    extraction_verified: bool = Field(strict=True)
    complete_document_verified: bool = Field(strict=True)
    review_note: Note

    @model_validator(mode="after")
    def affirmative_review(self):
        if not all(
            (
                self.source_verified,
                self.applicability_verified,
                self.extraction_verified,
                self.complete_document_verified,
            )
        ):
            raise ValueError("All source, scope, extraction and completeness reviews are required")
        return self


class KnowledgeRevoke(StrictModel):
    expected_version: Version
    reason: Note


class KnowledgeView(BaseModel):
    model_config = {"from_attributes": True}
    id: UUID
    institution_id: UUID
    department_id: UUID | None
    curriculum_id: UUID | None
    name: str
    source_document_id: UUID
    source_document_version: int
    version: int
    status: Literal["draft", "approved", "revoked"]
    document_hash: Digest
    page_count: int
    extractor_version: str
    source_checked_on: date
    created_at: datetime
    updated_at: datetime
    approved_by: UUID | None
    approved_at: datetime | None
    review_note: str
    revoked_by: UUID | None
    revoked_at: datetime | None
    revocation_reason: str


class KnowledgeList(BaseModel):
    items: list[KnowledgeView]
    next_cursor: UUID | None = None


class ChunkView(ChunkPart):
    model_config = {"from_attributes": True, "extra": "ignore"}
    id: UUID
    part_index: int
    part_count: int
    character_start: int
    character_end: int
    content_hash: Digest


class PageView(BaseModel):
    knowledge_document_id: UUID
    version: int
    page: int
    page_hash: Digest
    is_blank: bool
    parts: list[ChunkView]


class PageSummary(BaseModel):
    page: int
    part_count: int
    character_count: int
    page_hash: Digest
    is_blank: bool


class PageList(BaseModel):
    items: list[PageSummary]
    next_cursor: int | None = None


class KnowledgeContext(StrictModel):
    institution_id: UUID
    department_id: UUID
    curriculum_id: UUID | None = None
    admission_year: Year | None = None
    track: StudyTrack | None = None


class KnowledgeQuery(StrictModel):
    question: Question
    context: KnowledgeContext


class KnowledgeSearch(KnowledgeQuery):
    limit: int = Field(default=3, ge=1, le=10, strict=True)


class KnowledgeSearchResponse(BaseModel):
    query_id: UUID
    status: Literal["evidence_found", "insufficient_evidence", "needs_user_input", "failed"]
    reason: Literal[
        "approved_sources_found",
        "no_approved_matching_evidence",
        "academic_scope_required",
        "conflicting_admission_year",
        "rule_engine_required",
        "document_context_not_approved_or_incomplete",
        "rag_processing_failed",
    ]
    sources: list[AssistantCitation] = Field(default_factory=list)
    missing_fields: list[str] = Field(default_factory=list)

    @model_validator(mode="after")
    def evidence_only(self):
        if bool(self.sources) != (self.status == "evidence_found"):
            raise ValueError("Only evidence_found may contain approved sources")
        return self
