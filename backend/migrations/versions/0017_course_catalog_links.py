"""Course department, atomic course placement receipts and course record provenance.

Existing courses keep department_id NULL (shared across the school) and existing
course records keep no catalog provenance.

Revision ID: 0017_course_catalog_links
Revises: 0016_guidance_bindings
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0017_course_catalog_links"
down_revision: str | Sequence[str] | None = "0016_guidance_bindings"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
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
    op.add_column("courses", sa.Column("department_id", sa.Uuid(), nullable=True))
    op.create_index(op.f("ix_courses_department_id"), "courses", ["department_id"], unique=False)
    op.create_foreign_key(
        op.f("fk_courses_department_id_departments"),
        "courses",
        "departments",
        ["department_id", "institution_id"],
        ["id", "institution_id"],
    )
    op.create_unique_constraint(
        op.f("uq_curriculum_courses_id"), "curriculum_courses", ["id", "course_id"]
    )
    op.add_column(
        "personal_course_records", sa.Column("catalog_course_id", sa.Uuid(), nullable=True)
    )
    op.add_column(
        "personal_course_records", sa.Column("catalog_course_version", sa.Integer(), nullable=True)
    )
    op.add_column(
        "personal_course_records", sa.Column("curriculum_course_id", sa.Uuid(), nullable=True)
    )
    op.add_column(
        "personal_course_records",
        sa.Column("curriculum_course_version", sa.Integer(), nullable=True),
    )
    op.create_index(
        op.f("ix_personal_course_records_catalog_course_id"),
        "personal_course_records",
        ["catalog_course_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_personal_course_records_curriculum_course_id"),
        "personal_course_records",
        ["curriculum_course_id"],
        unique=False,
    )
    op.create_foreign_key(
        op.f("fk_personal_course_records_curriculum_course_id_curriculum_courses"),
        "personal_course_records",
        "curriculum_courses",
        ["curriculum_course_id", "catalog_course_id"],
        ["id", "course_id"],
    )
    op.create_foreign_key(
        op.f("fk_personal_course_records_catalog_course_id_courses"),
        "personal_course_records",
        "courses",
        ["catalog_course_id"],
        ["id"],
    )
    # Autogenerate does not detect CHECK constraints; keep this in step with the model.
    op.create_check_constraint(
        op.f("ck_personal_course_records_catalog_source"),
        "personal_course_records",
        "(catalog_course_id IS NULL) = (catalog_course_version IS NULL) AND "
        "(curriculum_course_id IS NULL) = (curriculum_course_version IS NULL) AND "
        "(curriculum_course_id IS NULL OR catalog_course_id IS NOT NULL)",
    )


def downgrade() -> None:
    op.drop_constraint(
        op.f("ck_personal_course_records_catalog_source"),
        "personal_course_records",
        type_="check",
    )
    op.drop_constraint(
        op.f("fk_personal_course_records_catalog_course_id_courses"),
        "personal_course_records",
        type_="foreignkey",
    )
    op.drop_constraint(
        op.f("fk_personal_course_records_curriculum_course_id_curriculum_courses"),
        "personal_course_records",
        type_="foreignkey",
    )
    op.drop_index(
        op.f("ix_personal_course_records_curriculum_course_id"),
        table_name="personal_course_records",
    )
    op.drop_index(
        op.f("ix_personal_course_records_catalog_course_id"), table_name="personal_course_records"
    )
    op.drop_column("personal_course_records", "curriculum_course_version")
    op.drop_column("personal_course_records", "curriculum_course_id")
    op.drop_column("personal_course_records", "catalog_course_version")
    op.drop_column("personal_course_records", "catalog_course_id")
    op.drop_constraint(op.f("uq_curriculum_courses_id"), "curriculum_courses", type_="unique")
    op.drop_constraint(op.f("fk_courses_department_id_departments"), "courses", type_="foreignkey")
    op.drop_index(op.f("ix_courses_department_id"), table_name="courses")
    op.drop_column("courses", "department_id")
    op.drop_table("course_placement_receipts")
