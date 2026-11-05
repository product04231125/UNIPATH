"""Keep equivalent decision CHECK expressions stable across pg_dump/pg_restore.

Revision ID: 0013_admin_decision_roundtrip
Revises: 0012_school_admin_applications
"""

from alembic import op

revision = "0013_admin_decision_roundtrip"
down_revision = "0012_school_admin_applications"
branch_labels = None
depends_on = None


def _replace(rejected_or_cancelled):
    name = op.f("ck_school_admin_applications_decision")
    op.drop_constraint(name, "school_admin_applications", type_="check")
    op.create_check_constraint(
        name,
        "school_admin_applications",
        "(status = 'pending' AND reviewed_at IS NULL AND reviewed_by IS NULL "
        "AND granted_scope_id IS NULL AND NOT identity_verified AND NOT affiliation_verified) OR "
        f"({rejected_or_cancelled} AND reviewed_at IS NOT NULL "
        "AND reviewed_by IS NOT NULL AND granted_scope_id IS NULL "
        "AND NOT identity_verified AND NOT affiliation_verified) OR "
        "(status = 'approved' AND reviewed_at IS NOT NULL AND reviewed_by IS NOT NULL "
        "AND granted_scope_id IS NOT NULL AND identity_verified AND affiliation_verified)",
    )


def upgrade():
    # Compound IN(varchar literals) changes its cast placement during restore.
    # Explicit OR has identical allowed states and keeps strict backup comparison.
    _replace("(status = 'rejected' OR status = 'cancelled')")


def downgrade():
    _replace("status IN ('rejected','cancelled')")
