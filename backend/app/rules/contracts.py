"""Internal rule contracts; these are not public API or physical database models."""

from datetime import date
from decimal import Decimal
from enum import StrEnum
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

Amount = Annotated[
    Decimal,
    Field(ge=0, le=1_000_000, allow_inf_nan=False, max_digits=18, decimal_places=6),
]
Total = Annotated[Decimal, Field(ge=0, allow_inf_nan=False)]
Name = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=128)]


class Contract(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)


class Status(StrEnum):
    SATISFIED = "satisfied"
    NOT_SATISFIED = "not_satisfied"
    NEEDS_REVIEW = "needs_review"
    NOT_APPLICABLE = "not_applicable"


class Origin(StrEnum):
    OFFICIAL = "official"
    PERSONAL = "personal"


class ScopeType(StrEnum):
    INSTITUTION = "institution"
    DEPARTMENT = "department"
    CURRICULUM = "curriculum"


class Approval(StrEnum):
    APPROVED = "approved"
    PENDING = "pending"
    REJECTED = "rejected"
    NEEDS_REVIEW = "needs_review"


class Completion(StrEnum):
    COMPLETED = "completed"
    FAILED = "failed"
    IN_PROGRESS = "in_progress"
    NEEDS_REVIEW = "needs_review"


class Scope(Contract):
    scope_type: ScopeType
    institution_id: UUID
    department_id: UUID | None = None
    curriculum_id: UUID | None = None
    admission_year_from: int | None = Field(default=None, ge=1000, le=9999, strict=True)
    admission_year_to: int | None = Field(default=None, ge=1000, le=9999, strict=True)
    track: Name | None = None

    @model_validator(mode="after")
    def consistent_scope(self):
        required_department = self.scope_type != ScopeType.INSTITUTION
        required_curriculum = self.scope_type == ScopeType.CURRICULUM
        if (self.department_id is not None) != required_department:
            raise ValueError("Department reference does not match scope")
        if (self.curriculum_id is not None) != required_curriculum:
            raise ValueError("Curriculum reference does not match scope")
        if (self.admission_year_from is None) != (self.admission_year_to is None):
            raise ValueError("An admission-year interval requires both endpoints")
        if self.admission_year_from is not None and (
            self.admission_year_from > self.admission_year_to
        ):
            raise ValueError("Admission-year interval is reversed")
        return self


class AcademicContext(Contract):
    institution_id: UUID | None = None
    department_id: UUID | None = None
    curriculum_id: UUID | None = None
    admission_year: int | None = Field(default=None, ge=1000, le=9999, strict=True)
    track: Name | None = None


class Evidence(Contract):
    document_id: UUID
    title: Name
    source_url: Annotated[str, Field(pattern=r"^https?://[^\s]+$", max_length=2048)]
    page: int = Field(ge=1, strict=True)


class AcademicRecord(Contract):
    id: UUID
    course_id: UUID
    completion_status: Completion
    earned_credits: Amount | None = None
    category: Name | None = None
    grade_points: Amount | None = None
    grade_scale: Name | None = None


class VolunteerRecord(Contract):
    id: UUID
    approval_status: Approval
    approved_hours: Amount | None = None


class CertificateRecord(Contract):
    id: UUID
    certificate_id: UUID
    approval_status: Approval
    expires_on: date | None = None
    validity_known: bool = Field(default=False, strict=True)


class ThesisRecord(Contract):
    id: UUID
    thesis_type: Name
    approval_status: Approval
    is_completed: bool = Field(strict=True)
    grade: Name | None = None


class Snapshot(Contract):
    # None means unavailable; an empty tuple means a known empty record list.
    academics: tuple[AcademicRecord, ...] | None = None
    volunteers: tuple[VolunteerRecord, ...] | None = None
    certificates: tuple[CertificateRecord, ...] | None = None
    theses: tuple[ThesisRecord, ...] | None = None

    @model_validator(mode="after")
    def unique_record_ids(self):
        for records in (self.academics, self.volunteers, self.certificates, self.theses):
            if records is not None and len({record.id for record in records}) != len(records):
                raise ValueError("Duplicate record identifiers")
        return self


class RuleBase(Contract):
    id: UUID
    code: Name
    title: Name


class CreditRule(RuleBase):
    kind: Literal["minimum_credits"] = "minimum_credits"
    minimum: Amount
    category: Name | None = None


class CourseRequirement(Contract):
    course_id: UUID
    minimum_credits: Amount | None = None
    minimum_grade_points: Amount | None = None
    comparison_grade_scale: Name | None = None

    @model_validator(mode="after")
    def comparable_grade(self):
        if (self.minimum_grade_points is None) != (self.comparison_grade_scale is None):
            raise ValueError("Grade thresholds require an explicit comparison scale")
        return self


class CourseRule(RuleBase):
    kind: Literal["required_courses"] = "required_courses"
    courses: tuple[CourseRequirement, ...] = Field(min_length=1)

    @model_validator(mode="after")
    def distinct_courses(self):
        if len({c.course_id for c in self.courses}) != len(self.courses):
            raise ValueError("Duplicate required courses")
        return self


class VolunteerRule(RuleBase):
    kind: Literal["minimum_volunteer_hours"] = "minimum_volunteer_hours"
    minimum: Amount


class CertificateRule(RuleBase):
    kind: Literal["any_certificate"] = "any_certificate"
    certificate_ids: tuple[UUID, ...] = Field(min_length=1)

    @model_validator(mode="after")
    def distinct_certificates(self):
        if len(set(self.certificate_ids)) != len(self.certificate_ids):
            raise ValueError("Duplicate certificate alternatives")
        return self


class ThesisRule(RuleBase):
    kind: Literal["thesis"] = "thesis"
    thesis_type: Name
    requires_approval: bool = Field(default=True, strict=True)
    accepted_grades: tuple[Name, ...] = ()


Rule = Annotated[
    CreditRule | CourseRule | VolunteerRule | CertificateRule | ThesisRule,
    Field(discriminator="kind"),
]


class RuleSet(Contract):
    id: UUID
    code: Name
    version: int = Field(ge=1, strict=True)
    origin: Origin
    scope: Scope | None = None
    approval_status: Approval = Approval.PENDING
    evidence: tuple[Evidence, ...] = ()
    effective_from: date | None = None
    effective_to: date | None = None
    is_active: bool = Field(default=True, strict=True)
    rules: tuple[Rule, ...] = Field(min_length=1)

    @model_validator(mode="after")
    def consistent_rule_set(self):
        if (self.scope is not None) != (self.origin == Origin.OFFICIAL):
            raise ValueError("Only official rule sets have an institutional scope")
        if self.origin == Origin.OFFICIAL and self.approval_status == Approval.APPROVED:
            if not self.evidence:
                raise ValueError("Approved official rules require document evidence")
        if self.effective_from and self.effective_to and self.effective_from > self.effective_to:
            raise ValueError("Effective date interval is reversed")
        if len({r.id for r in self.rules}) != len(self.rules):
            raise ValueError("Duplicate rule identifiers")
        if len({r.code for r in self.rules}) != len(self.rules):
            raise ValueError("Duplicate rule codes")
        return self


class RuleResult(Contract):
    rule_set_id: UUID
    rule_set_version: int
    rule_id: UUID
    rule_code: Name
    title: Name
    status: Status
    reason: str
    current: Total | None = None
    required: Total | None = None
    deficit: Total | None = None
    missing_course_ids: tuple[UUID, ...] = ()
    uncertain_course_ids: tuple[UUID, ...] = ()
    evidence_record_ids: tuple[UUID, ...] = ()


class AppliedVersion(Contract):
    rule_set_id: UUID
    version: int
    scope_type: ScopeType | None
    evidence: tuple[Evidence, ...]


class Evaluation(Contract):
    status: Status
    official: bool
    label: str
    reason: str
    evaluated_on: date
    applied_versions: tuple[AppliedVersion, ...] = ()
    results: tuple[RuleResult, ...] = ()
    missing_fields: tuple[str, ...] = ()
