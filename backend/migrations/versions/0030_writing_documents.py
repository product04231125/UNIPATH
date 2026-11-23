"""Saved 자기소개서·포트폴리오 drafts, so a student can keep several and edit them later.

Revision ID: 0030_writing_documents
Revises: 0029_career_goals
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0030_writing_documents"
down_revision: str | Sequence[str] | None = "0029_career_goals"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "writing_documents",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("title", sa.String(length=120), nullable=False),
        sa.Column("document_type", sa.String(length=24), nullable=False),
        sa.Column("content", sa.JSON(), nullable=False),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint("version >= 1", name=op.f("ck_writing_documents_version")),
        sa.CheckConstraint(
            "document_type IN ('cover_letter','portfolio')",
            name=op.f("ck_writing_documents_document_type"),
        ),
        sa.ForeignKeyConstraint(
            ["owner_id"],
            ["users.id"],
            name=op.f("fk_writing_documents_owner_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_writing_documents")),
    )
    op.create_index(
        op.f("ix_writing_documents_owner_id"), "writing_documents", ["owner_id"], unique=False
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_writing_documents_owner_id"), table_name="writing_documents")
    op.drop_table("writing_documents")
