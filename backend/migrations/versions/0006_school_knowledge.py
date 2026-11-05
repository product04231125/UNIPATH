"""Scoped school knowledge extraction, explicit review and immutable publication."""

from alembic import op

revision = "0006_school_knowledge"
down_revision = "0005_personal_evaluations"
branch_labels = None
depends_on = None


def upgrade():
    op.execute("""
        ALTER TABLE official_documents ADD CONSTRAINT uq_official_documents_id UNIQUE (id,
        institution_id)
    """)
    op.execute("""
        CREATE TABLE school_knowledge_documents ( source_document_id UUID NOT NULL,
        source_document_version INTEGER NOT NULL, department_id UUID, curriculum_id UUID,
        document_hash VARCHAR(64) NOT NULL, page_count INTEGER NOT NULL, extractor_version
        VARCHAR(128) NOT NULL, source_checked_on DATE NOT NULL, status VARCHAR(16) NOT NULL,
        approved_by UUID, approved_at TIMESTAMP WITH TIME ZONE, review_note VARCHAR(500) NOT NULL,
        revoked_by UUID, revoked_at TIMESTAMP WITH TIME ZONE, revocation_reason VARCHAR(500) NOT
        NULL, id UUID NOT NULL, institution_id UUID NOT NULL, name VARCHAR(128) NOT NULL, version
        INTEGER NOT NULL, created_by UUID NOT NULL, updated_by UUID NOT NULL, created_at TIMESTAMP
        WITH TIME ZONE DEFAULT now() NOT NULL, updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
        NOT NULL, CONSTRAINT pk_school_knowledge_documents PRIMARY KEY (id), CONSTRAINT
        uq_school_knowledge_documents_id UNIQUE (id, institution_id), CONSTRAINT
        fk_school_knowledge_documents_source_document_id_offici_c885 FOREIGN
        KEY(source_document_id, institution_id) REFERENCES official_documents (id,
        institution_id), CONSTRAINT fk_school_knowledge_documents_department_id_departments
        FOREIGN KEY(department_id, institution_id) REFERENCES departments (id, institution_id),
        CONSTRAINT fk_school_knowledge_documents_curriculum_id_curricula FOREIGN
        KEY(curriculum_id, department_id, institution_id) REFERENCES curricula (id, department_id,
        institution_id), CONSTRAINT ck_school_knowledge_documents_versions CHECK (version >= 1 AND
        source_document_version >= 1), CONSTRAINT ck_school_knowledge_documents_page_count CHECK
        (page_count BETWEEN 1 AND 200), CONSTRAINT ck_school_knowledge_documents_document_hash
        CHECK (document_hash ~ '^[0-9a-f]{64}$'), CONSTRAINT ck_school_knowledge_documents_scope
        CHECK (curriculum_id IS NULL OR department_id IS NOT NULL), CONSTRAINT
        ck_school_knowledge_documents_status CHECK (status IN ('draft','approved','revoked')),
        CONSTRAINT ck_school_knowledge_documents_approval CHECK ((status = 'draft' AND approved_by
        IS NULL AND approved_at IS NULL) OR (status <> 'draft' AND approved_by IS NOT NULL AND
        approved_at IS NOT NULL AND length(trim(review_note)) > 0)), CONSTRAINT
        ck_school_knowledge_documents_revocation CHECK ((status <> 'revoked' AND revoked_by IS
        NULL AND revoked_at IS NULL) OR (status = 'revoked' AND revoked_by IS NOT NULL AND
        revoked_at IS NOT NULL AND length(trim(revocation_reason)) > 0)), CONSTRAINT
        uq_school_knowledge_documents_source_document_id UNIQUE (source_document_id), CONSTRAINT
        fk_school_knowledge_documents_approved_by_users FOREIGN KEY(approved_by) REFERENCES users
        (id), CONSTRAINT fk_school_knowledge_documents_revoked_by_users FOREIGN KEY(revoked_by)
        REFERENCES users (id), CONSTRAINT
        fk_school_knowledge_documents_institution_id_institutions FOREIGN KEY(institution_id)
        REFERENCES institutions (id), CONSTRAINT fk_school_knowledge_documents_created_by_users
        FOREIGN KEY(created_by) REFERENCES users (id), CONSTRAINT
        fk_school_knowledge_documents_updated_by_users FOREIGN KEY(updated_by) REFERENCES users
        (id) )
    """)
    op.execute("""
        CREATE INDEX ix_school_knowledge_documents_institution_id ON school_knowledge_documents
        (institution_id)
    """)
    op.execute("""
        CREATE TABLE school_knowledge_chunks ( id UUID NOT NULL, knowledge_document_id UUID NOT
        NULL, institution_id UUID NOT NULL, page INTEGER NOT NULL, part_index INTEGER NOT NULL,
        part_count INTEGER NOT NULL, character_start INTEGER NOT NULL, character_end INTEGER NOT
        NULL, content TEXT NOT NULL, is_blank BOOLEAN NOT NULL, content_hash VARCHAR(64) NOT NULL,
        page_hash VARCHAR(64) NOT NULL, admission_years JSONB, tracks JSONB, warnings JSONB NOT
        NULL, CONSTRAINT pk_school_knowledge_chunks PRIMARY KEY (id), CONSTRAINT
        uq_school_knowledge_chunks_knowledge_document_id UNIQUE (knowledge_document_id, page,
        part_index), CONSTRAINT fk_school_knowledge_chunks_knowledge_document_id_school_0984
        FOREIGN KEY(knowledge_document_id, institution_id) REFERENCES school_knowledge_documents
        (id, institution_id) ON DELETE CASCADE, CONSTRAINT ck_school_knowledge_chunks_page CHECK
        (page BETWEEN 1 AND 200), CONSTRAINT ck_school_knowledge_chunks_parts CHECK (part_index >=
        0 AND part_index < part_count AND part_count <= 20), CONSTRAINT
        ck_school_knowledge_chunks_content_bounds CHECK (character_start >= 0 AND character_end =
        character_start + char_length(content) AND ((NOT is_blank AND char_length(content) BETWEEN
        1 AND 20000) OR (is_blank AND content = '' AND part_index = 0 AND part_count = 1 AND
        character_start = 0))), CONSTRAINT ck_school_knowledge_chunks_hashes CHECK (content_hash ~
        '^[0-9a-f]{64}$' AND page_hash ~ '^[0-9a-f]{64}$'), CONSTRAINT
        ck_school_knowledge_chunks_warnings CHECK (jsonb_typeof(warnings) = 'array'), CONSTRAINT
        ck_school_knowledge_chunks_years CHECK (admission_years IS NULL OR
        jsonb_typeof(admission_years) = 'array'), CONSTRAINT ck_school_knowledge_chunks_tracks
        CHECK (tracks IS NULL OR jsonb_typeof(tracks) = 'array') )
    """)


def downgrade():
    op.drop_table("school_knowledge_chunks")
    op.drop_table("school_knowledge_documents")
    op.drop_constraint("uq_official_documents_id", "official_documents", type_="unique")
