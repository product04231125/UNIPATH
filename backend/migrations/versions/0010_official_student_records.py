"""Private normalized school records and immutable review/master provenance."""

from alembic import op

revision = "0010_official_student_records"
down_revision = "0009_official_record_sources"
branch_labels = None
depends_on = None


def upgrade():
    op.execute("""
        ALTER TABLE official_record_sources ADD CONSTRAINT
        uq_official_record_sources_owner_scope UNIQUE (id,owner_id,institution_id)
    """)
    op.execute("""
        CREATE TABLE official_record_batches (
        id UUID NOT NULL,
        source_id UUID NOT NULL,
        owner_id UUID NOT NULL,
        institution_id UUID NOT NULL,
        source_version INTEGER NOT NULL,
        source_sha256 VARCHAR(64) NOT NULL,
        client_id UUID NOT NULL,
        creation_digest VARCHAR(64) NOT NULL,
        data_digest VARCHAR(64) NOT NULL,
        kind VARCHAR(16) NOT NULL,
        status VARCHAR(16) NOT NULL,
        version INTEGER NOT NULL,
        department_id UUID,
        curriculum_id UUID,
        admission_year INTEGER,
        track VARCHAR(64),
        coverage VARCHAR(16) NOT NULL,
        page_count INTEGER NOT NULL,
        records_as_of DATE NOT NULL,
        record_count INTEGER NOT NULL,
        data_json JSONB NOT NULL,
        created_by UUID,
        approved_by UUID,
        approved_at TIMESTAMP WITH TIME ZONE,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        CONSTRAINT pk_official_record_batches PRIMARY KEY (id),
        CONSTRAINT uq_official_record_batches_owner_id UNIQUE (owner_id, client_id),
        CONSTRAINT uq_official_record_batches_id UNIQUE (id, institution_id),
        CONSTRAINT fk_official_record_batches_source_id_official_record_sources FOREIGN
        KEY(source_id, owner_id, institution_id) REFERENCES official_record_sources (id,
        owner_id, institution_id),
        CONSTRAINT fk_official_record_batches_department_id_departments FOREIGN
        KEY(department_id, institution_id) REFERENCES departments (id, institution_id),
        CONSTRAINT fk_official_record_batches_curriculum_id_curricula FOREIGN KEY(curriculum_id,
        department_id, institution_id) REFERENCES curricula (id, department_id, institution_id),
        CONSTRAINT ck_official_record_batches_versions CHECK (version >= 1 AND source_version >=
        1),
        CONSTRAINT ck_official_record_batches_digests CHECK (source_sha256 ~ '^[0-9a-f]{64}$'
        AND creation_digest ~ '^[0-9a-f]{64}$' AND data_digest ~ '^[0-9a-f]{64}$'),
        CONSTRAINT ck_official_record_batches_kind CHECK (kind IN
        ('academics','volunteers','certificates','theses')),
        CONSTRAINT ck_official_record_batches_status CHECK (status IN
        ('draft','approved','revoked','superseded','discarded')),
        CONSTRAINT ck_official_record_batches_coverage CHECK (coverage IN
        ('complete','partial')),
        CONSTRAINT ck_official_record_batches_record_limits CHECK (page_count >= 1 AND
        page_count <= 500 AND record_count >= 0 AND record_count <= 500),
        CONSTRAINT ck_official_record_batches_hierarchy CHECK (curriculum_id IS NULL OR
        department_id IS NOT NULL),
        CONSTRAINT ck_official_record_batches_admission_year CHECK (admission_year IS NULL OR
        admission_year >= 1000 AND admission_year <= 9999),
        CONSTRAINT ck_official_record_batches_approval_context CHECK (status <> 'approved' OR
        approved_at IS NOT NULL AND department_id IS NOT NULL AND admission_year IS NOT NULL AND
        track IS NOT NULL),
        CONSTRAINT ck_official_record_batches_payload_shape CHECK (jsonb_typeof(data_json) =
        'object' AND data_json ? 'records' AND data_json ? 'kind' AND
        jsonb_typeof(data_json->'records') = 'array' AND
        jsonb_array_length(data_json->'records') = record_count AND data_json->>'kind' = kind),
        CONSTRAINT fk_official_record_batches_owner_id_users FOREIGN KEY(owner_id) REFERENCES
        users (id),
        CONSTRAINT fk_official_record_batches_institution_id_institutions FOREIGN
        KEY(institution_id) REFERENCES institutions (id),
        CONSTRAINT fk_official_record_batches_created_by_users FOREIGN KEY(created_by)
        REFERENCES users (id) ON DELETE SET NULL,
        CONSTRAINT fk_official_record_batches_approved_by_users FOREIGN KEY(approved_by)
        REFERENCES users (id) ON DELETE SET NULL
        )
    """)
    op.execute("""
        CREATE INDEX ix_official_record_batches_institution_id ON official_record_batches
        (institution_id)
    """)
    op.execute("""
        CREATE INDEX ix_official_record_batches_owner_id ON official_record_batches (owner_id)
    """)
    op.execute("""
        CREATE INDEX ix_official_record_batches_source_id ON official_record_batches (source_id)
    """)
    op.execute("""
        CREATE UNIQUE INDEX uq_official_record_batches_approved ON official_record_batches
        (owner_id, institution_id, department_id, curriculum_id, admission_year, track, kind)
        NULLS NOT DISTINCT WHERE status = 'approved'
    """)
    op.execute("""
        CREATE UNIQUE INDEX uq_official_record_batches_draft ON official_record_batches
        (source_id, kind) WHERE status = 'draft'
    """)
    op.execute("""
        CREATE TABLE official_record_batch_events (
        id UUID NOT NULL,
        batch_id UUID NOT NULL,
        actor_id UUID,
        version INTEGER NOT NULL,
        action VARCHAR(24) NOT NULL,
        reason VARCHAR(500) NOT NULL,
        occurred_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        CONSTRAINT pk_official_record_batch_events PRIMARY KEY (id),
        CONSTRAINT uq_official_record_batch_events_batch_id UNIQUE (batch_id, version),
        CONSTRAINT ck_official_record_batch_events_version CHECK (version >= 1),
        CONSTRAINT ck_official_record_batch_events_action CHECK (action IN
        ('created','replaced','approved','revoked','superseded','source_revoked','source_withdrawn','discarded')),
        CONSTRAINT fk_official_record_batch_events_batch_id_official_recor_72a1 FOREIGN
        KEY(batch_id) REFERENCES official_record_batches (id),
        CONSTRAINT fk_official_record_batch_events_actor_id_users FOREIGN KEY(actor_id)
        REFERENCES users (id) ON DELETE SET NULL
        )
    """)
    op.execute("""
        CREATE INDEX ix_official_record_batch_events_batch_id ON official_record_batch_events
        (batch_id)
    """)
    op.execute("""
        CREATE TABLE official_record_course_refs (
        batch_id UUID NOT NULL,
        course_id UUID NOT NULL,
        institution_id UUID NOT NULL,
        catalog_version INTEGER NOT NULL,
        code VARCHAR(64) NOT NULL,
        name VARCHAR(128) NOT NULL,
        CONSTRAINT pk_official_record_course_refs PRIMARY KEY (batch_id, course_id),
        CONSTRAINT fk_official_record_course_refs_batch_id_official_record_batches FOREIGN
        KEY(batch_id, institution_id) REFERENCES official_record_batches (id, institution_id),
        CONSTRAINT fk_official_record_course_refs_course_id_courses FOREIGN KEY(course_id,
        institution_id) REFERENCES courses (id, institution_id),
        CONSTRAINT ck_official_record_course_refs_version CHECK (catalog_version >= 1)
        )
    """)
    op.execute("""
        CREATE INDEX ix_official_record_course_refs_course_id ON official_record_course_refs
        (course_id)
    """)
    op.execute("""
        CREATE TABLE official_record_certificate_refs (
        batch_id UUID NOT NULL,
        certificate_id UUID NOT NULL,
        institution_id UUID NOT NULL,
        catalog_version INTEGER NOT NULL,
        code VARCHAR(64) NOT NULL,
        name VARCHAR(128) NOT NULL,
        provider_id UUID NOT NULL,
        provider_version INTEGER NOT NULL,
        provider_name VARCHAR(128) NOT NULL,
        CONSTRAINT pk_official_record_certificate_refs PRIMARY KEY (batch_id, certificate_id),
        CONSTRAINT fk_official_record_certificate_refs_batch_id_official_r_55ec FOREIGN
        KEY(batch_id, institution_id) REFERENCES official_record_batches (id, institution_id),
        CONSTRAINT ck_official_record_certificate_refs_versions CHECK (catalog_version >= 1 AND
        provider_version >= 1),
        CONSTRAINT fk_official_record_certificate_refs_certificate_id_certificates FOREIGN
        KEY(certificate_id) REFERENCES certificates (id),
        CONSTRAINT fk_official_record_certificate_refs_provider_id_certifi_94a7 FOREIGN
        KEY(provider_id) REFERENCES certificate_providers (id)
        )
    """)
    op.execute("""
        CREATE INDEX ix_official_record_certificate_refs_certificate_id ON
        official_record_certificate_refs (certificate_id)
    """)
    op.execute("""
        CREATE INDEX ix_official_record_certificate_refs_provider_id ON
        official_record_certificate_refs (provider_id)
    """)


def downgrade():
    op.drop_table("official_record_certificate_refs")
    op.drop_table("official_record_course_refs")
    op.drop_table("official_record_batch_events")
    op.drop_table("official_record_batches")
    op.drop_constraint(
        "uq_official_record_sources_owner_scope", "official_record_sources", type_="unique"
    )
