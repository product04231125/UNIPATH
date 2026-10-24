"""Owner-only import receipts retain identities, never a second copy of records."""

from datetime import datetime
from uuid import UUID

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Integer, String, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class PersonalImportReceipt(Base):
    __tablename__ = "personal_import_receipts"
    owner_id: Mapped[UUID] = mapped_column(ForeignKey("users.id"), primary_key=True)
    import_id: Mapped[UUID] = mapped_column(primary_key=True)
    digest: Mapped[str] = mapped_column(String(64))
    record_count: Mapped[int] = mapped_column(Integer)
    profile_version: Mapped[int | None] = mapped_column(Integer)
    mappings_json: Mapped[list] = mapped_column(JSONB)
    committed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    __table_args__ = (
        CheckConstraint("digest ~ '^[0-9a-f]{64}$'", name="digest"),
        CheckConstraint("record_count >= 0 AND record_count <= 500", name="count"),
        CheckConstraint("profile_version IS NULL OR profile_version >= 1", name="profile_version"),
        CheckConstraint("record_count > 0 OR profile_version IS NOT NULL", name="nonempty"),
        CheckConstraint(
            "jsonb_typeof(mappings_json) = 'array' AND "
            "jsonb_array_length(mappings_json) = record_count",
            name="mappings",
        ),
    )
