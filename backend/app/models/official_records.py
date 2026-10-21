"""Private normalized record batches with immutable approvals and master references."""

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


class OfficialRecordBatch(Base):
    __tablename__ = "official_record_batches"
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    source_id: Mapped[UUID] = mapped_column(index=True)
    owner_id: Mapped[UUID] = mapped_column(ForeignKey("users.id"), index=True)
    institution_id: Mapped[UUID] = mapped_column(ForeignKey("institutions.id"), index=True)
    source_version: Mapped[int] = mapped_column(Integer)
    source_sha256: Mapped[str] = mapped_column(String(64))
    client_id: Mapped[UUID] = mapped_column()
    creation_digest: Mapped[str] = mapped_column(String(64))
    data_digest: Mapped[str] = mapped_column(String(64))
    kind: Mapped[str] = mapped_column(String(16))
    status: Mapped[str] = mapped_column(String(16), default="draft")
    version: Mapped[int] = mapped_column(Integer, default=1)
    department_id: Mapped[UUID | None] = mapped_column()
    curriculum_id: Mapped[UUID | None] = mapped_column()
    admission_year: Mapped[int | None] = mapped_column(Integer)
    track: Mapped[str | None] = mapped_column(String(64))
    coverage: Mapped[str] = mapped_column(String(16))
    page_count: Mapped[int] = mapped_column(Integer)
    records_as_of: Mapped[date] = mapped_column(Date)
    record_count: Mapped[int] = mapped_column(Integer)
    data_json: Mapped[dict] = mapped_column(JSONB, deferred=True)
    created_by: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    approved_by: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    approved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    __table_args__ = (
        UniqueConstraint("owner_id", "client_id"),
        UniqueConstraint("id", "institution_id"),
        ForeignKeyConstraint(
            ["source_id", "owner_id", "institution_id"],
            [
                "official_record_sources.id",
                "official_record_sources.owner_id",
                "official_record_sources.institution_id",
            ],
        ),
        ForeignKeyConstraint(
            ["department_id", "institution_id"], ["departments.id", "departments.institution_id"]
        ),
        ForeignKeyConstraint(
            ["curriculum_id", "department_id", "institution_id"],
            ["curricula.id", "curricula.department_id", "curricula.institution_id"],
        ),
        CheckConstraint("version >= 1 AND source_version >= 1", name="versions"),
        CheckConstraint(
            "source_sha256 ~ '^[0-9a-f]{64}$' AND creation_digest ~ '^[0-9a-f]{64}$' "
            "AND data_digest ~ '^[0-9a-f]{64}$'",
            name="digests",
        ),
        CheckConstraint("kind IN ('academics','volunteers','certificates','theses')", name="kind"),
        CheckConstraint(
            "status IN ('draft','approved','revoked','superseded','discarded')", name="status"
        ),
        CheckConstraint("coverage IN ('complete','partial')", name="coverage"),
        CheckConstraint(
            "page_count >= 1 AND page_count <= 500 AND record_count >= 0 AND record_count <= 500",
            name="record_limits",
        ),
        CheckConstraint("curriculum_id IS NULL OR department_id IS NOT NULL", name="hierarchy"),
        CheckConstraint(
            "admission_year IS NULL OR admission_year >= 1000 AND admission_year <= 9999",
            name="admission_year",
        ),
        CheckConstraint(
            "status <> 'approved' OR approved_at IS NOT NULL "
            "AND department_id IS NOT NULL AND admission_year IS NOT NULL AND track IS NOT NULL",
            name="approval_context",
        ),
        CheckConstraint(
            "jsonb_typeof(data_json) = 'object' AND data_json ? 'records' "
            "AND data_json ? 'kind' AND jsonb_typeof(data_json->'records') = 'array' "
            "AND jsonb_array_length(data_json->'records') = record_count "
            "AND data_json->>'kind' = kind",
            name="payload_shape",
        ),
    )


class OfficialRecordBatchEvent(Base):
    __tablename__ = "official_record_batch_events"
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    batch_id: Mapped[UUID] = mapped_column(ForeignKey("official_record_batches.id"), index=True)
    actor_id: Mapped[UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    version: Mapped[int] = mapped_column(Integer)
    action: Mapped[str] = mapped_column(String(24))
    reason: Mapped[str] = mapped_column(String(500), default="")
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    __table_args__ = (
        UniqueConstraint("batch_id", "version"),
        CheckConstraint("version >= 1", name="version"),
        CheckConstraint(
            "action IN ('created','replaced','approved','revoked','superseded',"
            "'source_revoked','source_withdrawn','discarded')",
            name="action",
        ),
    )


class OfficialRecordCourseRef(Base):
    __tablename__ = "official_record_course_refs"
    batch_id: Mapped[UUID] = mapped_column(primary_key=True)
    course_id: Mapped[UUID] = mapped_column(primary_key=True, index=True)
    institution_id: Mapped[UUID] = mapped_column()
    catalog_version: Mapped[int] = mapped_column(Integer)
    code: Mapped[str] = mapped_column(String(64))
    name: Mapped[str] = mapped_column(String(128))
    __table_args__ = (
        ForeignKeyConstraint(
            ["batch_id", "institution_id"],
            ["official_record_batches.id", "official_record_batches.institution_id"],
        ),
        ForeignKeyConstraint(
            ["course_id", "institution_id"], ["courses.id", "courses.institution_id"]
        ),
        CheckConstraint("catalog_version >= 1", name="version"),
    )


class OfficialRecordCertificateRef(Base):
    __tablename__ = "official_record_certificate_refs"
    batch_id: Mapped[UUID] = mapped_column(primary_key=True)
    certificate_id: Mapped[UUID] = mapped_column(
        ForeignKey("certificates.id"), primary_key=True, index=True
    )
    institution_id: Mapped[UUID] = mapped_column()
    catalog_version: Mapped[int] = mapped_column(Integer)
    code: Mapped[str] = mapped_column(String(64))
    name: Mapped[str] = mapped_column(String(128))
    provider_id: Mapped[UUID] = mapped_column(ForeignKey("certificate_providers.id"), index=True)
    provider_version: Mapped[int] = mapped_column(Integer)
    provider_name: Mapped[str] = mapped_column(String(128))
    __table_args__ = (
        ForeignKeyConstraint(
            ["batch_id", "institution_id"],
            ["official_record_batches.id", "official_record_batches.institution_id"],
        ),
        CheckConstraint("catalog_version >= 1 AND provider_version >= 1", name="versions"),
    )


Index(
    "uq_official_record_batches_draft",
    OfficialRecordBatch.source_id,
    OfficialRecordBatch.kind,
    unique=True,
    postgresql_where=text("status = 'draft'"),
)
Index(
    "uq_official_record_batches_approved",
    OfficialRecordBatch.owner_id,
    OfficialRecordBatch.institution_id,
    OfficialRecordBatch.department_id,
    OfficialRecordBatch.curriculum_id,
    OfficialRecordBatch.admission_year,
    OfficialRecordBatch.track,
    OfficialRecordBatch.kind,
    unique=True,
    postgresql_where=text("status = 'approved'"),
    postgresql_nulls_not_distinct=True,
)
