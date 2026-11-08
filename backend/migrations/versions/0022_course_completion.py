"""Use student course status for earned credits, preserving recorded completions."""

import sqlalchemy as sa
from alembic import op

revision = "0022_course_completion"
down_revision = "0021_personal_pass_fail"
branch_labels = None
depends_on = None


def upgrade():
    op.drop_constraint(
        op.f("ck_personal_course_records_completion"), "personal_course_records", type_="check"
    )
    op.create_check_constraint(
        op.f("ck_personal_course_records_completion"),
        "personal_course_records",
        "completion IN ('planned','in_progress','recorded','not_completed')",
    )


def downgrade():
    if (
        op.get_bind()
        .execute(
            sa.text(
                "SELECT EXISTS(SELECT 1 FROM personal_course_records "
                "WHERE completion='not_completed')"
            )
        )
        .scalar()
    ):
        raise RuntimeError("Cannot downgrade: not-completed course states would be lost")
    op.drop_constraint(
        op.f("ck_personal_course_records_completion"), "personal_course_records", type_="check"
    )
    op.create_check_constraint(
        op.f("ck_personal_course_records_completion"),
        "personal_course_records",
        "completion IN ('planned','in_progress','recorded')",
    )
