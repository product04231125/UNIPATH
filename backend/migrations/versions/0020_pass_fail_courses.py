"""Separate P/F evaluation from known, zero and unconfirmed credits."""

import sqlalchemy as sa
from alembic import op

revision = "0020_pass_fail_courses"
down_revision = "0019_optional_school_course_code"
branch_labels = None
depends_on = None


def upgrade():
    for table, amount in [
        ("courses", "credits"),
        ("academic_curriculum_courses", "recognized_credits"),
    ]:
        op.add_column(
            table,
            sa.Column("grading_basis", sa.String(16), nullable=False, server_default="unspecified"),
        )
        op.alter_column(table, amount, existing_type=sa.Numeric(8, 3), nullable=True)
        op.create_check_constraint(
            op.f(f"ck_{table}_grading_basis"),
            table,
            "grading_basis IN ('unspecified','graded','pass_fail')",
        )
        op.create_check_constraint(
            op.f(f"ck_{table}_known_credits"),
            table,
            f"{amount} IS NOT NULL OR grading_basis = 'pass_fail'",
        )


def downgrade():
    for table, amount in [
        ("courses", "credits"),
        ("academic_curriculum_courses", "recognized_credits"),
    ]:
        if (
            op.get_bind()
            .execute(
                sa.text(
                    f"SELECT EXISTS(SELECT 1 FROM {table} "
                    f"WHERE {amount} IS NULL OR grading_basis <> 'unspecified')"
                )
            )
            .scalar()
        ):
            raise RuntimeError("Cannot downgrade: P/F grading or unconfirmed credits would be lost")
    for table, amount in [
        ("courses", "credits"),
        ("academic_curriculum_courses", "recognized_credits"),
    ]:
        op.drop_constraint(op.f(f"ck_{table}_known_credits"), table, type_="check")
        op.drop_constraint(op.f(f"ck_{table}_grading_basis"), table, type_="check")
        op.alter_column(table, amount, existing_type=sa.Numeric(8, 3), nullable=False)
        op.drop_column(table, "grading_basis")
