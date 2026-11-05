"""Atomic personal workspace import receipts; existing records remain unchanged."""

from alembic import op

revision = "0008_personal_imports"
down_revision = "0007_official_rule_programs"
branch_labels = None
depends_on = None


def upgrade():
    op.execute("""
        CREATE TABLE personal_import_receipts ( owner_id UUID NOT NULL, import_id UUID NOT NULL,
        digest VARCHAR(64) NOT NULL, record_count INTEGER NOT NULL, profile_version INTEGER,
        mappings_json JSONB NOT NULL, committed_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT
        NULL, CONSTRAINT pk_personal_import_receipts PRIMARY KEY (owner_id, import_id), CONSTRAINT
        ck_personal_import_receipts_digest CHECK (digest ~ '^[0-9a-f]{64}$'), CONSTRAINT
        ck_personal_import_receipts_count CHECK (record_count >= 0 AND record_count <= 500),
        CONSTRAINT ck_personal_import_receipts_profile_version CHECK (profile_version IS NULL OR
        profile_version >= 1), CONSTRAINT ck_personal_import_receipts_nonempty CHECK (record_count
        > 0 OR profile_version IS NOT NULL), CONSTRAINT ck_personal_import_receipts_mappings CHECK
        (jsonb_typeof(mappings_json) = 'array' AND jsonb_array_length(mappings_json) =
        record_count), CONSTRAINT fk_personal_import_receipts_owner_id_users FOREIGN KEY(owner_id)
        REFERENCES users (id) )
    """)


def downgrade():
    op.drop_table("personal_import_receipts")
