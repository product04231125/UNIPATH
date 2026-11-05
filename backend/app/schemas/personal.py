"""Typed personal planning/records contracts; never trusted academic evidence."""

import re
from datetime import UTC, date, datetime
from decimal import Decimal
from typing import Annotated, Literal
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import (
    AfterValidator,
    AwareDatetime,
    BaseModel,
    BeforeValidator,
    ConfigDict,
    Field,
    StringConstraints,
    create_model,
    field_validator,
    model_validator,
)

from app.schemas.academic import safe_url
from app.schemas.auth import Name, StrictModel

ShortText = Annotated[str, StringConstraints(strip_whitespace=True, max_length=128)]
Notes = Annotated[str, StringConstraints(max_length=8000)]
LongText = Annotated[str, StringConstraints(max_length=32000)]
RequiredNotes = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=1, max_length=8000)
]
Credits = Annotated[
    Decimal, Field(gt=0, le=100, max_digits=8, decimal_places=3, allow_inf_nan=False)
]
Amount = Annotated[
    Decimal, Field(ge=0, le=1_000_000, max_digits=18, decimal_places=6, allow_inf_nan=False)
]
Hours = Annotated[
    Decimal, Field(ge=0, le=1_000_000, max_digits=12, decimal_places=3, allow_inf_nan=False)
]
Link = Annotated[str, StringConstraints(max_length=2048), AfterValidator(safe_url)]


def date_input(value):
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value):
        raise ValueError("Use a calendar date in YYYY-MM-DD form")
    return value


def instant_input(value):
    if not isinstance(value, (str, datetime)):
        raise ValueError("Use an ISO 8601 timestamp with an explicit UTC offset")
    if isinstance(value, str) and not re.fullmatch(
        r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}"
        r"(?:\.[0-9]{1,6})?(?:Z|[+-][0-9]{2}:[0-9]{2})",
        value,
    ):
        raise ValueError("Use an ISO 8601 timestamp with an explicit UTC offset")
    return value


Day = Annotated[date, BeforeValidator(date_input)]
Instant = Annotated[AwareDatetime, BeforeValidator(instant_input)]
WeekStart = Literal["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
RecordKind = Literal["course", "activity", "experience", "credential", "achievement"]


class ProfileData(StrictModel):
    school: ShortText = ""
    department: ShortText = ""
    admission_year: int | None = Field(default=None, ge=1900, le=9999, strict=True)
    track: Name | None = None
    academic_year_override: int | None = Field(default=None, ge=1, le=4, strict=True)
    week_starts_on: WeekStart = "sunday"
    institution_id: UUID | None = None
    department_id: UUID | None = None
    curriculum_id: UUID | None = None

    @model_validator(mode="after")
    def valid_context(self):
        if self.admission_year is not None and self.admission_year > datetime.now(UTC).year + 1:
            raise ValueError("Admission year is in the future")
        if self.department_id and not self.institution_id:
            raise ValueError("A department requires an institution")
        if self.curriculum_id and not self.department_id:
            raise ValueError("A curriculum requires a department")
        return self


class ProfileView(ProfileData):
    owner_id: UUID
    version: int
    created_at: datetime | None = None
    updated_at: datetime | None = None
    official: Literal[False] = False


class PersonalCreate(StrictModel):
    title: Name
    detail: Notes = ""
    client_id: UUID | None = None


class EventCreate(PersonalCreate):
    starts_at: Instant
    ends_at: Instant
    time_zone: Annotated[str, StringConstraints(min_length=1, max_length=64)]
    category: Literal["academic", "personal", "activity", "deadline"]

    @field_validator("time_zone")
    @classmethod
    def known_zone(cls, value):
        try:
            ZoneInfo(value)
        except (ZoneInfoNotFoundError, ValueError):
            raise ValueError("Use an IANA time zone") from None
        return value

    @model_validator(mode="after")
    def valid_period(self):
        if self.ends_at <= self.starts_at:
            raise ValueError("End must be after start")
        return self


class CourseRecordCreate(PersonalCreate):
    term: Name
    category: Name
    credits: Credits
    section: ShortText = ""
    course_code: ShortText = ""
    grade: ShortText = ""
    completion: Literal["planned", "in_progress", "recorded"] = "planned"


class DatedRecord(PersonalCreate):
    started_on: Day | None = None
    ended_on: Day | None = None

    @model_validator(mode="after")
    def valid_period(self):
        if self.started_on and self.ended_on and self.started_on > self.ended_on:
            raise ValueError("Dates are reversed")
        return self


class ActivityRecordCreate(DatedRecord):
    organization: ShortText = ""
    role: ShortText = ""
    reported_hours: Hours | None = None
    approved_hours: Hours | None = None
    approval: Literal["pending", "approved", "rejected", "needs_review"] | None = None
    observed_on: Day | None = None

    @model_validator(mode="after")
    def observed_approval(self):
        if self.approved_hours and (self.approval != "approved" or self.observed_on is None):
            raise ValueError("Observed approved hours require approved state and observation date")
        return self


class ExperienceRecordCreate(DatedRecord):
    experience_type: Name
    organization: ShortText = ""
    role: ShortText = ""
    result: Notes = ""
    status_label: ShortText = ""


class CredentialRecordCreate(PersonalCreate):
    provider: ShortText = ""
    level: ShortText = ""
    earned_on: Day | None = None
    expires_on: Day | None = None
    status_label: ShortText = ""
    evidence_url: Link = ""

    @model_validator(mode="after")
    def valid_period(self):
        if self.earned_on and self.expires_on and self.earned_on > self.expires_on:
            raise ValueError("Dates are reversed")
        return self


class AchievementRecordCreate(DatedRecord):
    achievement_type: Name
    thesis_type: ShortText = ""
    thesis_status_label: ShortText = ""
    thesis_grade: ShortText = ""
    thesis_approved_on: Day | None = None
    role: Name
    result: RequiredNotes
    evidence_url: Link = ""


class PersonalCurriculumCreate(PersonalCreate):
    school: Name
    department: Name
    admission_year: int = Field(ge=1000, le=9999, strict=True)
    curriculum_year: int = Field(ge=1000, le=9999, strict=True)
    evidence_url: Link = ""


class PersonalCurriculumCourseCreate(PersonalCreate):
    curriculum_id: UUID
    course_record_id: UUID | None = None
    course_code: ShortText = ""
    category: Name
    credits: Credits
    required: bool = Field(strict=True)


class RecordReference(StrictModel):
    kind: RecordKind
    record_id: UUID


class PersonalGraduationRuleCreate(PersonalCreate):
    curriculum_id: UUID
    curriculum_course_id: UUID | None = None
    rule_code: ShortText = ""
    rule_type: Name
    scope: Literal["institution", "department", "curriculum"]
    required_value: Amount | None = None
    current_value: Amount | None = None
    unit: ShortText = ""
    condition: RequiredNotes
    effective_from: Day | None = None
    effective_to: Day | None = None
    evidence_url: Link = ""
    related_record: RecordReference | None = None

    @model_validator(mode="after")
    def valid_period(self):
        if self.effective_from and self.effective_to and self.effective_from > self.effective_to:
            raise ValueError("Dates are reversed")
        return self


class PortfolioCompositionCreate(PersonalCreate):
    audience: Literal["private", "application", "public_review"] = "private"
    reviewed: bool = Field(default=False, strict=True)
    sources: list[RecordReference] = Field(default_factory=list, max_length=100)

    @field_validator("sources")
    @classmethod
    def valid_sources(cls, value):
        if len({(v.kind, v.record_id) for v in value}) != len(value):
            raise ValueError("Duplicate sources")
        if any(v.kind != "achievement" for v in value):
            raise ValueError("Compositions reference achievements only")
        return value


class ApplicationDocumentCreate(PersonalCreate):
    target: Name
    role: Name
    document_type: Name
    body: LongText = ""
    sources: list[RecordReference] = Field(default_factory=list, max_length=100)

    @field_validator("sources")
    @classmethod
    def valid_sources(cls, value):
        if len({(v.kind, v.record_id) for v in value}) != len(value):
            raise ValueError("Duplicate sources")
        if any(v.kind not in ("achievement", "experience") for v in value):
            raise ValueError("Documents reference achievements or experiences only")
        return value


class OwnedView(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    owner_id: UUID
    version: int
    created_at: datetime
    updated_at: datetime
    origin: Literal["personal"] = "personal"
    official: Literal[False] = False


def patch_contract(name, schema, *, initial=False):
    """Keep DTO field bounds in OpenAPI; validate merged cross-field rules on save."""
    fields = {}
    for key, info in schema.model_fields.items():
        if key == "client_id":
            continue
        annotation = info.annotation | None
        if info.metadata:
            annotation = Annotated[annotation, *info.metadata]
        fields[key] = (annotation, None)
    return create_model(
        name,
        __base__=StrictModel,
        expected_version=(int, Field(ge=0 if initial else 1, strict=True)),
        **fields,
    )


ProfilePatch = patch_contract("ProfilePatch", ProfileData, initial=True)
for prefix in (
    "Event",
    "CourseRecord",
    "ActivityRecord",
    "ExperienceRecord",
    "CredentialRecord",
    "AchievementRecord",
    "PersonalCurriculum",
    "PersonalCurriculumCourse",
    "PersonalGraduationRule",
    "PortfolioComposition",
    "ApplicationDocument",
):
    schema = globals()[prefix + "Create"]
    globals()[prefix + "Patch"] = patch_contract(prefix + "Patch", schema)
    globals()[prefix + "View"] = create_model(prefix + "View", __base__=(schema, OwnedView))
