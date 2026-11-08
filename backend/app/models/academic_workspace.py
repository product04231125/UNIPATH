"""Additive administrator catalog revisions; never student records or audit inputs."""

from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    ForeignKeyConstraint,
    Index,
    Integer,
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
