"""Additive student-owned academic bindings and immutable activations."""

from datetime import datetime
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    ForeignKeyConstraint,
    Integer,
    Numeric,
    String,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class StudentAcademicActivation(Base):
    __tablename__ = "student_academic_activations"
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    owner_id: Mapped[UUID] = mapped_column(ForeignKey("users.id"), index=True)
    context_digest: Mapped[str] = mapped_column(String(64))
    selection_digest: Mapped[str] = mapped_column(String(64))
    contexts_json: Mapped[list] = mapped_column(JSONB)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    __table_args__ = (UniqueConstraint("id", "owner_id"),)


class StudentAcademicWorkspace(Base):
    __tablename__ = "student_academic_workspaces"
    owner_id: Mapped[UUID] = mapped_column(ForeignKey("users.id"), primary_key=True)
    version: Mapped[int] = mapped_column(Integer, default=0)
    active_activation_id: Mapped[UUID | None] = mapped_column()
    __table_args__ = (
        ForeignKeyConstraint(
            ["active_activation_id", "owner_id"],
            ["student_academic_activations.id", "student_academic_activations.owner_id"],
        ),
        CheckConstraint("version >= 0", name="version"),
    )


class StudentAcademicContext(Base):
    __tablename__ = "student_academic_contexts"
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    owner_id: Mapped[UUID] = mapped_column(ForeignKey("student_academic_workspaces.owner_id"))
    institution_id: Mapped[UUID] = mapped_column(ForeignKey("institutions.id"))
    department_id: Mapped[UUID] = mapped_column(ForeignKey("departments.id"))
    track_id: Mapped[UUID] = mapped_column(ForeignKey("academic_study_tracks.id"))
    curriculum_revision_id: Mapped[UUID] = mapped_column(
        ForeignKey("academic_curriculum_revisions.id")
    )
    admission_year: Mapped[int] = mapped_column(Integer)
    primary: Mapped[bool] = mapped_column(Boolean)
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    position: Mapped[int] = mapped_column(Integer)
    __table_args__ = (
        UniqueConstraint("id", "owner_id"),
        CheckConstraint("admission_year BETWEEN 1000 AND 9999", name="year"),
        CheckConstraint("position >= 0", name="position"),
    )


class StudentAcademicDocument(Base):
    __tablename__ = "student_academic_documents"
    activation_id: Mapped[UUID] = mapped_column(
        ForeignKey("student_academic_activations.id"), primary_key=True
    )
    requirement_revision_id: Mapped[UUID] = mapped_column(
        ForeignKey("academic_requirement_revisions.id"), primary_key=True
    )
    snapshot_json: Mapped[dict] = mapped_column(JSONB)


class StudentAcademicResponse(Base):
    __tablename__ = "student_academic_responses"
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    owner_id: Mapped[UUID] = mapped_column(ForeignKey("users.id"), index=True)
    activation_id: Mapped[UUID] = mapped_column()
    requirement_revision_id: Mapped[UUID] = mapped_column()
    item_id: Mapped[UUID] = mapped_column()
    value: Mapped[bool | None] = mapped_column(Boolean)
    previous_value: Mapped[bool | None] = mapped_column(Boolean)
    needs_confirmation: Mapped[bool] = mapped_column(Boolean, default=False)
    version: Mapped[int] = mapped_column(Integer, default=1)
    confirmed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    # Historical record identity/version/title survives a source record's deletion.
    records_json: Mapped[list] = mapped_column(JSONB, default=list)
    __table_args__ = (
        UniqueConstraint("activation_id", "requirement_revision_id", "item_id"),
        ForeignKeyConstraint(
            ["activation_id", "owner_id"],
            ["student_academic_activations.id", "student_academic_activations.owner_id"],
        ),
        ForeignKeyConstraint(
            ["activation_id", "requirement_revision_id"],
            [
                "student_academic_documents.activation_id",
                "student_academic_documents.requirement_revision_id",
            ],
        ),
        CheckConstraint("version >= 1", name="version"),
    )


class StudentAcademicCourseLink(Base):
    __tablename__ = "student_academic_course_links"
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    owner_id: Mapped[UUID] = mapped_column(ForeignKey("users.id"), index=True)
    course_record_id: Mapped[UUID] = mapped_column()
    context_id: Mapped[UUID] = mapped_column()
    entry_id: Mapped[UUID] = mapped_column(ForeignKey("academic_curriculum_courses.id"))
    record_version: Mapped[int] = mapped_column(Integer)
    result: Mapped[str] = mapped_column(String(20))
    earned_credits: Mapped[Decimal | None] = mapped_column(Numeric(8, 3))
    included: Mapped[bool] = mapped_column(Boolean, default=True)
    version: Mapped[int] = mapped_column(Integer, default=1)
    __table_args__ = (
        UniqueConstraint("owner_id", "course_record_id", "context_id"),
        ForeignKeyConstraint(
            ["course_record_id", "owner_id"],
            ["personal_course_records.id", "personal_course_records.owner_id"],
            ondelete="CASCADE",
        ),
        ForeignKeyConstraint(
            ["context_id", "owner_id"],
            ["student_academic_contexts.id", "student_academic_contexts.owner_id"],
        ),
        CheckConstraint("result IN ('completed','not_completed','needs_review')", name="result"),
        CheckConstraint(
            "earned_credits IS NULL OR earned_credits BETWEEN 0 AND 100", name="credits"
        ),
        CheckConstraint("version >= 1 AND record_version >= 1", name="versions"),
    )


class StudentAcademicReceipt(Base):
    __tablename__ = "student_academic_receipts"
    owner_id: Mapped[UUID] = mapped_column(ForeignKey("users.id"), primary_key=True)
    client_id: Mapped[UUID] = mapped_column(primary_key=True)
    request_digest: Mapped[str] = mapped_column(String(64))
    response_json: Mapped[dict] = mapped_column(JSONB)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
