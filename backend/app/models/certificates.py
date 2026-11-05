"""Shared certificate identities, separate from any user's possession or validity."""

from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class GlobalCatalogRecord:
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    code: Mapped[str] = mapped_column(String(64))
    name: Mapped[str] = mapped_column(String(128))
    official_url: Mapped[str] = mapped_column(String(2048))
    status: Mapped[str] = mapped_column(String(16), default="active")
    version: Mapped[int] = mapped_column(Integer, default=1)
    created_by: Mapped[UUID] = mapped_column(ForeignKey("users.id"))
    updated_by: Mapped[UUID] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class CertificateProvider(GlobalCatalogRecord, Base):
    __tablename__ = "certificate_providers"
    __table_args__ = (
        UniqueConstraint("code"),
        CheckConstraint("version >= 1", name="version"),
        CheckConstraint("status IN ('active','inactive')", name="status"),
    )


class Certificate(GlobalCatalogRecord, Base):
    __tablename__ = "certificates"
    provider_id: Mapped[UUID] = mapped_column(ForeignKey("certificate_providers.id"), index=True)
    __table_args__ = (
        UniqueConstraint("provider_id", "code"),
        CheckConstraint("version >= 1", name="version"),
        CheckConstraint("status IN ('active','inactive')", name="status"),
    )
