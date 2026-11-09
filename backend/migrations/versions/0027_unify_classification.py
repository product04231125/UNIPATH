"""Keep one classification and one course record link: the academic workspace's.

Drops the school_classifications table with the course and curriculum-link references to
it (0015) and the course record catalog provenance columns (0017). Classification
revisions, study tracks and student_academic_course_links replace them. Course
department ownership and course placement receipts from 0017 stay.

The upgrade refuses to run while any of the dropped tables or columns hold data, so no
environment loses records without someone deciding what to do with them first.

Revision ID: 0027_unify_classification
Revises: 0026_credit_record_bindings
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0027_unify_classification"
down_revision: str | Sequence[str] | None = "0026_credit_record_bindings"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

IN_USE = {
    "school_classifications": "SELECT count(*) FROM school_classifications",
    "courses.classification_id/track_id": (
        "SELECT count(*) FROM courses WHERE classification_id IS NOT NULL OR track_id IS NOT NULL"
    ),
    "curriculum_courses.classification_id/track_id": (
        "SELECT count(*) FROM curriculum_courses "
        "WHERE classification_id IS NOT NULL OR track_id IS NOT NULL"
    ),
    "personal_course_records.catalog_course_id/curriculum_course_id": (
        "SELECT count(*) FROM personal_course_records "
        "WHERE catalog_course_id IS NOT NULL OR curriculum_course_id IS NOT NULL"
    ),
}


def upgrade() -> None:
    connection = op.get_bind()
    in_use = {
        name: count
        for name, query in IN_USE.items()
        if (count := connection.execute(sa.text(query)).scalar_one())
    }
    if in_use:
        detail = ", ".join(f"{name}={count}" for name, count in in_use.items())
        raise RuntimeError(
            f"0027 stopped before dropping data that is still in use: {detail}. "
            "Move it to classification revisions or student academic course links, "
            "or clear it deliberately, then run the migration again."
        )

    # Course record catalog provenance (from 0017).
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

    # School classifications and the references to them (from 0015).
    for table in ("curriculum_courses", "courses"):
        for column in ("classification_id", "track_id"):
            op.drop_constraint(
                op.f(f"fk_{table}_{column}_school_classifications"), table, type_="foreignkey"
            )
            op.drop_index(op.f(f"ix_{table}_{column}"), table_name=table)
            op.drop_column(table, column)
    op.drop_index(op.f("ix_school_classifications_parent_id"), table_name="school_classifications")
    op.drop_index(
        op.f("ix_school_classifications_institution_id"), table_name="school_classifications"
    )
    op.drop_table("school_classifications")


def downgrade() -> None:
    # Recreates the empty structures; dropped data is not restored.
    op.create_table(
        "school_classifications",
        sa.Column("kind", sa.String(length=16), nullable=False),
        sa.Column("parent_id", sa.Uuid(), nullable=True),
        sa.Column("description", sa.String(length=1000), nullable=False),
        sa.Column("official_code", sa.String(length=64), nullable=True),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("institution_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=128), nullable=False),
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
        sa.CheckConstraint(
            "(kind = 'subcategory') = (parent_id IS NOT NULL)",
            name=op.f("ck_school_classifications_subcategory_parent"),
        ),
        sa.CheckConstraint(
            "kind IN ('category', 'subcategory', 'track')",
            name=op.f("ck_school_classifications_kind"),
        ),
        sa.CheckConstraint(
            "status IN ('active', 'inactive')", name=op.f("ck_school_classifications_status")
        ),
        sa.ForeignKeyConstraint(
            ["created_by"], ["users.id"], name=op.f("fk_school_classifications_created_by_users")
        ),
        sa.ForeignKeyConstraint(
            ["institution_id"],
            ["institutions.id"],
            name=op.f("fk_school_classifications_institution_id_institutions"),
        ),
        sa.ForeignKeyConstraint(
            ["parent_id", "institution_id"],
            ["school_classifications.id", "school_classifications.institution_id"],
            name=op.f("fk_school_classifications_parent_id_school_classifications"),
        ),
        sa.ForeignKeyConstraint(
            ["updated_by"], ["users.id"], name=op.f("fk_school_classifications_updated_by_users")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_school_classifications")),
        sa.UniqueConstraint("id", "institution_id", name=op.f("uq_school_classifications_id")),
    )
    op.create_index(
        op.f("ix_school_classifications_institution_id"),
        "school_classifications",
        ["institution_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_school_classifications_parent_id"),
        "school_classifications",
        ["parent_id"],
        unique=False,
    )
    for table in ("courses", "curriculum_courses"):
        for column in ("classification_id", "track_id"):
            op.add_column(table, sa.Column(column, sa.Uuid(), nullable=True))
            op.create_index(op.f(f"ix_{table}_{column}"), table, [column], unique=False)
            op.create_foreign_key(
                op.f(f"fk_{table}_{column}_school_classifications"),
                table,
                "school_classifications",
                [column, "institution_id"],
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
    op.create_check_constraint(
        op.f("ck_personal_course_records_catalog_source"),
        "personal_course_records",
        "(catalog_course_id IS NULL) = (catalog_course_version IS NULL) AND "
        "(curriculum_course_id IS NULL) = (curriculum_course_version IS NULL) AND "
        "(curriculum_course_id IS NULL OR catalog_course_id IS NOT NULL)",
    )
