"""Scoped, reviewed extraction records; separate from academic metadata approval."""

from datetime import date, datetime
from uuid import UUID, uuid4

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    ForeignKeyConstraint,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.models.academic import CatalogRecord
from app.models.base import Base


class KnowledgeDocument(CatalogRecord, Base):
    __tablename__ = "school_knowledge_documents"
    source_document_id: Mapped[UUID] = mapped_column(unique=True)
    source_document_version: Mapped[int] = mapped_column(Integer)
    department_id: Mapped[UUID | None] = mapped_column()
    curriculum_id: Mapped[UUID | None] = mapped_column()
    document_hash: Mapped[str] = mapped_column(String(64))
    page_count: Mapped[int] = mapped_column(Integer)
    extractor_version: Mapped[str] = mapped_column(String(128))
    source_checked_on: Mapped[date] = mapped_column(Date)
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
            ["source_document_id", "institution_id"],
            ["official_documents.id", "official_documents.institution_id"],
        ),
        ForeignKeyConstraint(
            ["department_id", "institution_id"], ["departments.id", "departments.institution_id"]
        ),
        ForeignKeyConstraint(
            ["curriculum_id", "department_id", "institution_id"],
            ["curricula.id", "curricula.department_id", "curricula.institution_id"],
        ),
        CheckConstraint("version >= 1 AND source_document_version >= 1", name="versions"),
        CheckConstraint("page_count BETWEEN 1 AND 200", name="page_count"),
        CheckConstraint("document_hash ~ '^[0-9a-f]{64}$'", name="document_hash"),
        CheckConstraint("curriculum_id IS NULL OR department_id IS NOT NULL", name="scope"),
        CheckConstraint("status IN ('draft','approved','revoked')", name="status"),
        CheckConstraint(
            "(status = 'draft' AND approved_by IS NULL AND approved_at IS NULL) OR "
            "(status <> 'draft' AND approved_by IS NOT NULL "
            "AND approved_at IS NOT NULL AND length(trim(review_note)) > 0)",
            name="approval",
        ),
        CheckConstraint(
            "(status <> 'revoked' AND revoked_by IS NULL AND revoked_at IS NULL) OR "
            "(status = 'revoked' AND revoked_by IS NOT NULL AND revoked_at IS NOT NULL "
            "AND length(trim(revocation_reason)) > 0)",
            name="revocation",
        ),
    )


class KnowledgeChunk(Base):
    __tablename__ = "school_knowledge_chunks"
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    knowledge_document_id: Mapped[UUID] = mapped_column()
    institution_id: Mapped[UUID] = mapped_column()
    page: Mapped[int] = mapped_column(Integer)
    part_index: Mapped[int] = mapped_column(Integer)
    part_count: Mapped[int] = mapped_column(Integer)
    character_start: Mapped[int] = mapped_column(Integer)
    character_end: Mapped[int] = mapped_column(Integer)
    content: Mapped[str] = mapped_column(Text)
    is_blank: Mapped[bool] = mapped_column(Boolean, default=False)
    content_hash: Mapped[str] = mapped_column(String(64))
    page_hash: Mapped[str] = mapped_column(String(64))
    admission_years: Mapped[list | None] = mapped_column(JSONB(none_as_null=True), nullable=True)
    tracks: Mapped[list | None] = mapped_column(JSONB(none_as_null=True), nullable=True)
    warnings: Mapped[list] = mapped_column(JSONB)
    __table_args__ = (
        UniqueConstraint("id", "institution_id"),
        UniqueConstraint("knowledge_document_id", "page", "part_index"),
        ForeignKeyConstraint(
            ["knowledge_document_id", "institution_id"],
            ["school_knowledge_documents.id", "school_knowledge_documents.institution_id"],
            ondelete="CASCADE",
        ),
        CheckConstraint("page BETWEEN 1 AND 200", name="page"),
        CheckConstraint(
            "part_index >= 0 AND part_index < part_count AND part_count <= 20", name="parts"
        ),
        CheckConstraint(
            "character_start >= 0 AND character_end = character_start + char_length(content) "
            "AND ((NOT is_blank AND char_length(content) BETWEEN 1 AND 20000) OR "
            "(is_blank AND content = '' AND part_index = 0 AND part_count = 1 "
            "AND character_start = 0))",
            name="content_bounds",
        ),
        CheckConstraint(
            "content_hash ~ '^[0-9a-f]{64}$' AND page_hash ~ '^[0-9a-f]{64}$'", name="hashes"
        ),
        CheckConstraint("jsonb_typeof(warnings) = 'array'", name="warnings"),
        CheckConstraint(
            "admission_years IS NULL OR jsonb_typeof(admission_years) = 'array'", name="years"
        ),
        CheckConstraint("tracks IS NULL OR jsonb_typeof(tracks) = 'array'", name="tracks"),
    )
