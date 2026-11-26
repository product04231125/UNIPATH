"""Which collected guidance bundle each registered school shows its students."""

from datetime import datetime
from uuid import UUID

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class AcademicGuidanceBinding(Base):
    __tablename__ = "academic_guidance_bindings"
    __table_args__ = (CheckConstraint("version >= 1", name="version"),)
    # One binding per school; no row means the school shows no collected guidance.
    institution_id: Mapped[UUID] = mapped_column(ForeignKey("institutions.id"), primary_key=True)
    bundle_id: Mapped[str] = mapped_column(String(64))
    edition: Mapped[str] = mapped_column(String(64))
    version: Mapped[int] = mapped_column(Integer, default=1)
    created_by: Mapped[UUID] = mapped_column(ForeignKey("users.id"))
    updated_by: Mapped[UUID] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
