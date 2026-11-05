"""Reviewed catalogue completeness and immutable owner-only graduation audits."""

from alembic import op

revision = "0011_official_graduation_audits"
down_revision = "0010_official_student_records"
branch_labels = None
depends_on = None


def upgrade():
    op.execute("""
        CREATE TABLE graduation_catalog_reviews ( id UUID NOT NULL, client_id UUID NOT NULL,
        reviewed_by UUID, creation_digest VARCHAR(64) NOT NULL, snapshot_digest VARCHAR(64)
        NOT NULL, snapshot_json JSONB NOT NULL, review_note VARCHAR(500) NOT NULL, version
        INTEGER NOT NULL, status VARCHAR(16) NOT NULL, created_at TIMESTAMP WITH TIME ZONE
        DEFAULT now() NOT NULL, updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        institution_id UUID NOT NULL, department_id UUID NOT NULL, curriculum_id UUID NOT
        NULL, admission_year INTEGER NOT NULL, track VARCHAR(64) NOT NULL, as_of DATE NOT
        NULL, CONSTRAINT pk_graduation_catalog_reviews PRIMARY KEY (id), CONSTRAINT
        fk_graduation_catalog_reviews_department_id_departments FOREIGN KEY(department_id,
        institution_id) REFERENCES departments (id, institution_id), CONSTRAINT
        fk_graduation_catalog_reviews_curriculum_id_curricula FOREIGN KEY(curriculum_id,
        department_id, institution_id) REFERENCES curricula (id, department_id,
        institution_id), CONSTRAINT ck_graduation_catalog_reviews_cohort CHECK (admission_year
        >= 1000 AND admission_year <= 9999), CONSTRAINT
        uq_graduation_catalog_reviews_reviewed_by UNIQUE (reviewed_by, client_id), CONSTRAINT
        ck_graduation_catalog_reviews_version CHECK (version >= 1), CONSTRAINT
        ck_graduation_catalog_reviews_status CHECK (status IN
        ('approved','revoked','superseded')), CONSTRAINT ck_graduation_catalog_reviews_digests
        CHECK (creation_digest ~ '^[0-9a-f]{64}$' AND snapshot_digest ~ '^[0-9a-f]{64}$'),
        CONSTRAINT ck_graduation_catalog_reviews_snapshot_shape CHECK
        (jsonb_typeof(snapshot_json) = 'object'), CONSTRAINT
        ck_graduation_catalog_reviews_review_note CHECK (length(trim(review_note)) > 0),
        CONSTRAINT fk_graduation_catalog_reviews_reviewed_by_users FOREIGN KEY(reviewed_by)
        REFERENCES users (id) ON DELETE SET NULL, CONSTRAINT
        fk_graduation_catalog_reviews_institution_id_institutions FOREIGN KEY(institution_id)
        REFERENCES institutions (id) )
    """)
    op.execute("""
        CREATE INDEX ix_graduation_catalog_reviews_school_id ON graduation_catalog_reviews
        (institution_id, id)
    """)
    op.execute("""
        CREATE UNIQUE INDEX uq_graduation_catalog_review_active ON graduation_catalog_reviews
        (institution_id, department_id, curriculum_id, admission_year, track, as_of) WHERE
        status = 'approved'
    """)
    op.execute("""
        CREATE TABLE graduation_catalog_review_events ( id UUID NOT NULL, review_id UUID NOT
        NULL, actor_id UUID, version INTEGER NOT NULL, action VARCHAR(16) NOT NULL, reason
        VARCHAR(500) NOT NULL, occurred_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        CONSTRAINT pk_graduation_catalog_review_events PRIMARY KEY (id), CONSTRAINT
        uq_graduation_catalog_review_events_review_id UNIQUE (review_id, version), CONSTRAINT
        ck_graduation_catalog_review_events_version CHECK (version >= 1), CONSTRAINT
        ck_graduation_catalog_review_events_action CHECK (action IN
        ('approved','revoked','superseded')), CONSTRAINT
        fk_graduation_catalog_review_events_review_id_graduatio_915f FOREIGN KEY(review_id)
        REFERENCES graduation_catalog_reviews (id), CONSTRAINT
        fk_graduation_catalog_review_events_actor_id_users FOREIGN KEY(actor_id) REFERENCES
        users (id) ON DELETE SET NULL )
    """)
    op.execute("""
        CREATE INDEX ix_graduation_catalog_review_events_review_id ON
        graduation_catalog_review_events (review_id)
    """)
    op.execute("""
        CREATE TABLE graduation_audits ( id UUID NOT NULL, owner_id UUID NOT NULL, client_id
        UUID NOT NULL, version INTEGER NOT NULL, creation_digest VARCHAR(64) NOT NULL,
        payload_digest VARCHAR(64) NOT NULL, payload_bytes INTEGER NOT NULL, payload_json
        JSONB NOT NULL, status VARCHAR(16) NOT NULL, reason VARCHAR(128) NOT NULL,
        catalog_complete BOOLEAN NOT NULL, eligible_as_of BOOLEAN NOT NULL, catalog_review_id
        UUID, catalog_review_version INTEGER, created_at TIMESTAMP WITH TIME ZONE DEFAULT
        now() NOT NULL, institution_id UUID NOT NULL, department_id UUID NOT NULL,
        curriculum_id UUID NOT NULL, admission_year INTEGER NOT NULL, track VARCHAR(64) NOT
        NULL, as_of DATE NOT NULL, CONSTRAINT pk_graduation_audits PRIMARY KEY (id),
        CONSTRAINT fk_graduation_audits_department_id_departments FOREIGN KEY(department_id,
        institution_id) REFERENCES departments (id, institution_id), CONSTRAINT
        fk_graduation_audits_curriculum_id_curricula FOREIGN KEY(curriculum_id, department_id,
        institution_id) REFERENCES curricula (id, department_id, institution_id), CONSTRAINT
        ck_graduation_audits_cohort CHECK (admission_year >= 1000 AND admission_year <= 9999),
        CONSTRAINT uq_graduation_audits_owner_id UNIQUE (owner_id, client_id), CONSTRAINT
        ck_graduation_audits_immutable CHECK (version = 1), CONSTRAINT
        ck_graduation_audits_status CHECK (status IN
        ('satisfied','not_satisfied','needs_review','not_applicable')), CONSTRAINT
        ck_graduation_audits_digests CHECK (creation_digest ~ '^[0-9a-f]{64}$' AND
        payload_digest ~ '^[0-9a-f]{64}$'), CONSTRAINT ck_graduation_audits_payload_limit
        CHECK (payload_bytes >= 1 AND payload_bytes <= 4194304), CONSTRAINT
        ck_graduation_audits_eligibility CHECK (eligible_as_of = (status = 'satisfied' AND
        catalog_complete)), CONSTRAINT ck_graduation_audits_review_version CHECK
        ((catalog_review_id IS NULL AND catalog_review_version IS NULL) OR (catalog_review_id
        IS NOT NULL AND catalog_review_version IS NOT NULL AND catalog_review_version >= 1)),
        CONSTRAINT ck_graduation_audits_complete_review CHECK (NOT catalog_complete OR
        catalog_review_id IS NOT NULL), CONSTRAINT ck_graduation_audits_official_result CHECK
        (jsonb_typeof(payload_json) = 'object' AND
        coalesce(payload_json->'evaluation'->'official' = 'true'::jsonb, false) AND
        coalesce(payload_json->'evaluation'->>'status' = status, false)), CONSTRAINT
        fk_graduation_audits_owner_id_users FOREIGN KEY(owner_id) REFERENCES users (id),
        CONSTRAINT fk_graduation_audits_catalog_review_id_graduation_catal_20da FOREIGN
        KEY(catalog_review_id) REFERENCES graduation_catalog_reviews (id), CONSTRAINT
        fk_graduation_audits_institution_id_institutions FOREIGN KEY(institution_id)
        REFERENCES institutions (id) )
    """)
    op.execute("""
        CREATE INDEX ix_graduation_audits_owner_id ON graduation_audits (owner_id, id)
    """)


def downgrade():
    op.drop_table("graduation_audits")
    op.drop_table("graduation_catalog_review_events")
    op.drop_table("graduation_catalog_reviews")
