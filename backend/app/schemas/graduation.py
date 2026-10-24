"""Reviewed catalogue completeness and owner-only, reproducible graduation audits."""

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import ConfigDict, Field, model_validator

from app.schemas.auth import StrictModel
from app.schemas.evaluations import EvaluationStatus, Total
from app.schemas.knowledge import Digest, Note, Version
from app.schemas.personal import Day
from app.schemas.rule_programs import (
    Condition,
    EvidenceView,
    PublicProgram,
    ReferenceSnapshot,
    SelectionContext,
    SelectionIssue,
)

LABEL = "학교 검토 자료 기준 졸업요건 감사"


class GraduationContext(SelectionContext):
    """Full registered school, department, curriculum, cohort and track are required."""


class CatalogPreview(StrictModel):
    context: GraduationContext
    as_of: Day
    status: Literal["available", "needs_review", "not_applicable"]
    reason: str
    programs: list[PublicProgram]
    issues: list[SelectionIssue]
    snapshot_digest: Digest
    reviewable: bool


class CatalogReviewCreate(StrictModel):
    context: GraduationContext
    as_of: Day
    client_id: UUID
    expected_catalog_digest: Digest
    all_requirements_reviewed: bool = Field(strict=True)
    all_levels_reviewed: bool = Field(strict=True)
    sources_reviewed: bool = Field(strict=True)
    review_note: Note
    replaces_review_id: UUID | None = None
    expected_replaced_version: Version | None = None

    @model_validator(mode="after")
    def explicit_complete_review(self):
        if not all(
            (self.all_requirements_reviewed, self.all_levels_reviewed, self.sources_reviewed)
        ):
            raise ValueError("Explicit complete catalogue and scope review is required")
        if (self.replaces_review_id is None) != (self.expected_replaced_version is None):
            raise ValueError("Replacement requires the previous review and its version")
        if not self.review_note.isprintable():
            raise ValueError("Use a printable single-line review note")
        return self


class CatalogReviewRevoke(StrictModel):
    expected_version: Version
    reason: Note

    @model_validator(mode="after")
    def printable_reason(self):
        if not self.reason.isprintable():
            raise ValueError("Use a printable single-line reason")
        return self


class CatalogReviewHeader(StrictModel):
    id: UUID
    client_id: UUID
    context: GraduationContext
    as_of: Day
    status: Literal["approved", "revoked", "superseded"]
    version: Version
    snapshot_digest: Digest
    created_at: datetime
    updated_at: datetime


class CatalogReviewView(CatalogReviewHeader):
    reviewed_by: UUID | None
    review_note: str
    snapshot: CatalogPreview
    usable: bool
    issues: list[str]


class CatalogReviewList(StrictModel):
    items: list[CatalogReviewHeader]
    next_cursor: UUID | None = None


class CatalogReviewEvent(StrictModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    review_id: UUID
    actor_id: UUID | None
    version: Version
    action: Literal["approved", "revoked", "superseded"]
    reason: str
    occurred_at: datetime


class CatalogReviewEvents(StrictModel):
    items: list[CatalogReviewEvent]


class GraduationAuditCreate(StrictModel):
    context: GraduationContext
    as_of: Day
    client_id: UUID


class AuditEvidence(StrictModel):
    chunk_id: UUID
    knowledge_document_id: UUID
    knowledge_version: Version
    document_id: UUID
    document_version: Version
    title: str
    source_url: str
    page: int
    content_hash: Digest
    document_hash: Digest

    @classmethod
    def from_evidence(cls, evidence: EvidenceView):
        return cls.model_validate(evidence.model_dump(exclude={"excerpt"}))


class AuditedRule(StrictModel):
    rule_id: UUID
    source_version: Version
    title: str
    condition: Condition
    evidence: list[AuditEvidence]
    references: list[ReferenceSnapshot]


class AuditedProgram(StrictModel):
    id: UUID
    version: Version
    rule_set_id: UUID | None
    rule_id: UUID | None
    source_version: Version
    name: str
    rules: list[AuditedRule]


class AuditedBatch(StrictModel):
    id: UUID
    version: Version
    kind: Literal["academics", "volunteers", "certificates", "theses"]
    data_digest: Digest
    source_id: UUID
    source_version: Version
    source_sha256: Digest


class AuditIssue(StrictModel):
    kind: Literal["catalog", "records", "academics", "volunteers", "certificates", "theses"]
    reason: str


class AuditRecordEvidence(StrictModel):
    record_id: UUID
    batch_id: UUID
    client_id: UUID
    kind: Literal["academics", "volunteers", "certificates", "theses"]
    source_page: int = Field(ge=1, le=500, strict=True)


class AuditResultItem(StrictModel):
    rule_set_id: UUID
    rule_set_version: Version
    rule_id: UUID
    title: str
    status: EvaluationStatus
    reason: str
    current: Total | None = None
    required: Total | None = None
    deficit: Total | None = None
    missing_course_ids: list[UUID] = Field(default_factory=list)
    uncertain_course_ids: list[UUID] = Field(default_factory=list)
    evidence_record_ids: list[UUID] = Field(default_factory=list)


class GraduationAuditHeader(StrictModel):
    id: UUID
    owner_id: UUID
    client_id: UUID
    version: Literal[1] = 1
    context: GraduationContext
    evaluated_on: Day
    created_at: datetime
    official: Literal[True] = True
    label: Literal["학교 검토 자료 기준 졸업요건 감사"] = LABEL
    status: EvaluationStatus
    reason: str
    catalog_complete: bool
    eligible_as_of: bool


class GraduationAuditView(GraduationAuditHeader):
    catalog_review_id: UUID | None
    catalog_review_version: Version | None
    catalog_digest: Digest
    criteria: list[AuditedProgram]
    records: list[AuditedBatch]
    record_evidence: list[AuditRecordEvidence]
    results: list[AuditResultItem]
    issues: list[AuditIssue]
    current_usable: bool
    current_issues: list[AuditIssue]


class GraduationAuditList(StrictModel):
    items: list[GraduationAuditHeader]
    next_cursor: UUID | None = None
