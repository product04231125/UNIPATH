"""Owner-isolated personal records. None are verified school records."""

from datetime import date, datetime
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    ForeignKeyConstraint,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class OwnedRecord:
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    owner_id: Mapped[UUID] = mapped_column(ForeignKey("users.id"), index=True)
    client_id: Mapped[UUID | None] = mapped_column()
    title: Mapped[str] = mapped_column(String(128))
    detail: Mapped[str] = mapped_column(Text, default="")
    version: Mapped[int] = mapped_column(Integer, default=1)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class PlanningProfile(Base):
    __tablename__ = "planning_profiles"
    owner_id: Mapped[UUID] = mapped_column(ForeignKey("users.id"), primary_key=True)
    school: Mapped[str] = mapped_column(String(128), default="")
    department: Mapped[str] = mapped_column(String(128), default="")
    admission_year: Mapped[int | None] = mapped_column(Integer)
    track: Mapped[str | None] = mapped_column(String(128))
    academic_year_override: Mapped[int | None] = mapped_column(Integer)
    week_starts_on: Mapped[str] = mapped_column(String(16), default="sunday")
    institution_id: Mapped[UUID | None] = mapped_column(ForeignKey("institutions.id"))
    department_id: Mapped[UUID | None] = mapped_column()
    curriculum_id: Mapped[UUID | None] = mapped_column()
    version: Mapped[int] = mapped_column(Integer, default=1)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    __table_args__ = (
        CheckConstraint("version >= 1", name="version"),
        CheckConstraint(
            "admission_year IS NULL OR admission_year BETWEEN 1900 AND 9999", name="year"
        ),
        CheckConstraint(
            "academic_year_override IS NULL OR academic_year_override BETWEEN 1 AND 4",
            name="academic_year",
        ),
        CheckConstraint(
            "week_starts_on IN ('sunday','monday','tuesday','wednesday',"
            "'thursday','friday','saturday')",
            name="week_start",
        ),
        CheckConstraint(
            "(department_id IS NULL OR institution_id IS NOT NULL) AND "
            "(curriculum_id IS NULL OR department_id IS NOT NULL)",
            name="hierarchy",
        ),
        ForeignKeyConstraint(
            ["department_id", "institution_id"], ["departments.id", "departments.institution_id"]
        ),
        ForeignKeyConstraint(
            ["curriculum_id", "department_id", "institution_id"],
            ["curricula.id", "curricula.department_id", "curricula.institution_id"],
        ),
    )


class PersonalEvent(OwnedRecord, Base):
    __tablename__ = "personal_events"
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    ends_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    time_zone: Mapped[str] = mapped_column(String(64))
    category: Mapped[str] = mapped_column(String(16))
    __table_args__ = (
        CheckConstraint("ends_at > starts_at", name="period"),
        CheckConstraint(
            "category IN ('academic','personal','activity','deadline')", name="category"
        ),
    )


class CourseRecord(OwnedRecord, Base):
    __tablename__ = "personal_course_records"
    term: Mapped[str] = mapped_column(String(128))
    category: Mapped[str] = mapped_column(String(128))
    credits: Mapped[Decimal] = mapped_column(Numeric(8, 3))
    section: Mapped[str] = mapped_column(String(128), default="")
    course_code: Mapped[str] = mapped_column(String(128), default="")
    grade: Mapped[str] = mapped_column(String(128), default="")
    completion: Mapped[str] = mapped_column(String(16), default="planned")
    __table_args__ = (
        CheckConstraint("credits > 0 AND credits <= 100", name="credits"),
        CheckConstraint("completion IN ('planned','in_progress','recorded')", name="completion"),
    )


class ActivityRecord(OwnedRecord, Base):
    __tablename__ = "personal_activity_records"
    organization: Mapped[str] = mapped_column(String(128), default="")
    started_on: Mapped[date | None] = mapped_column(Date)
    ended_on: Mapped[date | None] = mapped_column(Date)
    role: Mapped[str] = mapped_column(String(128), default="")
    reported_hours: Mapped[Decimal | None] = mapped_column(Numeric(12, 3))
    approved_hours: Mapped[Decimal | None] = mapped_column(Numeric(12, 3))
    approval: Mapped[str | None] = mapped_column(String(16))
    observed_on: Mapped[date | None] = mapped_column(Date)
    __table_args__ = (
        CheckConstraint("reported_hours IS NULL OR reported_hours >= 0", name="reported_hours"),
        CheckConstraint("approved_hours IS NULL OR approved_hours >= 0", name="approved_hours"),
        CheckConstraint(
            "approval IS NULL OR approval IN ('pending','approved','rejected','needs_review')",
            name="observed_approval",
        ),
        CheckConstraint(
            "approved_hours IS NULL OR approved_hours = 0 OR "
            "(approval IS NOT NULL AND approval = 'approved' AND observed_on IS NOT NULL)",
            name="observation_required",
        ),
    )


class ExperienceRecord(OwnedRecord, Base):
    __tablename__ = "personal_experience_records"
    experience_type: Mapped[str] = mapped_column(String(128))
    organization: Mapped[str] = mapped_column(String(128), default="")
    started_on: Mapped[date | None] = mapped_column(Date)
    ended_on: Mapped[date | None] = mapped_column(Date)
    role: Mapped[str] = mapped_column(String(128), default="")
    result: Mapped[str] = mapped_column(Text, default="")
    status_label: Mapped[str] = mapped_column(String(128), default="")


class CredentialRecord(OwnedRecord, Base):
    __tablename__ = "personal_credential_records"
    provider: Mapped[str] = mapped_column(String(128), default="")
    level: Mapped[str] = mapped_column(String(128), default="")
    earned_on: Mapped[date | None] = mapped_column(Date)
    expires_on: Mapped[date | None] = mapped_column(Date)
    status_label: Mapped[str] = mapped_column(String(128), default="")
    evidence_url: Mapped[str] = mapped_column(String(2048), default="")
    __table_args__ = (
        CheckConstraint(
            "earned_on IS NULL OR expires_on IS NULL OR earned_on <= expires_on", name="period"
        ),
    )


class AchievementRecord(OwnedRecord, Base):
    __tablename__ = "personal_achievement_records"
    achievement_type: Mapped[str] = mapped_column(String(128))
    thesis_type: Mapped[str] = mapped_column(String(128), default="")
    thesis_status_label: Mapped[str] = mapped_column(String(128), default="")
    thesis_grade: Mapped[str] = mapped_column(String(128), default="")
    thesis_approved_on: Mapped[date | None] = mapped_column(Date)
    started_on: Mapped[date | None] = mapped_column(Date)
    ended_on: Mapped[date | None] = mapped_column(Date)
    role: Mapped[str] = mapped_column(String(128))
    result: Mapped[str] = mapped_column(Text)
    evidence_url: Mapped[str] = mapped_column(String(2048), default="")


class PersonalCurriculum(OwnedRecord, Base):
    __tablename__ = "personal_curricula"
    school: Mapped[str] = mapped_column(String(128))
    department: Mapped[str] = mapped_column(String(128))
    admission_year: Mapped[int] = mapped_column(Integer)
    curriculum_year: Mapped[int] = mapped_column(Integer)
    evidence_url: Mapped[str] = mapped_column(String(2048), default="")
    __table_args__ = (
        CheckConstraint("admission_year BETWEEN 1000 AND 9999", name="admission_year"),
        CheckConstraint("curriculum_year BETWEEN 1000 AND 9999", name="curriculum_year"),
    )


class PersonalCurriculumCourse(OwnedRecord, Base):
    __tablename__ = "personal_curriculum_courses"
    curriculum_id: Mapped[UUID] = mapped_column(index=True)
    course_record_id: Mapped[UUID | None] = mapped_column(index=True)
    course_code: Mapped[str] = mapped_column(String(128), default="")
    category: Mapped[str] = mapped_column(String(128))
    credits: Mapped[Decimal] = mapped_column(Numeric(8, 3))
    required: Mapped[bool] = mapped_column(Boolean)
    __table_args__ = (CheckConstraint("credits > 0 AND credits <= 100", name="credits"),)


class PersonalGraduationRule(OwnedRecord, Base):
    __tablename__ = "personal_graduation_rules"
    curriculum_id: Mapped[UUID] = mapped_column(index=True)
    curriculum_course_id: Mapped[UUID | None] = mapped_column(index=True)
    rule_code: Mapped[str] = mapped_column(String(128), default="")
    rule_type: Mapped[str] = mapped_column(String(128))
    scope: Mapped[str] = mapped_column(String(16))
    required_value: Mapped[Decimal | None] = mapped_column(Numeric(18, 6))
    current_value: Mapped[Decimal | None] = mapped_column(Numeric(18, 6))
    unit: Mapped[str] = mapped_column(String(128), default="")
    condition: Mapped[str] = mapped_column(Text)
    effective_from: Mapped[date | None] = mapped_column(Date)
    effective_to: Mapped[date | None] = mapped_column(Date)
    evidence_url: Mapped[str] = mapped_column(String(2048), default="")
    related_course_id: Mapped[UUID | None] = mapped_column()
    related_activity_id: Mapped[UUID | None] = mapped_column()
    related_experience_id: Mapped[UUID | None] = mapped_column()
    related_credential_id: Mapped[UUID | None] = mapped_column()
    related_achievement_id: Mapped[UUID | None] = mapped_column()
    __table_args__ = (
        CheckConstraint("scope IN ('institution','department','curriculum')", name="scope"),
        CheckConstraint("required_value IS NULL OR required_value >= 0", name="required_value"),
        CheckConstraint("current_value IS NULL OR current_value >= 0", name="current_value"),
        CheckConstraint(
            "effective_from IS NULL OR effective_to IS NULL OR effective_from <= effective_to",
            name="period",
        ),
        CheckConstraint(
            "num_nonnulls(related_course_id,related_activity_id,related_experience_id,"
            "related_credential_id,related_achievement_id) <= 1",
            name="one_related_record",
        ),
    )


class PortfolioComposition(OwnedRecord, Base):
    __tablename__ = "portfolio_compositions"
    audience: Mapped[str] = mapped_column(String(24), default="private")
    reviewed: Mapped[bool] = mapped_column(Boolean, default=False)
    __table_args__ = (
        CheckConstraint("audience IN ('private','application','public_review')", name="audience"),
    )


class ApplicationDocument(OwnedRecord, Base):
    __tablename__ = "application_documents"
    target: Mapped[str] = mapped_column(String(128))
    role: Mapped[str] = mapped_column(String(128))
    document_type: Mapped[str] = mapped_column(String(128))
    body: Mapped[str] = mapped_column(Text, default="")


class PortfolioSource(Base):
    __tablename__ = "portfolio_sources"
    composition_id: Mapped[UUID] = mapped_column(primary_key=True)
    owner_id: Mapped[UUID] = mapped_column()
    position: Mapped[int] = mapped_column(Integer, primary_key=True)
    achievement_id: Mapped[UUID] = mapped_column()
    __table_args__ = (
        UniqueConstraint("composition_id", "achievement_id"),
        CheckConstraint("position >= 0", name="position"),
    )


class ApplicationSource(Base):
    __tablename__ = "application_document_sources"
    document_id: Mapped[UUID] = mapped_column(primary_key=True)
    owner_id: Mapped[UUID] = mapped_column()
    position: Mapped[int] = mapped_column(Integer, primary_key=True)
    achievement_id: Mapped[UUID | None] = mapped_column()
    experience_id: Mapped[UUID | None] = mapped_column()
    __table_args__ = (
        UniqueConstraint("document_id", "achievement_id", name="uq_application_source_achievement"),
        UniqueConstraint("document_id", "experience_id", name="uq_application_source_experience"),
        CheckConstraint("position >= 0", name="position"),
        CheckConstraint("num_nonnulls(achievement_id, experience_id) = 1", name="one_source"),
    )


class PersonalCreationReceipt(Base):
    """A retry cannot resurrect a deleted record; receipts contain no raw payload."""

    __tablename__ = "personal_creation_receipts"
    owner_id: Mapped[UUID] = mapped_column(ForeignKey("users.id"), primary_key=True)
    resource: Mapped[str] = mapped_column(String(48), primary_key=True)
    client_id: Mapped[UUID] = mapped_column(primary_key=True)
    record_id: Mapped[UUID] = mapped_column()
    digest: Mapped[str] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


OWNED_MODELS = (
    PersonalEvent,
    CourseRecord,
    ActivityRecord,
    ExperienceRecord,
    CredentialRecord,
    AchievementRecord,
    PersonalCurriculum,
    PersonalCurriculumCourse,
    PersonalGraduationRule,
    PortfolioComposition,
    ApplicationDocument,
)
for model in OWNED_MODELS:
    model.__table__.append_constraint(UniqueConstraint("id", "owner_id"))
    model.__table__.append_constraint(UniqueConstraint("owner_id", "client_id"))
    model.__table__.append_constraint(CheckConstraint("version >= 1", name="version"))
PersonalCurriculumCourse.__table__.append_constraint(
    UniqueConstraint("id", "curriculum_id", "owner_id", name="uq_personal_course_curriculum_owner")
)
for model in (ActivityRecord, ExperienceRecord, AchievementRecord):
    model.__table__.append_constraint(
        CheckConstraint(
            "started_on IS NULL OR ended_on IS NULL OR started_on <= ended_on", name="period"
        )
    )


def owned_fk(model, fields, target, target_fields=None, *, cascade=False):
    model.__table__.append_constraint(
        ForeignKeyConstraint(
            [*fields, "owner_id"],
            [
                f"{target.__tablename__}.{column}"
                for column in [*(target_fields or ["id"]), "owner_id"]
            ],
            ondelete="CASCADE" if cascade else None,
        )
    )


owned_fk(PersonalCurriculumCourse, ["curriculum_id"], PersonalCurriculum)
owned_fk(PersonalCurriculumCourse, ["course_record_id"], CourseRecord)
owned_fk(PersonalGraduationRule, ["curriculum_id"], PersonalCurriculum)
owned_fk(
    PersonalGraduationRule,
    ["curriculum_course_id", "curriculum_id"],
    PersonalCurriculumCourse,
    ["id", "curriculum_id"],
)
for kind, model in [
    ("course", CourseRecord),
    ("activity", ActivityRecord),
    ("experience", ExperienceRecord),
    ("credential", CredentialRecord),
    ("achievement", AchievementRecord),
]:
    owned_fk(PersonalGraduationRule, [f"related_{kind}_id"], model)
owned_fk(PortfolioSource, ["composition_id"], PortfolioComposition, cascade=True)
owned_fk(PortfolioSource, ["achievement_id"], AchievementRecord)
owned_fk(ApplicationSource, ["document_id"], ApplicationDocument, cascade=True)
owned_fk(ApplicationSource, ["achievement_id"], AchievementRecord)
owned_fk(ApplicationSource, ["experience_id"], ExperienceRecord)
