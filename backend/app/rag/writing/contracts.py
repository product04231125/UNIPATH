"""Bounded, provider-neutral contracts for preview, editing and export."""

from typing import Annotated, Literal
from uuid import UUID

from pydantic import (
    AfterValidator,
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
    model_validator,
)

from app.schemas.academic import safe_url


def xml_text(value):
    if any(
        ord(c) < 32 and c not in "\t\n\r" or 0xD800 <= ord(c) <= 0xDFFF or c in "\ufffe\uffff"
        for c in value
    ):
        raise ValueError("Control characters are not allowed")
    return value


Label = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=120),
    AfterValidator(xml_text),
]
Text = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=1200),
    AfterValidator(xml_text),
]
# Section headings may be a whole 자기소개서 question.
Heading = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=300),
    AfterValidator(xml_text),
]
LongText = Annotated[str, StringConstraints(max_length=20000), AfterValidator(xml_text)]


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid")


RecordKind = Literal["course", "activity", "experience", "credential", "achievement"]


class CompositionRecord(Strict):
    kind: RecordKind
    record_id: UUID


class CompositionGroup(Strict):
    """One target-job requirement and the student's records that show it."""

    requirement: Label
    records: list[CompositionRecord] = Field(min_length=1, max_length=10)


class PostingSource(Strict):
    """The posting a document is written for (from 채용공고 분석). Shown with saved documents;
    only its text (posting_text) and requirements go to the model."""

    source: Literal["saramin", "work24", "jobkorea", "greenhouse", "manual"]
    source_id: str = Field(default="", max_length=200)
    title: Label
    company: str = Field(default="", max_length=120)
    url: Annotated[str, StringConstraints(max_length=2048), AfterValidator(safe_url)] = ""
    # When the posting was analysed (ISO 8601), to show how fresh the comparison is.
    analyzed_at: str = Field(default="", max_length=40)


class PostingRequirement(Strict):
    """One requirement of that posting as 채용공고 분석 compared it with the student's records."""

    requirement: Label
    priority: Literal["required", "preferred"]
    status: Literal["supported", "partially_supported", "insufficient_evidence"]
    records: list[CompositionRecord] = Field(default_factory=list, max_length=10)


class WritingRequest(Strict):
    document_type: Literal["cover_letter", "portfolio"]
    mode: Literal["create", "improve"] = "create"
    target_role: Label
    target_company: str = Field(default="", max_length=120)
    # Optional posting: experiences are chosen and framed for what it asks.
    posting_text: LongText = ""
    questions: list[Heading] = Field(default_factory=list, max_length=6)
    # Characters (spaces included) per question, as application forms count them.
    char_limit: int | None = Field(default=None, ge=200, le=5000, strict=True)
    original_text: LongText = ""
    # Portfolio only: requirements in priority order with the records that show each
    # (포트폴리오 구성, e.g. from the latest 목표 직무 분석).
    composition: list[CompositionGroup] = Field(default_factory=list, max_length=12)
    # The analysed posting this is written for, and its requirements with their evidence.
    posting: PostingSource | None = None
    posting_requirements: list[PostingRequirement] = Field(default_factory=list, max_length=20)
    external_processing_consent: bool = Field(default=False, strict=True)

    @model_validator(mode="after")
    def original_mode(self):
        if self.mode == "create" and self.original_text:
            raise ValueError("Use improve mode for an existing draft")
        if self.composition and self.document_type != "portfolio":
            raise ValueError("Composition is for portfolios")
        return self


class Citation(Strict):
    kind: Literal["course", "activity", "experience", "credential", "achievement"]
    record_id: UUID
    version: int = Field(ge=1, strict=True)
    excerpt: Text


class GroundedText(Strict):
    text: Text
    citations: list[Citation] = Field(min_length=1, max_length=5)


class FactRow(GroundedText):
    label: Label


class Section(Strict):
    heading: Heading
    paragraphs: list[GroundedText] = Field(default_factory=list, max_length=4)
    facts: list[FactRow] = Field(default_factory=list, max_length=8)

    @model_validator(mode="after")
    def nonempty(self):
        if not self.paragraphs and not self.facts:
            raise ValueError("Empty sections are not allowed")
        return self


class Revision(Strict):
    original_excerpt: Text
    section_index: int = Field(ge=0, le=7, strict=True)
    reason: Text


class Draft(Strict):
    sections: list[Section] = Field(min_length=1, max_length=8)
    questions_for_user: list[Label] = Field(default_factory=list, max_length=8)
    revisions: list[Revision] = Field(default_factory=list, max_length=8)

    @model_validator(mode="after")
    def bounded_document(self):
        size = sum(
            len(p.text) for section in self.sections for p in [*section.paragraphs, *section.facts]
        )
        if size > 18000:
            raise ValueError("Document exceeds 18000 characters")
        if any(r.section_index >= len(self.sections) for r in self.revisions):
            raise ValueError("Revision points to an unknown section")
        return self


class EditedText(BaseModel):
    # The owner's edits: citations from generation may come back and are ignored.
    model_config = ConfigDict(extra="ignore")
    text: Text


class EditedFact(EditedText):
    label: Label


class EditedSection(BaseModel):
    model_config = ConfigDict(extra="ignore")
    heading: Heading
    paragraphs: list[EditedText] = Field(default_factory=list, max_length=8)
    facts: list[EditedFact] = Field(default_factory=list, max_length=12)

    @model_validator(mode="after")
    def nonempty(self):
        if not self.paragraphs and not self.facts:
            raise ValueError("Empty sections are not allowed")
        return self


class EditedDocument(BaseModel):
    """What is exported: edited text only, never re-verified and never sent to a model."""

    model_config = ConfigDict(extra="ignore")
    sections: list[EditedSection] = Field(min_length=1, max_length=12)

    @model_validator(mode="after")
    def bounded_document(self):
        size = sum(
            len(p.text) for section in self.sections for p in [*section.paragraphs, *section.facts]
        )
        if size > 24000:
            raise ValueError("Document exceeds 24000 characters")
        return self


class ExportProfile(Strict):
    # Kept outside the LLM payload; insert only values the owner chose for this document.
    name: Label
    email: str = Field(default="", max_length=160)
    phone: str = Field(default="", max_length=80)
    link: str = Field(default="", max_length=300)

    @model_validator(mode="after")
    def safe_text(self):
        for value in (self.email, self.phone, self.link):
            xml_text(value)
        return self


class StoredText(Strict):
    text: Text
    # Citations from generation; the owner's edits keep them but are not re-verified.
    citations: list[Citation] = Field(default_factory=list, max_length=5)


class StoredFact(StoredText):
    label: Label


class StoredSection(Strict):
    heading: Heading
    paragraphs: list[StoredText] = Field(default_factory=list, max_length=8)
    facts: list[StoredFact] = Field(default_factory=list, max_length=12)

    @model_validator(mode="after")
    def nonempty(self):
        if not self.paragraphs and not self.facts:
            raise ValueError("Empty sections are not allowed")
        return self


class StoredDraft(Strict):
    sections: list[StoredSection] = Field(min_length=1, max_length=12)
    questions_for_user: list[Label] = Field(default_factory=list, max_length=8)
    revisions: list[Revision] = Field(default_factory=list, max_length=8)

    @model_validator(mode="after")
    def bounded_document(self):
        size = sum(
            len(p.text) for section in self.sections for p in [*section.paragraphs, *section.facts]
        )
        if size > 24000:
            raise ValueError("Document exceeds 24000 characters")
        if any(r.section_index >= len(self.sections) for r in self.revisions):
            raise ValueError("Revision points to an unknown section")
        return self
