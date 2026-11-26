"""내 자료 in the account and saved 채용공고 분석 results with favorites.

Revision ID: 0031_materials_results
Revises: 0030_writing_documents
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0031_materials_results"
down_revision: str | Sequence[str] | None = "0030_writing_documents"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _timestamps(*names: str) -> list[sa.Column]:
    return [
        sa.Column(name, sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False)
        for name in names
    ]


def upgrade() -> None:
    op.create_table(
        "student_materials",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("title", sa.String(length=120), nullable=False),
        sa.Column("material_type", sa.String(length=16), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("filename", sa.String(length=200), nullable=True),
        sa.Column("byte_count", sa.Integer(), nullable=False),
        sa.Column("sha256", sa.String(length=64), nullable=True),
        sa.Column("file_data", sa.LargeBinary(), nullable=True),
        sa.Column("version", sa.Integer(), nullable=False),
        *_timestamps("created_at", "updated_at"),
        sa.CheckConstraint("version >= 1", name=op.f("ck_student_materials_version")),
        sa.CheckConstraint(
            "material_type IN ('portfolio','resume','cover_letter','other')",
            name=op.f("ck_student_materials_material_type"),
        ),
        sa.CheckConstraint(
            "(file_data IS NULL AND filename IS NULL AND sha256 IS NULL AND byte_count = 0)"
            " OR (file_data IS NOT NULL AND filename IS NOT NULL AND sha256 IS NOT NULL"
            " AND byte_count BETWEEN 5 AND 8388608 AND octet_length(file_data) = byte_count)",
            name=op.f("ck_student_materials_file"),
        ),
        sa.CheckConstraint(
            "file_data IS NOT NULL OR length(btrim(description)) > 0",
            name=op.f("ck_student_materials_content"),
        ),
        sa.ForeignKeyConstraint(
            ["owner_id"],
            ["users.id"],
            name=op.f("fk_student_materials_owner_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_student_materials")),
    )
    op.create_index(
        op.f("ix_student_materials_owner_id"), "student_materials", ["owner_id"], unique=False
    )
    op.create_table(
        "analysis_results",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("kind", sa.String(length=16), nullable=False),
        sa.Column("title", sa.String(length=160), nullable=False),
        sa.Column("summary", sa.JSON(), nullable=False),
        sa.Column("input", sa.JSON(), nullable=False),
        sa.Column("result", sa.JSON(), nullable=False),
        sa.Column("favorite", sa.Boolean(), nullable=False),
        *_timestamps("created_at"),
        sa.CheckConstraint(
            "kind IN ('posting','gap','search')", name=op.f("ck_analysis_results_kind")
        ),
        sa.ForeignKeyConstraint(
            ["owner_id"],
            ["users.id"],
            name=op.f("fk_analysis_results_owner_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_analysis_results")),
    )
    op.create_index(
        op.f("ix_analysis_results_owner_id"), "analysis_results", ["owner_id"], unique=False
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_analysis_results_owner_id"), table_name="analysis_results")
    op.drop_table("analysis_results")
    op.drop_index(op.f("ix_student_materials_owner_id"), table_name="student_materials")
    op.drop_table("student_materials")
