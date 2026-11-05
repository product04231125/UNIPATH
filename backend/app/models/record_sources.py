"""Private school-issued evidence; independent of personal records and public RAG."""

from datetime import date, datetime
from uuid import UUID, uuid4

from sqlalchemy import (
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    ForeignKeyConstraint,
    Integer,
    LargeBinary,
    String,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class OfficialRecordSource(Base):
    __tablename__ = "official_record_sources"
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    owner_id: Mapped[UUID] = mapped_column(ForeignKey("users.id"), index=True)
    client_id: Mapped[UUID] = mapped_column()
    institution_id: Mapped[UUID] = mapped_column(ForeignKey("institutions.id"), index=True)
    department_id: Mapped[UUID | None] = mapped_column()
    curriculum_id: Mapped[UUID | None] = mapped_column()
    document_kind: Mapped[str] = mapped_column(String(24))
    issued_on: Mapped[date] = mapped_column(Date)
    filename: Mapped[str] = mapped_column(String(128))
    sha256: Mapped[str] = mapped_column(String(64))
    byte_count: Mapped[int] = mapped_column(Integer)
    file_data: Mapped[bytes] = mapped_column(LargeBinary, deferred=True)
    status: Mapped[str] = mapped_column(String(16), default="submitted")
    version: Mapped[int] = mapped_column(Integer, default=1)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    __table_args__ = (
        UniqueConstraint("owner_id", "client_id"),
        UniqueConstraint(
            "id", "owner_id", "institution_id", name="uq_official_record_sources_owner_scope"
        ),
        CheckConstraint("version >= 1", name="version"),
        CheckConstraint("sha256 ~ '^[0-9a-f]{64}$'", name="sha256"),
        CheckConstraint(
            "byte_count >= 1 AND byte_count <= 2097152 AND octet_length(file_data) = byte_count",
            name="file_size",
        ),
        CheckConstraint(
            "status IN ('submitted','verified','rejected','revoked','withdrawn')", name="status"
        ),
        CheckConstraint(
            "document_kind IN ('transcript','volunteer','certificate','thesis','other')",
            name="document_kind",
        ),
        CheckConstraint("curriculum_id IS NULL OR department_id IS NOT NULL", name="hierarchy"),
        ForeignKeyConstraint(
            ["department_id", "institution_id"], ["departments.id", "departments.institution_id"]
        ),
        ForeignKeyConstraint(
            ["curriculum_id", "department_id", "institution_id"],
            ["curricula.id", "curricula.department_id", "curricula.institution_id"],
        ),
    )


class OfficialRecordSourceEvent(Base):
    __tablename__ = "official_record_source_events"
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    source_id: Mapped[UUID] = mapped_column(ForeignKey("official_record_sources.id"), index=True)
    actor_id: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    version: Mapped[int] = mapped_column(Integer)
    action: Mapped[str] = mapped_column(String(16))
    reason: Mapped[str] = mapped_column(String(500), default="")
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    __table_args__ = (
        UniqueConstraint("source_id", "version"),
        CheckConstraint("version >= 1", name="version"),
        CheckConstraint(
            "action IN ('submitted','verified','rejected','revoked','withdrawn')", name="action"
        ),
    )
