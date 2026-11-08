"""School-scoped course categories, subcategories and study tracks.

Courses and curriculum links may reference them; references cannot cross schools.

Revision ID: 0015_school_classifications
Revises: 0014_school_admin_signups
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0015_school_classifications"
down_revision: str | Sequence[str] | None = "0014_school_admin_signups"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
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
    op.add_column("courses", sa.Column("classification_id", sa.Uuid(), nullable=True))
    op.add_column("courses", sa.Column("track_id", sa.Uuid(), nullable=True))
    op.create_index(
        op.f("ix_courses_classification_id"), "courses", ["classification_id"], unique=False
    )
    op.create_index(op.f("ix_courses_track_id"), "courses", ["track_id"], unique=False)
    op.create_foreign_key(
        op.f("fk_courses_classification_id_school_classifications"),
        "courses",
        "school_classifications",
        ["classification_id", "institution_id"],
        ["id", "institution_id"],
    )
    op.create_foreign_key(
        op.f("fk_courses_track_id_school_classifications"),
        "courses",
        "school_classifications",
        ["track_id", "institution_id"],
        ["id", "institution_id"],
    )
    op.add_column("curriculum_courses", sa.Column("classification_id", sa.Uuid(), nullable=True))
    op.add_column("curriculum_courses", sa.Column("track_id", sa.Uuid(), nullable=True))
    op.create_index(
        op.f("ix_curriculum_courses_classification_id"),
        "curriculum_courses",
        ["classification_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_curriculum_courses_track_id"), "curriculum_courses", ["track_id"], unique=False
    )
    op.create_foreign_key(
        op.f("fk_curriculum_courses_track_id_school_classifications"),
        "curriculum_courses",
        "school_classifications",
        ["track_id", "institution_id"],
        ["id", "institution_id"],
    )
    op.create_foreign_key(
        op.f("fk_curriculum_courses_classification_id_school_classifications"),
        "curriculum_courses",
        "school_classifications",
        ["classification_id", "institution_id"],
        ["id", "institution_id"],
    )


def downgrade() -> None:
    op.drop_constraint(
        op.f("fk_curriculum_courses_classification_id_school_classifications"),
        "curriculum_courses",
        type_="foreignkey",
    )
    op.drop_constraint(
        op.f("fk_curriculum_courses_track_id_school_classifications"),
        "curriculum_courses",
        type_="foreignkey",
    )
    op.drop_index(op.f("ix_curriculum_courses_track_id"), table_name="curriculum_courses")
    op.drop_index(op.f("ix_curriculum_courses_classification_id"), table_name="curriculum_courses")
    op.drop_column("curriculum_courses", "track_id")
    op.drop_column("curriculum_courses", "classification_id")
    op.drop_constraint(
        op.f("fk_courses_track_id_school_classifications"), "courses", type_="foreignkey"
    )
    op.drop_constraint(
        op.f("fk_courses_classification_id_school_classifications"), "courses", type_="foreignkey"
    )
    op.drop_index(op.f("ix_courses_track_id"), table_name="courses")
    op.drop_index(op.f("ix_courses_classification_id"), table_name="courses")
    op.drop_column("courses", "track_id")
    op.drop_column("courses", "classification_id")
    op.drop_index(op.f("ix_school_classifications_parent_id"), table_name="school_classifications")
    op.drop_index(
        op.f("ix_school_classifications_institution_id"), table_name="school_classifications"
    )
    op.drop_table("school_classifications")
