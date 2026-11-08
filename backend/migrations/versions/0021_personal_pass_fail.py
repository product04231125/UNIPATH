"""Preserve P/F grading and unconfirmed credits in student records."""

import sqlalchemy as sa
from alembic import op

revision = "0021_personal_pass_fail"
down_revision = "0020_pass_fail_courses"
branch_labels = None
depends_on = None
table = "personal_course_records"


def upgrade():
    op.add_column(
        table,
        sa.Column("grading_basis", sa.String(16), nullable=False, server_default="unspecified"),
    )
    op.alter_column(table, "credits", existing_type=sa.Numeric(8, 3), nullable=True)
    op.drop_constraint(op.f("ck_personal_course_records_credits"), table, type_="check")
    op.create_check_constraint(
        op.f("ck_personal_course_records_credits"),
        table,
        "(credits >= 0 AND credits <= 100) AND (credits > 0 OR grading_basis = 'pass_fail')",
    )
    op.create_check_constraint(
        op.f("ck_personal_course_records_known_credits"),
        table,
        "credits IS NOT NULL OR grading_basis = 'pass_fail'",
    )
    op.create_check_constraint(
        op.f("ck_personal_course_records_grading_basis"),
        table,
        "grading_basis IN ('unspecified','graded','pass_fail')",
    )


def downgrade():
    if (
        op.get_bind()
        .execute(
            sa.text(
                "SELECT EXISTS(SELECT 1 FROM personal_course_records "
                "WHERE credits IS NULL OR credits = 0 OR grading_basis <> 'unspecified')"
            )
        )
        .scalar()
    ):
        raise RuntimeError("Cannot downgrade: student P/F records would lose data")
    for name in ["credits", "known_credits", "grading_basis"]:
        op.drop_constraint(op.f(f"ck_personal_course_records_{name}"), table, type_="check")
    op.create_check_constraint(
        op.f("ck_personal_course_records_credits"), table, "credits > 0 AND credits <= 100"
    )
    op.alter_column(table, "credits", existing_type=sa.Numeric(8, 3), nullable=False)
    op.drop_column(table, "grading_basis")
