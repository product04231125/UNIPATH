"""Immutable reviewed catalogue snapshots and owner-only historical audits."""

from datetime import date, datetime
from uuid import UUID, uuid4

from sqlalchemy import (
    CheckConstraint,
    Date,
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


class GraduationScope:
    institution_id: Mapped[UUID] = mapped_column(ForeignKey("institutions.id"))
    department_id: Mapped[UUID] = mapped_column()
    curriculum_id: Mapped[UUID] = mapped_column()
    admission_year: Mapped[int] = mapped_column(Integer)
    track: Mapped[str] = mapped_column(String(64))
    as_of: Mapped[date] = mapped_column(Date)


def scope_constraints():
    return (
        ForeignKeyConstraint(
            ["department_id", "institution_id"], ["departments.id", "departments.institution_id"]
        ),
        ForeignKeyConstraint(
            ["curriculum_id", "department_id", "institution_id"],
            ["curricula.id", "curricula.department_id", "curricula.institution_id"],
        ),
        CheckConstraint("admission_year >= 1000 AND admission_year <= 9999", name="cohort"),
    )


class GraduationCatalogReview(GraduationScope, Base):
    __tablename__ = "graduation_catalog_reviews"
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    client_id: Mapped[UUID] = mapped_column()
    reviewed_by: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    creation_digest: Mapped[str] = mapped_column(String(64))
    snapshot_digest: Mapped[str] = mapped_column(String(64))
    snapshot_json: Mapped[dict] = mapped_column(JSONB, deferred=True)
    review_note: Mapped[str] = mapped_column(String(500))
    version: Mapped[int] = mapped_column(Integer, default=1)
    status: Mapped[str] = mapped_column(String(16), default="approved")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    __table_args__ = (
        *scope_constraints(),
        UniqueConstraint("reviewed_by", "client_id"),
        CheckConstraint("version >= 1", name="version"),
        CheckConstraint("status IN ('approved','revoked','superseded')", name="status"),
        CheckConstraint(
            "creation_digest ~ '^[0-9a-f]{64}$' AND snapshot_digest ~ '^[0-9a-f]{64}$'",
            name="digests",
        ),
        CheckConstraint("jsonb_typeof(snapshot_json) = 'object'", name="snapshot_shape"),
        CheckConstraint("length(trim(review_note)) > 0", name="review_note"),
        Index("ix_graduation_catalog_reviews_school_id", "institution_id", "id"),
    )


Index(
    "uq_graduation_catalog_review_active",
    GraduationCatalogReview.institution_id,
    GraduationCatalogReview.department_id,
    GraduationCatalogReview.curriculum_id,
    GraduationCatalogReview.admission_year,
    GraduationCatalogReview.track,
    GraduationCatalogReview.as_of,
    unique=True,
    postgresql_where=text("status = 'approved'"),
)


class GraduationCatalogReviewEvent(Base):
    __tablename__ = "graduation_catalog_review_events"
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    review_id: Mapped[UUID] = mapped_column(ForeignKey("graduation_catalog_reviews.id"), index=True)
    actor_id: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    version: Mapped[int] = mapped_column(Integer)
    action: Mapped[str] = mapped_column(String(16))
    reason: Mapped[str] = mapped_column(String(500), default="")
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    __table_args__ = (
        UniqueConstraint("review_id", "version"),
        CheckConstraint("version >= 1", name="version"),
        CheckConstraint("action IN ('approved','revoked','superseded')", name="action"),
    )


class GraduationAudit(GraduationScope, Base):
    __tablename__ = "graduation_audits"
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    owner_id: Mapped[UUID] = mapped_column(ForeignKey("users.id"))
    client_id: Mapped[UUID] = mapped_column()
    version: Mapped[int] = mapped_column(Integer, default=1)
    creation_digest: Mapped[str] = mapped_column(String(64))
    payload_digest: Mapped[str] = mapped_column(String(64))
    payload_bytes: Mapped[int] = mapped_column(Integer)
    payload_json: Mapped[dict] = mapped_column(JSONB, deferred=True)
    status: Mapped[str] = mapped_column(String(16))
    reason: Mapped[str] = mapped_column(String(128))
    catalog_complete: Mapped[bool] = mapped_column()
    eligible_as_of: Mapped[bool] = mapped_column()
    catalog_review_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("graduation_catalog_reviews.id")
    )
    catalog_review_version: Mapped[int | None] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    __table_args__ = (
        *scope_constraints(),
        UniqueConstraint("owner_id", "client_id"),
        CheckConstraint("version = 1", name="immutable"),
        CheckConstraint(
            "status IN ('satisfied','not_satisfied','needs_review','not_applicable')", name="status"
        ),
        CheckConstraint(
            "creation_digest ~ '^[0-9a-f]{64}$' AND payload_digest ~ '^[0-9a-f]{64}$'",
            name="digests",
        ),
        CheckConstraint("payload_bytes >= 1 AND payload_bytes <= 4194304", name="payload_limit"),
        CheckConstraint(
            "eligible_as_of = (status = 'satisfied' AND catalog_complete)", name="eligibility"
        ),
        CheckConstraint(
            "(catalog_review_id IS NULL AND catalog_review_version IS NULL) OR "
            "(catalog_review_id IS NOT NULL AND catalog_review_version IS NOT NULL "
            "AND catalog_review_version >= 1)",
            name="review_version",
        ),
        CheckConstraint(
            "NOT catalog_complete OR catalog_review_id IS NOT NULL", name="complete_review"
        ),
        CheckConstraint(
            "jsonb_typeof(payload_json) = 'object' AND "
            "coalesce(payload_json->'evaluation'->'official' = 'true'::jsonb, false) AND "
            "coalesce(payload_json->'evaluation'->>'status' = status, false)",
            name="official_result",
        ),
        Index("ix_graduation_audits_owner_id", "owner_id", "id"),
    )
