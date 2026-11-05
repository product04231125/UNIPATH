"""Explicit personal calculation criteria and stable public result projections."""

from datetime import datetime
from decimal import Decimal
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, Field, model_validator

from app.schemas.auth import Name, StrictModel
from app.schemas.personal import Amount, Day

EvaluationStatus = Literal["satisfied", "not_satisfied", "needs_review", "not_applicable"]
SourceKind = Literal[
    "course-records",
    "activity-records",
    "credential-records",
    "achievement-records",
    "personal-curricula",
    "personal-curriculum-courses",
    "personal-graduation-rules",
]
Total = Annotated[Decimal, Field(ge=0, allow_inf_nan=False)]
Ids = Annotated[list[UUID], Field(max_length=500)]


class GradeObservation(StrictModel):
    course_record_id: UUID
    points: Amount
    scale: Name


class CreditCondition(StrictModel):
    kind: Literal["minimum_credits"]
    minimum: Amount
    category: Name | None = None
    course_record_ids: Ids | None = None


class RequiredCourse(StrictModel):
    curriculum_course_id: UUID
    minimum_credits: Amount | None = None
    minimum_grade_points: Amount | None = None
    comparison_grade_scale: Name | None = None

    @model_validator(mode="after")
    def paired_grade(self):
        if (self.minimum_grade_points is None) != (self.comparison_grade_scale is None):
            raise ValueError("A numeric grade threshold requires an explicit comparison scale")
        return self


class CourseCondition(StrictModel):
    kind: Literal["required_courses"]
    courses: list[RequiredCourse] = Field(min_length=1, max_length=100)
    grades: list[GradeObservation] = Field(default_factory=list, max_length=100)


class VolunteerCondition(StrictModel):
    kind: Literal["minimum_volunteer_hours"]
    minimum: Amount
    activity_ids: Ids


class CertificateObservation(StrictModel):
    credential_id: UUID
    possession: Literal["held", "not_held", "unknown"] = "unknown"
    validity_known: bool = Field(default=False, strict=True)


class CertificateCondition(StrictModel):
    kind: Literal["any_certificate"]
    certificates: list[CertificateObservation] = Field(min_length=1, max_length=100)


class ThesisObservation(StrictModel):
    achievement_id: UUID
    completion: Literal["completed", "in_progress", "unknown"] = "unknown"
    approval: Literal["approved", "pending", "rejected", "needs_review"] = "needs_review"


class ThesisCondition(StrictModel):
    kind: Literal["thesis"]
    thesis_type: Name
    requires_approval: bool = Field(default=True, strict=True)
    accepted_grades: list[Name] = Field(default_factory=list, max_length=20)
    records: list[ThesisObservation] = Field(max_length=100)


Condition = Annotated[
    CreditCondition | CourseCondition | VolunteerCondition | CertificateCondition | ThesisCondition,
    Field(discriminator="kind"),
]


class RuleCalculation(StrictModel):
    rule_id: UUID
    expected_version: int = Field(ge=1, strict=True)
    condition: Condition


class SourceVersion(StrictModel):
    kind: SourceKind
    record_id: UUID
    version: int = Field(ge=1, strict=True)


class PersonalEvaluationCreate(StrictModel):
    curriculum_id: UUID
    expected_curriculum_version: int = Field(ge=1, strict=True)
    client_id: UUID | None = None
    as_of: Day | None = None
    calculations: list[RuleCalculation] = Field(default_factory=list, max_length=100)
    expected_source_versions: list[SourceVersion] = Field(default_factory=list, max_length=2000)

    @model_validator(mode="after")
    def consistent_selections(self):
        if len({item.rule_id for item in self.calculations}) != len(self.calculations):
            raise ValueError("Duplicate rule calculations")
        if len({(v.kind, v.record_id) for v in self.expected_source_versions}) != len(
            self.expected_source_versions
        ):
            raise ValueError("Duplicate expected source versions")
        references = 0
        observations = {}
        for item in self.calculations:
            condition = item.condition
            if isinstance(condition, CreditCondition):
                ids = condition.course_record_ids or []
            elif isinstance(condition, CourseCondition):
                ids = [r.curriculum_course_id for r in condition.courses]
                references += len(condition.grades)
                if len({g.course_record_id for g in condition.grades}) != len(condition.grades):
                    raise ValueError("Duplicate grade observations")
                for grade in condition.grades:
                    key = ("grade", grade.course_record_id)
                    value = (grade.points, grade.scale)
                    if key in observations and observations[key] != value:
                        raise ValueError("Contradictory grade observations")
                    observations[key] = value
            elif isinstance(condition, VolunteerCondition):
                ids = condition.activity_ids
            elif isinstance(condition, CertificateCondition):
                ids = [o.credential_id for o in condition.certificates]
                for observation in condition.certificates:
                    key = ("credential", observation.credential_id)
                    value = (observation.possession, observation.validity_known)
                    if key in observations and observations[key] != value:
                        raise ValueError("Contradictory credential observations")
                    observations[key] = value
            else:
                ids = [o.achievement_id for o in condition.records]
                if len(set(condition.accepted_grades)) != len(condition.accepted_grades):
                    raise ValueError("Duplicate accepted grades")
                for observation in condition.records:
                    key = ("thesis", observation.achievement_id)
                    value = (observation.completion, observation.approval)
                    if key in observations and observations[key] != value:
                        raise ValueError("Contradictory thesis observations")
                    observations[key] = value
            if len(set(ids)) != len(ids):
                raise ValueError("Duplicate selected records")
            references += len(ids)
        if references > 2000:
            raise ValueError("Select at most 2000 record references")
        return self


class EvaluationItem(BaseModel):
    rule_id: UUID
    rule_version: int
    title: str
    status: EvaluationStatus
    reason: str
    current: Total | None = None
    required: Total | None = None
    deficit: Total | None = None
    missing_course_ids: list[UUID] = Field(default_factory=list)
    uncertain_course_ids: list[UUID] = Field(default_factory=list)
    evidence_record_ids: list[UUID] = Field(default_factory=list)
    condition: Condition | None = None


class PersonalEvaluationSummary(BaseModel):
    id: UUID
    owner_id: UUID
    client_id: UUID | None
    version: Literal[1] = 1
    curriculum_id: UUID
    curriculum_version: int
    curriculum_title: str
    created_at: datetime
    evaluated_on: Day
    official: Literal[False] = False
    label: Literal["개인 기준 계산 · 학교 공식 판정 아님"] = "개인 기준 계산 · 학교 공식 판정 아님"
    status: EvaluationStatus
    reason: str


class PersonalEvaluationView(PersonalEvaluationSummary):
    results: list[EvaluationItem]
    source_versions: list[SourceVersion]


class PersonalEvaluationList(BaseModel):
    items: list[PersonalEvaluationSummary]
    next_cursor: UUID | None = None
