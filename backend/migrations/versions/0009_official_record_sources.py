"""Private school-issued source files and append-only manual review events."""

from alembic import op

revision = "0009_official_record_sources"
down_revision = "0008_personal_imports"
branch_labels = None
depends_on = None


def upgrade():
    op.execute("""
        CREATE TABLE official_record_sources (
        id UUID NOT NULL,
        owner_id UUID NOT NULL,
        client_id UUID NOT NULL,
        institution_id UUID NOT NULL,
        department_id UUID,
        curriculum_id UUID,
        document_kind VARCHAR(24) NOT NULL,
        issued_on DATE NOT NULL,
        filename VARCHAR(128) NOT NULL,
        sha256 VARCHAR(64) NOT NULL,
        byte_count INTEGER NOT NULL,
        file_data BYTEA NOT NULL,
        status VARCHAR(16) NOT NULL,
        version INTEGER NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        CONSTRAINT pk_official_record_sources PRIMARY KEY (id),
        CONSTRAINT uq_official_record_sources_owner_id UNIQUE (owner_id, client_id),
        CONSTRAINT ck_official_record_sources_version CHECK (version >= 1),
        CONSTRAINT ck_official_record_sources_sha256 CHECK (sha256 ~ '^[0-9a-f]{64}$'),
        CONSTRAINT ck_official_record_sources_file_size CHECK (byte_count >= 1 AND
        byte_count <= 2097152 AND octet_length(file_data) = byte_count),
        CONSTRAINT ck_official_record_sources_status CHECK (status IN
        ('submitted','verified','rejected','revoked','withdrawn')),
        CONSTRAINT ck_official_record_sources_document_kind CHECK (document_kind IN
        ('transcript','volunteer','certificate','thesis','other')),
        CONSTRAINT ck_official_record_sources_hierarchy CHECK (curriculum_id IS NULL OR
        department_id IS NOT NULL),
        CONSTRAINT fk_official_record_sources_department_id_departments FOREIGN
        KEY(department_id, institution_id) REFERENCES departments (id, institution_id),
        CONSTRAINT fk_official_record_sources_curriculum_id_curricula FOREIGN KEY(curriculum_id,
        department_id, institution_id) REFERENCES curricula (id, department_id, institution_id),
        CONSTRAINT fk_official_record_sources_owner_id_users FOREIGN KEY(owner_id) REFERENCES
        users (id),
        CONSTRAINT fk_official_record_sources_institution_id_institutions FOREIGN
        KEY(institution_id) REFERENCES institutions (id)
        )
    """)
    op.execute("""
        CREATE INDEX ix_official_record_sources_institution_id ON official_record_sources
        (institution_id)
    """)
    op.execute("""
        CREATE INDEX ix_official_record_sources_owner_id ON official_record_sources (owner_id)
    """)
    op.execute("""
        CREATE TABLE official_record_source_events (
        id UUID NOT NULL,
        source_id UUID NOT NULL,
        actor_id UUID,
        version INTEGER NOT NULL,
        action VARCHAR(16) NOT NULL,
        reason VARCHAR(500) NOT NULL,
        occurred_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        CONSTRAINT pk_official_record_source_events PRIMARY KEY (id),
        CONSTRAINT uq_official_record_source_events_source_id UNIQUE (source_id, version),
        CONSTRAINT ck_official_record_source_events_version CHECK (version >= 1),
        CONSTRAINT ck_official_record_source_events_action CHECK (action IN
        ('submitted','verified','rejected','revoked','withdrawn')),
        CONSTRAINT fk_official_record_source_events_source_id_official_rec_e316 FOREIGN
        KEY(source_id) REFERENCES official_record_sources (id),
        CONSTRAINT fk_official_record_source_events_actor_id_users FOREIGN KEY(actor_id)
        REFERENCES users (id) ON DELETE SET NULL
        )
    """)
    op.execute("""
        CREATE INDEX ix_official_record_source_events_source_id ON official_record_source_events
        (source_id)
    """)


def downgrade():
    op.drop_table("official_record_source_events")
    op.drop_table("official_record_sources")
