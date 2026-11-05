"""Immutable owner-only personal evaluation snapshots and result history."""

from alembic import op

revision = "0005_personal_evaluations"
down_revision = "0004_personal_records"
branch_labels = None
depends_on = None


def upgrade():
    op.execute("""
        CREATE TABLE personal_evaluations ( id UUID NOT NULL, owner_id UUID NOT NULL, client_id
        UUID, version INTEGER NOT NULL, curriculum_id UUID NOT NULL, curriculum_version INTEGER
        NOT NULL, curriculum_title VARCHAR(128) NOT NULL, evaluated_on DATE NOT NULL, status
        VARCHAR(16) NOT NULL, reason VARCHAR(128) NOT NULL, result_json JSONB NOT NULL,
        criteria_json JSONB NOT NULL, course_aliases_json JSONB NOT NULL, source_versions_json
        JSONB NOT NULL, input_snapshot_json JSONB NOT NULL, created_at TIMESTAMP WITH TIME ZONE
        DEFAULT now() NOT NULL, CONSTRAINT pk_personal_evaluations PRIMARY KEY (id), CONSTRAINT
        uq_personal_evaluations_owner_id UNIQUE (owner_id, client_id), CONSTRAINT
        ck_personal_evaluations_immutable_version CHECK (version = 1 AND curriculum_version >= 1),
        CONSTRAINT ck_personal_evaluations_status CHECK (status IN
        ('satisfied','not_satisfied','needs_review','not_applicable')), CONSTRAINT
        ck_personal_evaluations_personal_only CHECK (jsonb_typeof(result_json) = 'object' AND
        coalesce(result_json->'official' = 'false'::jsonb, false)), CONSTRAINT
        ck_personal_evaluations_status_matches CHECK (coalesce(result_json->>'status' = status,
        false)), CONSTRAINT fk_personal_evaluations_owner_id_users FOREIGN KEY(owner_id)
        REFERENCES users (id) )
    """)
    op.execute("""
        CREATE INDEX ix_personal_evaluations_owner_created_id ON personal_evaluations (owner_id,
        created_at, id)
    """)


def downgrade():
    op.drop_table("personal_evaluations")
