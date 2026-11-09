"""Connect transcript categories without modifying published requirement snapshots."""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0026_credit_record_bindings"
down_revision = "0025_course_completion"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "academic_credit_record_bindings",
        sa.Column("requirement_revision_id", sa.Uuid(), nullable=False),
        sa.Column("institution_id", sa.Uuid(), nullable=False),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("bindings_json", postgresql.JSONB(), nullable=False),
        sa.Column("updated_by", sa.Uuid(), nullable=False),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.PrimaryKeyConstraint("requirement_revision_id"),
        sa.ForeignKeyConstraint(["institution_id"], ["institutions.id"]),
        sa.ForeignKeyConstraint(["updated_by"], ["users.id"]),
        sa.ForeignKeyConstraint(
            ["requirement_revision_id", "institution_id"],
            ["academic_requirement_revisions.id", "academic_requirement_revisions.institution_id"],
        ),
        sa.CheckConstraint("version >= 1", name=op.f("ck_academic_credit_record_bindings_version")),
        sa.CheckConstraint(
            "jsonb_typeof(bindings_json) = 'object'",
            name=op.f("ck_academic_credit_record_bindings_bindings"),
        ),
    )


def downgrade():
    if (
        op.get_bind()
        .execute(sa.text("SELECT EXISTS(SELECT 1 FROM academic_credit_record_bindings)"))
        .scalar()
    ):
        raise RuntimeError("Cannot downgrade: transcript category bindings would be lost")
    op.drop_table("academic_credit_record_bindings")
