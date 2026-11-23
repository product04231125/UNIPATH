"""Store the job each student is preparing for (Work24 occupation codes and detail words).

Revision ID: 0029_career_goals
Revises: 0028_drop_course_placements
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0029_career_goals"
down_revision: str | Sequence[str] | None = "0028_drop_course_placements"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "career_goals",
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("category_codes", sa.JSON(), nullable=False),
        sa.Column("keyword", sa.String(length=80), nullable=False),
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
        sa.CheckConstraint("version >= 1", name=op.f("ck_career_goals_version")),
        sa.ForeignKeyConstraint(
            ["owner_id"],
            ["users.id"],
            name=op.f("fk_career_goals_owner_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("owner_id", name=op.f("pk_career_goals")),
    )


def downgrade() -> None:
    op.drop_table("career_goals")
