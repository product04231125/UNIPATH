"""Place courses into curricula through curriculum revisions only.

Drops course_placement_receipts (0017), the replay receipts of POST /admin/course-placements.
A receipt only lets a lost response be replayed; the courses and curriculum links it created
stay. Course department ownership from 0017 stays.

Revision ID: 0028_drop_course_placements
Revises: 0027_unify_classification
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0028_drop_course_placements"
down_revision: str | Sequence[str] | None = "0027_unify_classification"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_table("course_placement_receipts")


def downgrade() -> None:
    # Recreates the empty table; dropped receipts are not restored.
    op.create_table(
        "course_placement_receipts",
        sa.Column("actor_id", sa.Uuid(), nullable=False),
        sa.Column("client_id", sa.Uuid(), nullable=False),
        sa.Column("institution_id", sa.Uuid(), nullable=False),
        sa.Column("digest", sa.String(length=64), nullable=False),
        sa.Column("course_id", sa.Uuid(), nullable=True),
        sa.Column("curriculum_course_id", sa.Uuid(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["actor_id"], ["users.id"], name=op.f("fk_course_placement_receipts_actor_id_users")
        ),
        sa.ForeignKeyConstraint(
            ["course_id"],
            ["courses.id"],
            name=op.f("fk_course_placement_receipts_course_id_courses"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["curriculum_course_id"],
            ["curriculum_courses.id"],
            name=op.f("fk_course_placement_receipts_curriculum_course_id_curriculum_courses"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["institution_id"],
            ["institutions.id"],
            name=op.f("fk_course_placement_receipts_institution_id_institutions"),
        ),
        sa.PrimaryKeyConstraint("actor_id", "client_id", name=op.f("pk_course_placement_receipts")),
    )
