"""Explicit execution criteria, reviewed source references and catalog selection."""

from datetime import date, datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, Field, TypeAdapter, model_validator

from app.schemas.assistant import StudyTrack
from app.schemas.auth import Name, StrictModel
from app.schemas.knowledge import Note, Version, Year
from app.schemas.personal import Amount


class CreditCriterion(StrictModel):
    kind: Literal["minimum_credits"]
    minimum: Amount
    category: Name | None = None


class ProgramRequiredCourse(StrictModel):
    course_id: UUID
    expected_version: Version
    minimum_credits: Amount | None = None
    minimum_grade_points: Amount | None = None
    comparison_grade_scale: Name | None = None

    @model_validator(mode="after")
    def comparable_grade(self):
        if (self.minimum_grade_points is None) != (self.comparison_grade_scale is None):
            raise ValueError("Numeric grade thresholds require an explicit matching scale")
        return self


class CourseCriterion(StrictModel):
    kind: Literal["required_courses"]
    courses: list[ProgramRequiredCourse] = Field(min_length=1, max_length=100)

    @model_validator(mode="after")
    def unique_courses(self):
        if len({course.course_id for course in self.courses}) != len(self.courses):
            raise ValueError("Duplicate course requirements")
        return self


class VolunteerCriterion(StrictModel):
    kind: Literal["minimum_volunteer_hours"]
    minimum: Amount


class CertificateChoice(StrictModel):
    certificate_id: UUID
    expected_version: Version


class CertificateCriterion(StrictModel):
    kind: Literal["any_certificate"]
    certificates: list[CertificateChoice] = Field(min_length=1, max_length=100)

    @model_validator(mode="after")
    def unique_certificates(self):
        if len({value.certificate_id for value in self.certificates}) != len(self.certificates):
            raise ValueError("Duplicate certificate alternatives")
        return self


class ThesisCriterion(StrictModel):
    kind: Literal["thesis"]
    thesis_type: Name
    requires_approval: bool = Field(default=True, strict=True)
    accepted_grades: list[Name] = Field(default_factory=list, max_length=20)

    @model_validator(mode="after")
    def unique_grades(self):
        if len(set(self.accepted_grades)) != len(self.accepted_grades):
            raise ValueError("Duplicate acceptable grades")
        return self


class ManualCriterion(StrictModel):
    kind: Literal["manual_review"]
    instruction: Note


Condition = Annotated[
    CreditCriterion
    | CourseCriterion
    | VolunteerCriterion
    | CertificateCriterion
    | ThesisCriterion
    | ManualCriterion,
    Field(discriminator="kind"),
]
condition_adapter = TypeAdapter(Condition)


class ProgramRuleInput(StrictModel):
    rule_id: UUID
    expected_version: Version
    condition: Condition
    evidence_chunk_ids: list[UUID] = Field(min_length=1, max_length=8)

    @model_validator(mode="after")
    def unique_evidence(self):
        if len(set(self.evidence_chunk_ids)) != len(self.evidence_chunk_ids):
            raise ValueError("Duplicate evidence references")
        return self


class ProgramData(StrictModel):
    admission_year_from: Year
    admission_year_to: Year
    tracks: list[StudyTrack] = Field(min_length=1, max_length=32)
    rules: list[ProgramRuleInput] = Field(default_factory=list, max_length=100)

    @model_validator(mode="after")
    def scope_and_rules(self):
        if not 0 <= self.admission_year_to - self.admission_year_from < 200:
            raise ValueError("Use an ordered admission interval of at most 200 years")
        if len(set(self.tracks)) != len(self.tracks):
            raise ValueError("Duplicate tracks")
        if len({r.rule_id for r in self.rules}) != len(self.rules):
            raise ValueError("Duplicate source rule definitions")
        if sum(len(r.evidence_chunk_ids) for r in self.rules) > 500:
            raise ValueError("Select at most 500 evidence references")
        references = sum(
            len(r.condition.courses)
            if isinstance(r.condition, CourseCriterion)
            else len(r.condition.certificates)
            if isinstance(r.condition, CertificateCriterion)
            else 0
            for r in self.rules
        )
        if references > 500:
            raise ValueError("Select at most 500 master record references")
        return self


class ProgramCreate(ProgramData):
    rule_set_id: UUID | None = None
    rule_id: UUID | None = None
    expected_source_version: Version

    @model_validator(mode="after")
    def single_target(self):
        if (self.rule_set_id is None) == (self.rule_id is None):
            raise ValueError("Select an applied rule set or an applied standalone rule")
        return self


class ProgramReplace(ProgramData):
    expected_version: Version


class ProgramApprove(StrictModel):
    expected_version: Version
    conditions_verified: bool = Field(strict=True)
    sources_verified: bool = Field(strict=True)
    applicability_verified: bool = Field(strict=True)
    complete_source_context_verified: bool = Field(strict=True)
    review_note: Note

    @model_validator(mode="after")
    def explicit_review(self):
        if not all(
            (
                self.conditions_verified,
                self.sources_verified,
                self.applicability_verified,
                self.complete_source_context_verified,
            )
        ):
            raise ValueError("All execution, source, scope and context reviews are required")
        return self


class ProgramRevoke(StrictModel):
    expected_version: Version
    reason: Note


class EvidenceView(BaseModel):
    chunk_id: UUID
    knowledge_document_id: UUID
    knowledge_version: int
    document_id: UUID
    document_version: int
    title: str
    source_url: str
    page: int
    content_hash: str
    document_hash: str
    excerpt: str


class ReferenceSnapshot(BaseModel):
    kind: Literal["course", "certificate"]
    record_id: UUID
    version: int
    code: str
    name: str
    provider_name: str | None = None


class ProgramRuleView(BaseModel):
    rule_id: UUID
    source_version: int
    title: str
    condition: Condition
    evidence: list[EvidenceView]
    references: list[ReferenceSnapshot]


class ProgramHeader(BaseModel):
    model_config = {"from_attributes": True}
    id: UUID
    institution_id: UUID
    department_id: UUID | None
    curriculum_id: UUID | None
    name: str
    rule_set_id: UUID | None
    rule_id: UUID | None
    source_version: int
    version: int
    admission_year_from: int
    admission_year_to: int
    tracks: list[str]
    effective_from: date | None
    effective_to: date | None
    status: Literal["draft", "approved", "revoked"]
    created_at: datetime
    updated_at: datetime
    approved_at: datetime | None
    revoked_at: datetime | None


class ProgramView(ProgramHeader):
    approved_by: UUID | None
    review_note: str
    revoked_by: UUID | None
    revocation_reason: str
    rules: list[ProgramRuleView]
    missing_rule_ids: list[UUID]
    usable: bool


class ProgramList(BaseModel):
    items: list[ProgramHeader]
    next_cursor: UUID | None = None


class PublicProgram(ProgramHeader):
    # No administrator notes or student records are exposed.
    rules: list[ProgramRuleView]


class SelectionContext(StrictModel):
    institution_id: UUID
    department_id: UUID
    curriculum_id: UUID
    admission_year: Year
    track: StudyTrack


class SelectionIssue(BaseModel):
    kind: Literal["rule_set", "rule"]
    record_id: UUID
    reason: Literal[
        "execution_program_required",
        "ambiguous_rule_programs",
        "program_dependency_unavailable",
        "manual_requirement",
    ]


class ProgramSelection(BaseModel):
    context: SelectionContext
    as_of: date
    status: Literal["available", "needs_review", "not_applicable"]
    reason: Literal[
        "registered_programs_available",
        "rule_program_review_required",
        "no_registered_rule_metadata",
        "rule_catalog_limit_exceeded",
    ]
    catalog_complete: Literal[False] = False
    programs: list[PublicProgram]
    issues: list[SelectionIssue]
