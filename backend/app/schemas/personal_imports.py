"""Explicit consent, typed local identities and an all-or-nothing append import."""

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, model_validator

from app.schemas import personal as dto
from app.schemas.auth import StrictModel

COLLECTIONS = (
    "events",
    "course_records",
    "activity_records",
    "experience_records",
    "credential_records",
    "achievement_records",
    "personal_curricula",
    "personal_curriculum_courses",
    "personal_graduation_rules",
    "portfolio_compositions",
    "application_documents",
)
REFERENCE_RESOURCES = {
    "course": "course_records",
    "activity": "activity_records",
    "experience": "experience_records",
    "credential": "credential_records",
    "achievement": "achievement_records",
}
Resource = Literal[
    "events",
    "course-records",
    "activity-records",
    "experience-records",
    "credential-records",
    "achievement-records",
    "personal-curricula",
    "personal-curriculum-courses",
    "personal-graduation-rules",
    "portfolio-compositions",
    "application-documents",
]


class ImportEvent(dto.EventCreate):
    client_id: UUID


class ImportCourseRecord(dto.CourseRecordCreate):
    client_id: UUID


class ImportActivityRecord(dto.ActivityRecordCreate):
    client_id: UUID


class ImportExperienceRecord(dto.ExperienceRecordCreate):
    client_id: UUID


class ImportCredentialRecord(dto.CredentialRecordCreate):
    client_id: UUID


class ImportAchievementRecord(dto.AchievementRecordCreate):
    client_id: UUID


class ImportPersonalCurriculum(dto.PersonalCurriculumCreate):
    client_id: UUID


class ImportRecordReference(dto.RecordReference):
    record_id: UUID = Field(alias="client_id")


class ImportCurriculumCourse(dto.PersonalCurriculumCourseCreate):
    client_id: UUID
    curriculum_id: UUID = Field(alias="curriculum_client_id")
    course_record_id: UUID | None = Field(default=None, alias="course_record_client_id")


class ImportGraduationRule(dto.PersonalGraduationRuleCreate):
    client_id: UUID
    curriculum_id: UUID = Field(alias="curriculum_client_id")
    curriculum_course_id: UUID | None = Field(default=None, alias="curriculum_course_client_id")
    related_record: ImportRecordReference | None = None


class ImportComposition(dto.PortfolioCompositionCreate):
    client_id: UUID
    sources: list[ImportRecordReference] = Field(default_factory=list, max_length=100)


class ImportApplicationDocument(dto.ApplicationDocumentCreate):
    client_id: UUID
    sources: list[ImportRecordReference] = Field(default_factory=list, max_length=100)


class PersonalImportCreate(StrictModel):
    import_id: UUID
    source_owner_id: UUID
    consent_confirmed: bool = Field(strict=True)
    # This can initialize an absent profile, never replace an existing profile.
    profile: dto.ProfileData | None = None
    events: list[ImportEvent] = Field(default_factory=list, max_length=100)
    course_records: list[ImportCourseRecord] = Field(default_factory=list, max_length=100)
    activity_records: list[ImportActivityRecord] = Field(default_factory=list, max_length=100)
    experience_records: list[ImportExperienceRecord] = Field(default_factory=list, max_length=100)
    credential_records: list[ImportCredentialRecord] = Field(default_factory=list, max_length=100)
    achievement_records: list[ImportAchievementRecord] = Field(default_factory=list, max_length=100)
    personal_curricula: list[ImportPersonalCurriculum] = Field(default_factory=list, max_length=100)
    personal_curriculum_courses: list[ImportCurriculumCourse] = Field(
        default_factory=list, max_length=100
    )
    personal_graduation_rules: list[ImportGraduationRule] = Field(
        default_factory=list, max_length=100
    )
    portfolio_compositions: list[ImportComposition] = Field(default_factory=list, max_length=100)
    application_documents: list[ImportApplicationDocument] = Field(
        default_factory=list, max_length=100
    )

    @model_validator(mode="after")
    def complete_local_graph(self):
        if not self.consent_confirmed:
            raise ValueError("Explicit import consent is required")
        groups = {name: getattr(self, name) for name in COLLECTIONS}
        count = sum(len(items) for items in groups.values())
        if count > 500 or not count and self.profile is None:
            raise ValueError("Import between 1 and 500 records, or an initial profile")
        identities = {name: {item.client_id for item in items} for name, items in groups.items()}
        if any(len(identities[name]) != len(items) for name, items in groups.items()):
            raise ValueError("Duplicate client identity in a collection")

        def require(name, identifier):
            if identifier is not None and identifier not in identities[name]:
                raise ValueError("Include every referenced local record in this import")

        for item in self.personal_curriculum_courses:
            require("personal_curricula", item.curriculum_id)
            require("course_records", item.course_record_id)
        courses = {item.client_id: item for item in self.personal_curriculum_courses}
        for item in self.personal_graduation_rules:
            require("personal_curricula", item.curriculum_id)
            require("personal_curriculum_courses", item.curriculum_course_id)
            if (
                item.curriculum_course_id
                and courses[item.curriculum_course_id].curriculum_id != item.curriculum_id
            ):
                raise ValueError("The local course and rule must share a curriculum")
            if item.related_record:
                require(
                    REFERENCE_RESOURCES[item.related_record.kind], item.related_record.record_id
                )
        reference_count = 0
        for item in [*self.portfolio_compositions, *self.application_documents]:
            reference_count += len(item.sources)
            for reference in item.sources:
                require(REFERENCE_RESOURCES[reference.kind], reference.record_id)
        if reference_count > 2000:
            raise ValueError("Import at most 2000 ordered source references")
        if len(self.model_dump_json(by_alias=True).encode()) > 2 * 1024 * 1024:
            raise ValueError("Import at most 2 MiB of normalized data")
        return self


class ImportMapping(BaseModel):
    resource: Resource
    client_id: UUID
    record_id: UUID
    version_at_import: int
    outcome: Literal["created", "reused"]


class PersonalImportView(BaseModel):
    import_id: UUID
    owner_id: UUID
    committed_at: datetime
    record_count: int
    profile_version_at_import: int | None
    mappings: list[ImportMapping]
    replayed: bool
    origin: Literal["personal"] = "personal"
    official: Literal[False] = False
