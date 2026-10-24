"""Reviewed execution programs anchored to immutable applied academic metadata."""

from datetime import date, datetime
from uuid import UUID, uuid4

from sqlalchemy import (
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    ForeignKeyConstraint,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.models.academic import CatalogRecord
from app.models.base import Base


class RuleProgram(CatalogRecord, Base):
    __tablename__ = "official_rule_programs"
    rule_set_id: Mapped[UUID | None] = mapped_column(index=True)
    rule_id: Mapped[UUID | None] = mapped_column(index=True)
    source_version: Mapped[int] = mapped_column(Integer)
    department_id: Mapped[UUID | None] = mapped_column()
    curriculum_id: Mapped[UUID | None] = mapped_column()
    admission_year_from: Mapped[int] = mapped_column(Integer)
    admission_year_to: Mapped[int] = mapped_column(Integer)
    tracks: Mapped[list] = mapped_column(JSONB)
    effective_from: Mapped[date | None] = mapped_column(Date)
    effective_to: Mapped[date | None] = mapped_column(Date)
    status: Mapped[str] = mapped_column(String(16), default="draft")
    approved_by: Mapped[UUID | None] = mapped_column(ForeignKey("users.id"))
    approved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    review_note: Mapped[str] = mapped_column(String(500), default="")
    revoked_by: Mapped[UUID | None] = mapped_column(ForeignKey("users.id"))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    revocation_reason: Mapped[str] = mapped_column(String(500), default="")
    __table_args__ = (
        UniqueConstraint("id", "institution_id"),
        ForeignKeyConstraint(
            ["rule_set_id", "institution_id"], ["rule_sets.id", "rule_sets.institution_id"]
        ),
        ForeignKeyConstraint(
            ["rule_id", "institution_id"],
            ["graduation_rules.id", "graduation_rules.institution_id"],
        ),
        ForeignKeyConstraint(
            ["department_id", "institution_id"], ["departments.id", "departments.institution_id"]
        ),
        ForeignKeyConstraint(
            ["curriculum_id", "department_id", "institution_id"],
            ["curricula.id", "curricula.department_id", "curricula.institution_id"],
        ),
        CheckConstraint("(rule_set_id IS NULL) <> (rule_id IS NULL)", name="single_target"),
        CheckConstraint("version >= 1 AND source_version >= 1", name="versions"),
        CheckConstraint(
            "admission_year_from >= 1000 AND admission_year_from <= 9999 AND "
            "admission_year_to >= admission_year_from AND admission_year_to <= 9999 AND "
            "admission_year_to - admission_year_from < 200",
            name="years",
        ),
        CheckConstraint(
            "jsonb_typeof(tracks) = 'array' AND jsonb_array_length(tracks) BETWEEN 1 AND 32",
            name="tracks",
        ),
        CheckConstraint("curriculum_id IS NULL OR department_id IS NOT NULL", name="scope"),
        CheckConstraint(
            "effective_from IS NULL OR effective_to IS NULL OR effective_from <= effective_to",
            name="dates",
        ),
        CheckConstraint("status IN ('draft','approved','revoked')", name="status"),
        CheckConstraint(
            "(status = 'draft' AND approved_by IS NULL AND approved_at IS NULL) OR "
            "(status <> 'draft' AND approved_by IS NOT NULL AND approved_at IS NOT NULL "
            "AND length(trim(review_note)) > 0)",
            name="approval",
        ),
        CheckConstraint(
            "(status <> 'revoked' AND revoked_by IS NULL AND revoked_at IS NULL) OR "
            "(status = 'revoked' AND revoked_by IS NOT NULL AND revoked_at IS NOT NULL "
            "AND length(trim(revocation_reason)) > 0)",
            name="revocation",
        ),
    )


class ProgramRule(Base):
    __tablename__ = "official_program_rules"
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    program_id: Mapped[UUID] = mapped_column()
    institution_id: Mapped[UUID] = mapped_column()
    rule_id: Mapped[UUID] = mapped_column()
    source_version: Mapped[int] = mapped_column(Integer)
    title: Mapped[str] = mapped_column(String(128))
    kind: Mapped[str] = mapped_column(String(32))
    condition_json: Mapped[dict] = mapped_column(JSONB)
    __table_args__ = (
        UniqueConstraint("id", "institution_id"),
        UniqueConstraint("program_id", "rule_id"),
        ForeignKeyConstraint(
            ["program_id", "institution_id"],
            ["official_rule_programs.id", "official_rule_programs.institution_id"],
            ondelete="CASCADE",
        ),
        ForeignKeyConstraint(
            ["rule_id", "institution_id"],
            ["graduation_rules.id", "graduation_rules.institution_id"],
        ),
        CheckConstraint("source_version >= 1", name="version"),
        CheckConstraint(
            "kind IN ('minimum_credits','required_courses','minimum_volunteer_hours',"
            "'any_certificate','thesis','manual_review')",
            name="kind",
        ),
        CheckConstraint(
            "jsonb_typeof(condition_json) = 'object' AND "
            "coalesce(condition_json->>'kind' = kind, false)",
            name="condition",
        ),
    )


class ProgramEvidence(Base):
    __tablename__ = "official_program_evidence"
    program_rule_id: Mapped[UUID] = mapped_column(primary_key=True)
    chunk_id: Mapped[UUID] = mapped_column(primary_key=True)
    institution_id: Mapped[UUID] = mapped_column()
    knowledge_version: Mapped[int] = mapped_column(Integer)
    content_hash: Mapped[str] = mapped_column(String(64))
    __table_args__ = (
        ForeignKeyConstraint(
            ["program_rule_id", "institution_id"],
            ["official_program_rules.id", "official_program_rules.institution_id"],
            ondelete="CASCADE",
        ),
        ForeignKeyConstraint(
            ["chunk_id", "institution_id"],
            ["school_knowledge_chunks.id", "school_knowledge_chunks.institution_id"],
        ),
        CheckConstraint("knowledge_version >= 1", name="version"),
        CheckConstraint("content_hash ~ '^[0-9a-f]{64}$'", name="hash"),
    )


class ProgramCourseRef(Base):
    __tablename__ = "official_program_course_refs"
    program_rule_id: Mapped[UUID] = mapped_column(primary_key=True)
    course_id: Mapped[UUID] = mapped_column(primary_key=True)
    institution_id: Mapped[UUID] = mapped_column()
    catalog_version: Mapped[int] = mapped_column(Integer)
    code: Mapped[str] = mapped_column(String(64))
    name: Mapped[str] = mapped_column(String(128))
    __table_args__ = (
        ForeignKeyConstraint(
            ["program_rule_id", "institution_id"],
            ["official_program_rules.id", "official_program_rules.institution_id"],
            ondelete="CASCADE",
        ),
        ForeignKeyConstraint(
            ["course_id", "institution_id"], ["courses.id", "courses.institution_id"]
        ),
        CheckConstraint("catalog_version >= 1", name="version"),
    )


class ProgramCertificateRef(Base):
    __tablename__ = "official_program_certificate_refs"
    program_rule_id: Mapped[UUID] = mapped_column(primary_key=True)
    certificate_id: Mapped[UUID] = mapped_column(ForeignKey("certificates.id"), primary_key=True)
    institution_id: Mapped[UUID] = mapped_column()
    catalog_version: Mapped[int] = mapped_column(Integer)
    code: Mapped[str] = mapped_column(String(64))
    name: Mapped[str] = mapped_column(String(128))
    provider_name: Mapped[str] = mapped_column(String(128))
    __table_args__ = (
        ForeignKeyConstraint(
            ["program_rule_id", "institution_id"],
            ["official_program_rules.id", "official_program_rules.institution_id"],
            ondelete="CASCADE",
        ),
        CheckConstraint("catalog_version >= 1", name="version"),
    )
