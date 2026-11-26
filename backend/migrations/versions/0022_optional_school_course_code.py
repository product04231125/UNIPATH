"""Keep UUID identities; allow missing school-issued course numbers."""

import sqlalchemy as sa
from alembic import op

revision = "0022_optional_school_course_code"
down_revision = "0021_student_academic"
branch_labels = None
depends_on = None


def upgrade():
    op.drop_constraint("uq_courses_institution_id", "courses", type_="unique")
    op.alter_column("courses", "code", existing_type=sa.String(64), server_default="")
    op.create_index(
        "uq_courses_school_code",
        "courses",
        ["institution_id", "code"],
        unique=True,
        postgresql_where=sa.text("code <> ''"),
    )


def downgrade():
    if (
        op.get_bind()
        .execute(sa.text("SELECT EXISTS(SELECT 1 FROM courses WHERE code = '')"))
        .scalar()
    ):
        raise RuntimeError(
            "Cannot downgrade while courses without school numbers exist; "
            "preserve and resolve them first"
        )
    op.drop_index("uq_courses_school_code", table_name="courses")
    op.alter_column("courses", "code", existing_type=sa.String(64), server_default=None)
    op.create_unique_constraint("uq_courses_institution_id", "courses", ["institution_id", "code"])
