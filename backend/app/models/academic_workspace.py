"""Additive administrator catalog revisions; never student records or audit inputs."""

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
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class ClassificationRevision(Base):
    __tablename__ = "academic_classification_revisions"
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    institution_id: Mapped[UUID] = mapped_column(ForeignKey("institutions.id"), index=True)
    revision: Mapped[int] = mapped_column(Integer)
    version: Mapped[int] = mapped_column(Integer, default=1)
    status: Mapped[str] = mapped_column(String(16), default="draft")
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    published_by: Mapped[UUID | None] = mapped_column(ForeignKey("users.id"))
    digest: Mapped[str | None] = mapped_column(String(64))
    review_note: Mapped[str] = mapped_column(String(1000), default="")
    created_by: Mapped[UUID] = mapped_column(ForeignKey("users.id"))
    updated_by: Mapped[UUID] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    __table_args__ = (
        UniqueConstraint("id", "institution_id"),
        UniqueConstraint("institution_id", "revision"),
        CheckConstraint("revision >= 1 AND version >= 1", name="versions"),
        CheckConstraint("status IN ('draft','published','withdrawn')", name="status"),
        CheckConstraint(
            "(status = 'draft' AND published_at IS NULL AND published_by IS NULL "
            "AND digest IS NULL) OR (status <> 'draft' AND published_at IS NOT NULL "
            "AND published_by IS NOT NULL AND digest IS NOT NULL)",
            name="publication",
        ),
        Index(
            "uq_academic_classifications_draft",
            "institution_id",
            unique=True,
            postgresql_where=text("status = 'draft'"),
        ),
    )


class ClassificationNode(Base):
    __tablename__ = "academic_classification_nodes"
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    institution_id: Mapped[UUID] = mapped_column()
    revision_id: Mapped[UUID] = mapped_column(index=True)
    logical_id: Mapped[UUID] = mapped_column(default=uuid4)
    parent_id: Mapped[UUID | None] = mapped_column()
    label: Mapped[str] = mapped_column(String(128))
    position: Mapped[int] = mapped_column(Integer)
    selectable: Mapped[bool] = mapped_column(Boolean, default=True)
    __table_args__ = (
        UniqueConstraint("id", "revision_id", "institution_id", name="uq_academic_node_revision"),
        UniqueConstraint("id", "institution_id"),
        UniqueConstraint("revision_id", "logical_id"),
        ForeignKeyConstraint(
            ["revision_id", "institution_id"],
            [
                "academic_classification_revisions.id",
                "academic_classification_revisions.institution_id",
            ],
            ondelete="CASCADE",
        ),
        ForeignKeyConstraint(
            ["parent_id", "revision_id", "institution_id"],
            [
                "academic_classification_nodes.id",
                "academic_classification_nodes.revision_id",
                "academic_classification_nodes.institution_id",
            ],
            deferrable=True,
            initially="DEFERRED",
        ),
        CheckConstraint("position >= 0", name="position"),
        CheckConstraint("parent_id IS NULL OR parent_id <> id", name="parent"),
        CheckConstraint("length(trim(label)) > 0", name="label"),
        Index(
            "uq_academic_node_root_position",
            "revision_id",
            "position",
            unique=True,
            postgresql_where=text("parent_id IS NULL"),
        ),
        Index(
            "uq_academic_node_child_position",
            "revision_id",
            "parent_id",
            "position",
            unique=True,
            postgresql_where=text("parent_id IS NOT NULL"),
        ),
    )


class StudyTrack(Base):
    __tablename__ = "academic_study_tracks"
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    institution_id: Mapped[UUID] = mapped_column(ForeignKey("institutions.id"), index=True)
    name: Mapped[str] = mapped_column(String(128))
    version: Mapped[int] = mapped_column(Integer, default=1)
    inactive_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_by: Mapped[UUID] = mapped_column(ForeignKey("users.id"))
    updated_by: Mapped[UUID] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    __table_args__ = (
        UniqueConstraint("id", "institution_id"),
        CheckConstraint("version >= 1", name="version"),
        CheckConstraint("length(trim(name)) > 0", name="name"),
    )


class AcademicMutationReceipt(Base):
    __tablename__ = "academic_mutation_receipts"
    actor_id: Mapped[UUID] = mapped_column(ForeignKey("users.id"), primary_key=True)
    client_id: Mapped[UUID] = mapped_column(primary_key=True)
    institution_id: Mapped[UUID] = mapped_column(ForeignKey("institutions.id"))
    operation: Mapped[str] = mapped_column(String(128))
    request_digest: Mapped[str] = mapped_column(String(64))
    response_json: Mapped[dict] = mapped_column(JSONB)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    __table_args__ = (
        CheckConstraint("request_digest ~ '^[0-9a-f]{64}$'", name="digest"),
        CheckConstraint("jsonb_typeof(response_json) = 'object'", name="response"),
    )


class AcademicCurriculumRevision(Base):
    __tablename__ = "academic_curriculum_revisions"
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    institution_id: Mapped[UUID] = mapped_column(ForeignKey("institutions.id"), index=True)
    lineage_id: Mapped[UUID] = mapped_column(default=uuid4, index=True)
    legacy_curriculum_id: Mapped[UUID | None] = mapped_column()
    classification_revision_id: Mapped[UUID] = mapped_column()
    revision: Mapped[int] = mapped_column(Integer)
    version: Mapped[int] = mapped_column(Integer, default=1)
    name: Mapped[str] = mapped_column(String(128))
    curriculum_year: Mapped[int | None] = mapped_column(Integer)
    scope_json: Mapped[dict] = mapped_column(JSONB)
    status: Mapped[str] = mapped_column(String(16), default="draft")
    digest: Mapped[str | None] = mapped_column(String(64))
    review_note: Mapped[str] = mapped_column(String(1000), default="")
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    published_by: Mapped[UUID | None] = mapped_column(ForeignKey("users.id"))
    created_by: Mapped[UUID] = mapped_column(ForeignKey("users.id"))
    updated_by: Mapped[UUID] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    __table_args__ = (
        UniqueConstraint("id", "institution_id"),
        UniqueConstraint(
            "id", "classification_revision_id", "institution_id", name="uq_ac_cur_class"
        ),
        UniqueConstraint("lineage_id", "revision"),
        ForeignKeyConstraint(
            ["legacy_curriculum_id", "institution_id"], ["curricula.id", "curricula.institution_id"]
        ),
        ForeignKeyConstraint(
            ["classification_revision_id", "institution_id"],
            [
                "academic_classification_revisions.id",
                "academic_classification_revisions.institution_id",
            ],
        ),
        CheckConstraint("version >= 1 AND revision >= 1", name="versions"),
        CheckConstraint("status IN ('draft','published','withdrawn')", name="status"),
        CheckConstraint(
            "curriculum_year IS NULL OR curriculum_year BETWEEN 1000 AND 9999", name="year"
        ),
        CheckConstraint("jsonb_typeof(scope_json) = 'object'", name="scope"),
        Index(
            "uq_academic_curriculum_draft",
            "lineage_id",
            unique=True,
            postgresql_where=text("status = 'draft'"),
        ),
    )


class AcademicCurriculumCourse(Base):
    __tablename__ = "academic_curriculum_courses"
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    logical_id: Mapped[UUID] = mapped_column(default=uuid4)
    institution_id: Mapped[UUID] = mapped_column()
    curriculum_revision_id: Mapped[UUID] = mapped_column(index=True)
    classification_revision_id: Mapped[UUID] = mapped_column()
    course_id: Mapped[UUID] = mapped_column()
    course_version: Mapped[int] = mapped_column(Integer)
    course_name: Mapped[str] = mapped_column(String(128))
    course_code: Mapped[str] = mapped_column(String(64))
    classification_node_id: Mapped[UUID] = mapped_column()
    requirement: Mapped[str] = mapped_column(String(20))
    recognized_credits: Mapped[Decimal | None] = mapped_column(Numeric(8, 3))
    grading_basis: Mapped[str] = mapped_column(
        String(16), default="unspecified", server_default="unspecified"
    )
    position: Mapped[int] = mapped_column(Integer)
    __table_args__ = (
        UniqueConstraint("id", "institution_id"),
        UniqueConstraint("curriculum_revision_id", "course_id"),
        UniqueConstraint("curriculum_revision_id", "logical_id", name="uq_ac_cur_course_logical"),
        UniqueConstraint("curriculum_revision_id", "position", name="uq_ac_cur_course_position"),
        ForeignKeyConstraint(
            ["curriculum_revision_id", "classification_revision_id", "institution_id"],
            [
                "academic_curriculum_revisions.id",
                "academic_curriculum_revisions.classification_revision_id",
                "academic_curriculum_revisions.institution_id",
            ],
            ondelete="CASCADE",
        ),
        ForeignKeyConstraint(
            ["course_id", "institution_id"], ["courses.id", "courses.institution_id"]
        ),
        ForeignKeyConstraint(
            ["classification_node_id", "classification_revision_id", "institution_id"],
            [
                "academic_classification_nodes.id",
                "academic_classification_nodes.revision_id",
                "academic_classification_nodes.institution_id",
            ],
        ),
        CheckConstraint("course_version >= 1 AND position >= 0", name="versions"),
        CheckConstraint("recognized_credits >= 0 AND recognized_credits <= 100", name="credits"),
        CheckConstraint(
            "grading_basis IN ('unspecified','graded','pass_fail')", name="grading_basis"
        ),
        CheckConstraint(
            "recognized_credits IS NOT NULL OR grading_basis = 'pass_fail'", name="known_credits"
        ),
        CheckConstraint(
            "requirement IN ('required','elective','not_specified')", name="requirement"
        ),
    )


class AcademicCurriculumTrackRef(Base):
    __tablename__ = "academic_curriculum_track_refs"
    curriculum_revision_id: Mapped[UUID] = mapped_column(primary_key=True)
    track_id: Mapped[UUID] = mapped_column(primary_key=True)
    institution_id: Mapped[UUID] = mapped_column()
    __table_args__ = (
        ForeignKeyConstraint(
            ["curriculum_revision_id", "institution_id"],
            ["academic_curriculum_revisions.id", "academic_curriculum_revisions.institution_id"],
            ondelete="CASCADE",
        ),
        ForeignKeyConstraint(
            ["track_id", "institution_id"],
            ["academic_study_tracks.id", "academic_study_tracks.institution_id"],
        ),
    )


class AcademicCurriculumDepartmentRef(Base):
    __tablename__ = "academic_curriculum_department_refs"
    curriculum_revision_id: Mapped[UUID] = mapped_column(primary_key=True)
    department_id: Mapped[UUID] = mapped_column(primary_key=True)
    institution_id: Mapped[UUID] = mapped_column()
    __table_args__ = (
        ForeignKeyConstraint(
            ["curriculum_revision_id", "institution_id"],
            ["academic_curriculum_revisions.id", "academic_curriculum_revisions.institution_id"],
            ondelete="CASCADE",
        ),
        ForeignKeyConstraint(
            ["department_id", "institution_id"], ["departments.id", "departments.institution_id"]
        ),
    )


class AcademicRequirementRevision(Base):
    __tablename__ = "academic_requirement_revisions"
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    institution_id: Mapped[UUID] = mapped_column(ForeignKey("institutions.id"), index=True)
    lineage_id: Mapped[UUID] = mapped_column(default=uuid4, index=True)
    revision: Mapped[int] = mapped_column(Integer)
    version: Mapped[int] = mapped_column(Integer, default=1)
    name: Mapped[str] = mapped_column(String(128))
    effective_from: Mapped[date | None] = mapped_column(Date)
    effective_to: Mapped[date | None] = mapped_column(Date)
    kind: Mapped[str] = mapped_column(String(24))
    scope_json: Mapped[dict] = mapped_column(JSONB)
    content_json: Mapped[dict] = mapped_column(JSONB)
    classification_revision_id: Mapped[UUID | None] = mapped_column()
    curriculum_revision_id: Mapped[UUID | None] = mapped_column()
    legacy_rule_id: Mapped[UUID | None] = mapped_column()
    legacy_rule_version: Mapped[int | None] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String(16), default="draft")
    digest: Mapped[str | None] = mapped_column(String(64))
    review_note: Mapped[str] = mapped_column(String(1000), default="")
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    published_by: Mapped[UUID | None] = mapped_column(ForeignKey("users.id"))
    withdrawn_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    withdrawal_reason: Mapped[str | None] = mapped_column(String(1000))
    created_by: Mapped[UUID] = mapped_column(ForeignKey("users.id"))
    updated_by: Mapped[UUID] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    __table_args__ = (
        UniqueConstraint("id", "institution_id"),
        UniqueConstraint(
            "id", "classification_revision_id", "institution_id", name="uq_ac_req_class"
        ),
        UniqueConstraint("lineage_id", "revision"),
        ForeignKeyConstraint(
            ["classification_revision_id", "institution_id"],
            [
                "academic_classification_revisions.id",
                "academic_classification_revisions.institution_id",
            ],
        ),
        ForeignKeyConstraint(
            ["curriculum_revision_id", "institution_id"],
            ["academic_curriculum_revisions.id", "academic_curriculum_revisions.institution_id"],
        ),
        ForeignKeyConstraint(
            ["legacy_rule_id", "institution_id"],
            ["graduation_rules.id", "graduation_rules.institution_id"],
        ),
        CheckConstraint("version >= 1 AND revision >= 1", name="versions"),
        CheckConstraint("kind IN ('checklist','certification','credit_table')", name="kind"),
        CheckConstraint("status IN ('draft','published','withdrawn')", name="status"),
        CheckConstraint(
            "effective_from IS NULL OR effective_to IS NULL OR effective_from <= effective_to",
            name="period",
        ),
        CheckConstraint(
            "jsonb_typeof(scope_json) = 'object' AND "
            "jsonb_typeof(content_json) = 'object' AND "
            "coalesce(content_json->>'kind' = kind, false)",
            name="content",
        ),
        CheckConstraint(
            "(status='draft' AND published_at IS NULL AND published_by IS NULL "
            "AND digest IS NULL) OR (status<>'draft' AND published_at IS NOT NULL "
            "AND published_by IS NOT NULL AND digest IS NOT NULL)",
            name="publication",
        ),
        CheckConstraint(
            "(status='withdrawn' AND withdrawn_at IS NOT NULL "
            "AND withdrawal_reason IS NOT NULL AND "
            "length(trim(withdrawal_reason)) > 0) OR (status<>'withdrawn' "
            "AND withdrawn_at IS NULL AND withdrawal_reason IS NULL)",
            name="withdrawal",
        ),
        Index(
            "uq_academic_requirement_draft",
            "lineage_id",
            unique=True,
            postgresql_where=text("status = 'draft'"),
        ),
    )


class AcademicCreditRecordBinding(Base):
    """Mutable data wiring; published requirement targets and snapshots stay immutable."""

    __tablename__ = "academic_credit_record_bindings"
    requirement_revision_id: Mapped[UUID] = mapped_column(primary_key=True)
    institution_id: Mapped[UUID] = mapped_column(ForeignKey("institutions.id"))
    version: Mapped[int] = mapped_column(Integer, default=1)
    bindings_json: Mapped[dict] = mapped_column(JSONB, default=dict)
    updated_by: Mapped[UUID] = mapped_column(ForeignKey("users.id"))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    __table_args__ = (
        ForeignKeyConstraint(
            ["requirement_revision_id", "institution_id"],
            ["academic_requirement_revisions.id", "academic_requirement_revisions.institution_id"],
        ),
        CheckConstraint("version >= 1", name="version"),
        CheckConstraint("jsonb_typeof(bindings_json) = 'object'", name="bindings"),
    )


class AcademicRequirementNodeRef(Base):
    __tablename__ = "academic_requirement_node_refs"
    requirement_revision_id: Mapped[UUID] = mapped_column(primary_key=True)
    node_id: Mapped[UUID] = mapped_column(primary_key=True)
    institution_id: Mapped[UUID] = mapped_column()
    classification_revision_id: Mapped[UUID] = mapped_column()
    __table_args__ = (
        ForeignKeyConstraint(
            ["requirement_revision_id", "classification_revision_id", "institution_id"],
            [
                "academic_requirement_revisions.id",
                "academic_requirement_revisions.classification_revision_id",
                "academic_requirement_revisions.institution_id",
            ],
            ondelete="CASCADE",
        ),
        ForeignKeyConstraint(
            ["node_id", "classification_revision_id", "institution_id"],
            [
                "academic_classification_nodes.id",
                "academic_classification_nodes.revision_id",
                "academic_classification_nodes.institution_id",
            ],
        ),
    )


class AcademicRequirementTrackRef(Base):
    __tablename__ = "academic_requirement_track_refs"
    requirement_revision_id: Mapped[UUID] = mapped_column(primary_key=True)
    track_id: Mapped[UUID] = mapped_column(primary_key=True)
    institution_id: Mapped[UUID] = mapped_column()
    __table_args__ = (
        ForeignKeyConstraint(
            ["requirement_revision_id", "institution_id"],
            ["academic_requirement_revisions.id", "academic_requirement_revisions.institution_id"],
            ondelete="CASCADE",
        ),
        ForeignKeyConstraint(
            ["track_id", "institution_id"],
            ["academic_study_tracks.id", "academic_study_tracks.institution_id"],
        ),
    )


class AcademicRequirementDepartmentRef(Base):
    __tablename__ = "academic_requirement_department_refs"
    requirement_revision_id: Mapped[UUID] = mapped_column(primary_key=True)
    department_id: Mapped[UUID] = mapped_column(primary_key=True)
    institution_id: Mapped[UUID] = mapped_column()
    __table_args__ = (
        ForeignKeyConstraint(
            ["requirement_revision_id", "institution_id"],
            ["academic_requirement_revisions.id", "academic_requirement_revisions.institution_id"],
            ondelete="CASCADE",
        ),
        ForeignKeyConstraint(
            ["department_id", "institution_id"], ["departments.id", "departments.institution_id"]
        ),
    )
