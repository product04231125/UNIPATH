"""When a personal event (study goal, exam step, plan) was checked off; null while open.

Revision ID: 0032_event_completion
Revises: 0031_materials_results
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0032_event_completion"
down_revision: str | Sequence[str] | None = "0031_materials_results"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "personal_events", sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True)
    )


def downgrade() -> None:
    op.drop_column("personal_events", "completed_at")
