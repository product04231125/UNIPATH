"""Which collected academic guidance bundle each registered school shows.

No row means the school shows no collected guidance to its students.

Revision ID: 0016_guidance_bindings
Revises: 0015_school_classifications
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0016_guidance_bindings"
down_revision: str | Sequence[str] | None = "0015_school_classifications"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "academic_guidance_bindings",
        sa.Column("institution_id", sa.Uuid(), nullable=False),
        sa.Column("bundle_id", sa.String(length=64), nullable=False),
        sa.Column("edition", sa.String(length=64), nullable=False),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("created_by", sa.Uuid(), nullable=False),
        sa.Column("updated_by", sa.Uuid(), nullable=False),
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
        sa.CheckConstraint("version >= 1", name=op.f("ck_academic_guidance_bindings_version")),
        sa.ForeignKeyConstraint(
            ["created_by"],
            ["users.id"],
            name=op.f("fk_academic_guidance_bindings_created_by_users"),
        ),
        sa.ForeignKeyConstraint(
            ["institution_id"],
            ["institutions.id"],
            name=op.f("fk_academic_guidance_bindings_institution_id_institutions"),
        ),
        sa.ForeignKeyConstraint(
            ["updated_by"],
            ["users.id"],
            name=op.f("fk_academic_guidance_bindings_updated_by_users"),
        ),
        sa.PrimaryKeyConstraint("institution_id", name=op.f("pk_academic_guidance_bindings")),
    )


def downgrade() -> None:
    op.drop_table("academic_guidance_bindings")
