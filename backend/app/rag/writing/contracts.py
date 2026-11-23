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
LongText = Annotated[str, StringConstraints(max_length=20000), AfterValidator(xml_text)]


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid")


class WritingRequest(Strict):
    document_type: Literal["cover_letter", "portfolio"]
    mode: Literal["create", "improve"] = "create"
    target_role: Label
    target_company: str = Field(default="", max_length=120)
    questions: list[Label] = Field(default_factory=list, max_length=6)
    original_text: LongText = ""
    external_processing_consent: bool = Field(default=False, strict=True)

    @model_validator(mode="after")
    def original_mode(self):
        if self.mode == "create" and self.original_text:
            raise ValueError("Use improve mode for an existing draft")
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
    heading: Label
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
