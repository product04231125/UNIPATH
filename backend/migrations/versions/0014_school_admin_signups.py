"""Atomic initial accounts and unregistered school request receipts.

Revision ID: 0014_school_admin_signups
Revises: 0013_admin_decision_roundtrip
"""

from alembic import op

revision = "0014_school_admin_signups"
down_revision = "0013_admin_decision_roundtrip"
branch_labels = None
depends_on = None


def upgrade():
    op.execute("""

CREATE TABLE school_admin_signups (
        id UUID NOT NULL,
        applicant_id UUID NOT NULL,
        institution_id UUID,
        school_name VARCHAR(128) NOT NULL,
        school_key VARCHAR(384) NOT NULL,
        official_url VARCHAR(2048) NOT NULL,
        client_id UUID NOT NULL,
        payload_hash VARCHAR(64) NOT NULL,
        position VARCHAR(128) NOT NULL,
        contact_email VARCHAR(254) NOT NULL,
        reason VARCHAR(1000) NOT NULL,
        status VARCHAR(16) NOT NULL,
        version INTEGER NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        reviewed_by UUID,
        reviewed_at TIMESTAMP WITH TIME ZONE,
        review_note VARCHAR(500) NOT NULL,
        identity_verified BOOLEAN NOT NULL,
        affiliation_verified BOOLEAN NOT NULL,
        granted_scope_id UUID,
        CONSTRAINT pk_school_admin_signups PRIMARY KEY (id),
        CONSTRAINT ck_school_admin_signups_status CHECK (status IN
('pending','approved','rejected','cancelled')),
        CONSTRAINT ck_school_admin_signups_version CHECK (version >= 1),
        CONSTRAINT ck_school_admin_signups_decision CHECK ((status = 'pending' AND reviewed_at
IS NULL AND reviewed_by IS NULL AND granted_scope_id IS NULL AND NOT identity_verified AND NOT
affiliation_verified) OR ((status = 'rejected' OR status = 'cancelled') AND reviewed_at IS NOT
NULL AND reviewed_by IS NOT NULL AND granted_scope_id IS NULL AND NOT identity_verified AND NOT
affiliation_verified) OR (status = 'approved' AND reviewed_at IS NOT NULL AND reviewed_by IS NOT
NULL AND granted_scope_id IS NOT NULL AND institution_id IS NOT NULL AND identity_verified AND
affiliation_verified)),
        CONSTRAINT fk_school_admin_signups_applicant_id_users FOREIGN KEY(applicant_id)
REFERENCES users (id) ON DELETE CASCADE,
        CONSTRAINT fk_school_admin_signups_institution_id_institutions FOREIGN
KEY(institution_id) REFERENCES institutions (id),
        CONSTRAINT fk_school_admin_signups_reviewed_by_users FOREIGN KEY(reviewed_by) REFERENCES
users (id),
        CONSTRAINT fk_school_admin_signups_granted_scope_id_admin_scopes FOREIGN
KEY(granted_scope_id) REFERENCES admin_scopes (id)
)

;
CREATE INDEX ix_school_admin_signups_applicant_id ON school_admin_signups (applicant_id);
CREATE INDEX ix_school_admin_signups_institution_id ON school_admin_signups (institution_id);
CREATE UNIQUE INDEX uq_school_admin_signups_client ON school_admin_signups (applicant_id,
client_id);
CREATE UNIQUE INDEX uq_school_admin_signups_pending ON school_admin_signups (applicant_id,
school_key) WHERE status = 'pending';
""")


def downgrade():
    op.drop_table("school_admin_signups")
