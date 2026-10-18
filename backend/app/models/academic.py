"""Official catalog and reviewed metadata; not student records or executable rules."""

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
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class CatalogRecord:
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    institution_id: Mapped[UUID] = mapped_column(ForeignKey("institutions.id"), index=True)
    name: Mapped[str] = mapped_column(String(128))
    version: Mapped[int] = mapped_column(Integer, default=1)
    created_by: Mapped[UUID] = mapped_column(ForeignKey("users.id"))
    updated_by: Mapped[UUID] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Department(CatalogRecord, Base):
    __tablename__ = "departments"
    __table_args__ = (UniqueConstraint("institution_id", "code"),)
    code: Mapped[str] = mapped_column(String(64))


class Curriculum(CatalogRecord, Base):
    __tablename__ = "curricula"
    __table_args__ = (
        UniqueConstraint("department_id", "year", "name"),
        CheckConstraint("year BETWEEN 1000 AND 9999", name="year"),
    )
    department_id: Mapped[UUID] = mapped_column(index=True)
    year: Mapped[int] = mapped_column(Integer)


class Course(CatalogRecord, Base):
    __tablename__ = "courses"
    __table_args__ = (
        UniqueConstraint("institution_id", "code"),
        CheckConstraint("credits >= 0 AND credits <= 100", name="credits"),
    )
    code: Mapped[str] = mapped_column(String(64))
    credits: Mapped[Decimal] = mapped_column(Numeric(8, 3))


class CurriculumCourse(CatalogRecord, Base):
    __tablename__ = "curriculum_courses"
    __table_args__ = (
        UniqueConstraint("curriculum_id", "course_id"),
        CheckConstraint("category IN ('major', 'general', 'other')", name="category"),
    )
    curriculum_id: Mapped[UUID] = mapped_column(index=True)
    course_id: Mapped[UUID] = mapped_column(index=True)
    category: Mapped[str] = mapped_column(String(16))
    required: Mapped[bool] = mapped_column(Boolean)


class ReviewedRecord(CatalogRecord):
    department_id: Mapped[UUID | None] = mapped_column(index=True)
    curriculum_id: Mapped[UUID | None] = mapped_column(index=True)
    lineage_id: Mapped[UUID] = mapped_column(default=uuid4)
    revision: Mapped[int] = mapped_column(Integer, default=1)
    status: Mapped[str] = mapped_column(String(16), default="draft")
    effective_from: Mapped[date | None] = mapped_column(Date)
    effective_to: Mapped[date | None] = mapped_column(Date)
    applied_by: Mapped[UUID | None] = mapped_column(ForeignKey("users.id"))
    applied_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class RuleSet(ReviewedRecord, Base):
    __tablename__ = "rule_sets"


class GraduationRule(ReviewedRecord, Base):
    __tablename__ = "graduation_rules"
    rule_set_id: Mapped[UUID | None] = mapped_column(index=True)
    rule_type: Mapped[str] = mapped_column(String(32))
    # Human-reviewed description only. Never eval/parse into an executable rule.
    definition: Mapped[str] = mapped_column(Text)
    source_url: Mapped[str] = mapped_column(String(2048), default="")


class OfficialDocument(ReviewedRecord, Base):
    __tablename__ = "official_documents"
    source_url: Mapped[str] = mapped_column(String(2048))
    document_type: Mapped[str] = mapped_column(String(24))
    rule_id: Mapped[UUID | None] = mapped_column(index=True)


for model in (RuleSet, GraduationRule, OfficialDocument):
    table = model.__table__
    table.append_constraint(CheckConstraint("status IN ('draft', 'applied')", name="status"))
    table.append_constraint(CheckConstraint("revision >= 1 AND version >= 1", name="versions"))
    table.append_constraint(
        CheckConstraint(
            "effective_from IS NULL OR effective_to IS NULL OR effective_from <= effective_to",
            name="effective_period",
        )
    )
    table.append_constraint(
        CheckConstraint(
            "curriculum_id IS NULL OR department_id IS NOT NULL",
            name="scope_hierarchy",
        )
    )
    table.append_constraint(UniqueConstraint("lineage_id", "revision"))
    Index(
        f"uq_{table.name}_draft",
        table.c.lineage_id,
        unique=True,
        postgresql_where=text("status = 'draft'"),
    )

# Keep school/department membership valid even for non-HTTP database writers.
for model in (Department, Curriculum, Course, RuleSet, GraduationRule):
    model.__table__.append_constraint(UniqueConstraint("id", "institution_id"))
Curriculum.__table__.append_constraint(
    UniqueConstraint("id", "department_id", "institution_id", name="uq_curricula_scope")
)
Curriculum.__table__.append_constraint(
    ForeignKeyConstraint(
        ["department_id", "institution_id"],
        ["departments.id", "departments.institution_id"],
    )
)
for model in (CurriculumCourse, RuleSet, GraduationRule, OfficialDocument):
    table = model.__table__
    if model == CurriculumCourse:
        table.append_constraint(
            ForeignKeyConstraint(
                ["course_id", "institution_id"],
                ["courses.id", "courses.institution_id"],
            )
        )
        table.append_constraint(
            ForeignKeyConstraint(
                ["curriculum_id", "institution_id"],
                ["curricula.id", "curricula.institution_id"],
            )
        )
    else:
        table.append_constraint(
            ForeignKeyConstraint(
                ["department_id", "institution_id"],
                ["departments.id", "departments.institution_id"],
            )
        )
        table.append_constraint(
            ForeignKeyConstraint(
                ["curriculum_id", "department_id", "institution_id"],
                ["curricula.id", "curricula.department_id", "curricula.institution_id"],
            )
        )
OfficialDocument.__table__.append_constraint(
    ForeignKeyConstraint(
        ["rule_id", "institution_id"],
        ["graduation_rules.id", "graduation_rules.institution_id"],
    )
)

GraduationRule.__table__.append_constraint(
    CheckConstraint(
        "rule_type IN ('credits', 'required_course', 'volunteer', "
        "'thesis', 'certificate', 'custom')",
        name="rule_type",
    )
)
OfficialDocument.__table__.append_constraint(
    CheckConstraint(
        "document_type IN ('academic', 'graduation', 'other')",
        name="document_type",
    )
)

GraduationRule.__table__.append_constraint(
    ForeignKeyConstraint(
        ["rule_set_id", "institution_id"],
        ["rule_sets.id", "rule_sets.institution_id"],
    )
)
