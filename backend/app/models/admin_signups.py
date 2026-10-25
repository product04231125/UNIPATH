"""Initial/unregistered school requests; proposed schools remain outside the official catalogue."""

from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class SchoolAdminSignup(Base):
    __tablename__ = "school_admin_signups"
    __table_args__ = (
        CheckConstraint("status IN ('pending','approved','rejected','cancelled')", name="status"),
        CheckConstraint("version >= 1", name="version"),
        CheckConstraint(
            "(status = 'pending' AND reviewed_at IS NULL AND reviewed_by IS NULL "
            "AND granted_scope_id IS NULL AND NOT identity_verified "
            "AND NOT affiliation_verified) OR "
            "((status = 'rejected' OR status = 'cancelled') AND reviewed_at IS NOT NULL "
            "AND reviewed_by IS NOT NULL AND granted_scope_id IS NULL "
            "AND NOT identity_verified AND NOT affiliation_verified) OR "
            "(status = 'approved' AND reviewed_at IS NOT NULL AND reviewed_by IS NOT NULL "
            "AND granted_scope_id IS NOT NULL AND institution_id IS NOT NULL "
            "AND identity_verified AND affiliation_verified)",
            name="decision",
        ),
        Index("uq_school_admin_signups_client", "applicant_id", "client_id", unique=True),
        Index(
            "uq_school_admin_signups_pending",
            "applicant_id",
            "school_key",
            unique=True,
            postgresql_where=text("status = 'pending'"),
        ),
    )
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    applicant_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    institution_id: Mapped[UUID | None] = mapped_column(ForeignKey("institutions.id"), index=True)
    school_name: Mapped[str] = mapped_column(String(128))
    school_key: Mapped[str] = mapped_column(String(384))
    official_url: Mapped[str] = mapped_column(String(2048), default="")
    client_id: Mapped[UUID] = mapped_column()
    payload_hash: Mapped[str] = mapped_column(String(64))
    position: Mapped[str] = mapped_column(String(128))
    contact_email: Mapped[str] = mapped_column(String(254))
    reason: Mapped[str] = mapped_column(String(1000))
    status: Mapped[str] = mapped_column(String(16), default="pending")
    version: Mapped[int] = mapped_column(Integer, default=1)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    reviewed_by: Mapped[UUID | None] = mapped_column(ForeignKey("users.id"))
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    review_note: Mapped[str] = mapped_column(String(500), default="")
    identity_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    affiliation_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    granted_scope_id: Mapped[UUID | None] = mapped_column(ForeignKey("admin_scopes.id"))
