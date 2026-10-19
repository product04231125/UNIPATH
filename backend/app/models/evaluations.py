"""Write-once personal calculation snapshots, retained independently of live inputs."""

from datetime import date, datetime
from uuid import UUID, uuid4

from sqlalchemy import (
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class PersonalEvaluation(Base):
    __tablename__ = "personal_evaluations"
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    owner_id: Mapped[UUID] = mapped_column(ForeignKey("users.id"))
    client_id: Mapped[UUID | None] = mapped_column()
    version: Mapped[int] = mapped_column(Integer, default=1)
    # Historical identity, not a live FK: removing a plan must not rewrite a
    # previous result. Ownership is validated before taking the immutable copy.
    curriculum_id: Mapped[UUID] = mapped_column()
    curriculum_version: Mapped[int] = mapped_column(Integer)
    curriculum_title: Mapped[str] = mapped_column(String(128))
    evaluated_on: Mapped[date] = mapped_column(Date)
    status: Mapped[str] = mapped_column(String(16))
    reason: Mapped[str] = mapped_column(String(128))
    result_json: Mapped[dict] = mapped_column(JSONB)
    criteria_json: Mapped[list] = mapped_column(JSONB)
    course_aliases_json: Mapped[dict] = mapped_column(JSONB)
    source_versions_json: Mapped[list] = mapped_column(JSONB)
    input_snapshot_json: Mapped[dict] = mapped_column(JSONB)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    __table_args__ = (
        UniqueConstraint("owner_id", "client_id"),
        CheckConstraint("version = 1 AND curriculum_version >= 1", name="immutable_version"),
        CheckConstraint(
            "status IN ('satisfied','not_satisfied','needs_review','not_applicable')", name="status"
        ),
        CheckConstraint(
            "jsonb_typeof(result_json) = 'object' AND "
            "coalesce(result_json->'official' = 'false'::jsonb, false)",
            name="personal_only",
        ),
        CheckConstraint("coalesce(result_json->>'status' = status, false)", name="status_matches"),
        Index("ix_personal_evaluations_owner_created_id", "owner_id", "created_at", "id"),
    )
