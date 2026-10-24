"""Global certificate identities and reviewed official rule execution programs."""

from alembic import op

revision = "0007_official_rule_programs"
down_revision = "0006_school_knowledge"
branch_labels = None
depends_on = None


def upgrade():
    op.execute("""
        ALTER TABLE school_knowledge_chunks ADD CONSTRAINT uq_school_knowledge_chunks_id UNIQUE
        (id, institution_id)
    """)
    op.execute("""
        CREATE TABLE certificate_providers ( id UUID NOT NULL, code VARCHAR(64) NOT NULL, name
        VARCHAR(128) NOT NULL, official_url VARCHAR(2048) NOT NULL, status VARCHAR(16) NOT NULL,
        version INTEGER NOT NULL, created_by UUID NOT NULL, updated_by UUID NOT NULL, created_at
        TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, updated_at TIMESTAMP WITH TIME ZONE
        DEFAULT now() NOT NULL, CONSTRAINT pk_certificate_providers PRIMARY KEY (id), CONSTRAINT
        uq_certificate_providers_code UNIQUE (code), CONSTRAINT ck_certificate_providers_version
        CHECK (version >= 1), CONSTRAINT ck_certificate_providers_status CHECK (status IN
        ('active','inactive')), CONSTRAINT fk_certificate_providers_created_by_users FOREIGN
        KEY(created_by) REFERENCES users (id), CONSTRAINT
        fk_certificate_providers_updated_by_users FOREIGN KEY(updated_by) REFERENCES users (id) )
    """)
    op.execute("""
        CREATE TABLE certificates ( provider_id UUID NOT NULL, id UUID NOT NULL, code VARCHAR(64)
        NOT NULL, name VARCHAR(128) NOT NULL, official_url VARCHAR(2048) NOT NULL, status
        VARCHAR(16) NOT NULL, version INTEGER NOT NULL, created_by UUID NOT NULL, updated_by UUID
        NOT NULL, created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, updated_at TIMESTAMP
        WITH TIME ZONE DEFAULT now() NOT NULL, CONSTRAINT pk_certificates PRIMARY KEY (id),
        CONSTRAINT uq_certificates_provider_id UNIQUE (provider_id, code), CONSTRAINT
        ck_certificates_version CHECK (version >= 1), CONSTRAINT ck_certificates_status CHECK
        (status IN ('active','inactive')), CONSTRAINT
        fk_certificates_provider_id_certificate_providers FOREIGN KEY(provider_id) REFERENCES
        certificate_providers (id), CONSTRAINT fk_certificates_created_by_users FOREIGN
        KEY(created_by) REFERENCES users (id), CONSTRAINT fk_certificates_updated_by_users FOREIGN
        KEY(updated_by) REFERENCES users (id) )
    """)
    op.execute("""
        CREATE INDEX ix_certificates_provider_id ON certificates (provider_id)
    """)
    op.execute("""
        CREATE TABLE official_rule_programs ( rule_set_id UUID, rule_id UUID, source_version
        INTEGER NOT NULL, department_id UUID, curriculum_id UUID, admission_year_from INTEGER NOT
        NULL, admission_year_to INTEGER NOT NULL, tracks JSONB NOT NULL, effective_from DATE,
        effective_to DATE, status VARCHAR(16) NOT NULL, approved_by UUID, approved_at TIMESTAMP
        WITH TIME ZONE, review_note VARCHAR(500) NOT NULL, revoked_by UUID, revoked_at TIMESTAMP
        WITH TIME ZONE, revocation_reason VARCHAR(500) NOT NULL, id UUID NOT NULL, institution_id
        UUID NOT NULL, name VARCHAR(128) NOT NULL, version INTEGER NOT NULL, created_by UUID NOT
        NULL, updated_by UUID NOT NULL, created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT
        NULL, updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, CONSTRAINT
        pk_official_rule_programs PRIMARY KEY (id), CONSTRAINT uq_official_rule_programs_id UNIQUE
        (id, institution_id), CONSTRAINT fk_official_rule_programs_rule_set_id_rule_sets FOREIGN
        KEY(rule_set_id, institution_id) REFERENCES rule_sets (id, institution_id), CONSTRAINT
        fk_official_rule_programs_rule_id_graduation_rules FOREIGN KEY(rule_id, institution_id)
        REFERENCES graduation_rules (id, institution_id), CONSTRAINT
        fk_official_rule_programs_department_id_departments FOREIGN KEY(department_id,
        institution_id) REFERENCES departments (id, institution_id), CONSTRAINT
        fk_official_rule_programs_curriculum_id_curricula FOREIGN KEY(curriculum_id,
        department_id, institution_id) REFERENCES curricula (id, department_id, institution_id),
        CONSTRAINT ck_official_rule_programs_single_target CHECK ((rule_set_id IS NULL) <>
        (rule_id IS NULL)), CONSTRAINT ck_official_rule_programs_versions CHECK (version >= 1 AND
        source_version >= 1), CONSTRAINT ck_official_rule_programs_years CHECK
        (admission_year_from >= 1000 AND admission_year_from <= 9999 AND admission_year_to >=
        admission_year_from AND admission_year_to <= 9999 AND admission_year_to -
        admission_year_from < 200), CONSTRAINT ck_official_rule_programs_tracks CHECK
        (jsonb_typeof(tracks) = 'array' AND jsonb_array_length(tracks) BETWEEN 1 AND 32),
        CONSTRAINT ck_official_rule_programs_scope CHECK (curriculum_id IS NULL OR department_id
        IS NOT NULL), CONSTRAINT ck_official_rule_programs_dates CHECK (effective_from IS NULL OR
        effective_to IS NULL OR effective_from <= effective_to), CONSTRAINT
        ck_official_rule_programs_status CHECK (status IN ('draft','approved','revoked')),
        CONSTRAINT ck_official_rule_programs_approval CHECK ((status = 'draft' AND approved_by IS
        NULL AND approved_at IS NULL) OR (status <> 'draft' AND approved_by IS NOT NULL AND
        approved_at IS NOT NULL AND length(trim(review_note)) > 0)), CONSTRAINT
        ck_official_rule_programs_revocation CHECK ((status <> 'revoked' AND revoked_by IS NULL
        AND revoked_at IS NULL) OR (status = 'revoked' AND revoked_by IS NOT NULL AND revoked_at
        IS NOT NULL AND length(trim(revocation_reason)) > 0)), CONSTRAINT
        fk_official_rule_programs_approved_by_users FOREIGN KEY(approved_by) REFERENCES users
        (id), CONSTRAINT fk_official_rule_programs_revoked_by_users FOREIGN KEY(revoked_by)
        REFERENCES users (id), CONSTRAINT fk_official_rule_programs_institution_id_institutions
        FOREIGN KEY(institution_id) REFERENCES institutions (id), CONSTRAINT
        fk_official_rule_programs_created_by_users FOREIGN KEY(created_by) REFERENCES users (id),
        CONSTRAINT fk_official_rule_programs_updated_by_users FOREIGN KEY(updated_by) REFERENCES
        users (id) )
    """)
    op.execute("""
        CREATE INDEX ix_official_rule_programs_institution_id ON official_rule_programs
        (institution_id)
    """)
    op.execute("""
        CREATE INDEX ix_official_rule_programs_rule_id ON official_rule_programs (rule_id)
    """)
    op.execute("""
        CREATE INDEX ix_official_rule_programs_rule_set_id ON official_rule_programs (rule_set_id)
    """)
    op.execute("""
        CREATE TABLE official_program_rules ( id UUID NOT NULL, program_id UUID NOT NULL,
        institution_id UUID NOT NULL, rule_id UUID NOT NULL, source_version INTEGER NOT NULL,
        title VARCHAR(128) NOT NULL, kind VARCHAR(32) NOT NULL, condition_json JSONB NOT NULL,
        CONSTRAINT pk_official_program_rules PRIMARY KEY (id), CONSTRAINT
        uq_official_program_rules_id UNIQUE (id, institution_id), CONSTRAINT
        uq_official_program_rules_program_id UNIQUE (program_id, rule_id), CONSTRAINT
        fk_official_program_rules_program_id_official_rule_programs FOREIGN KEY(program_id,
        institution_id) REFERENCES official_rule_programs (id, institution_id) ON DELETE CASCADE,
        CONSTRAINT fk_official_program_rules_rule_id_graduation_rules FOREIGN KEY(rule_id,
        institution_id) REFERENCES graduation_rules (id, institution_id), CONSTRAINT
        ck_official_program_rules_version CHECK (source_version >= 1), CONSTRAINT
        ck_official_program_rules_kind CHECK (kind IN
        ('minimum_credits','required_courses','minimum_volunteer_hours','any_certificate','thesis','manual_review')),
        CONSTRAINT ck_official_program_rules_condition CHECK (jsonb_typeof(condition_json) =
        'object' AND coalesce(condition_json->>'kind' = kind, false)) )
    """)
    op.execute("""
        CREATE TABLE official_program_evidence ( program_rule_id UUID NOT NULL, chunk_id UUID NOT
        NULL, institution_id UUID NOT NULL, knowledge_version INTEGER NOT NULL, content_hash
        VARCHAR(64) NOT NULL, CONSTRAINT pk_official_program_evidence PRIMARY KEY
        (program_rule_id, chunk_id), CONSTRAINT
        fk_official_program_evidence_program_rule_id_official_p_5af3 FOREIGN KEY(program_rule_id,
        institution_id) REFERENCES official_program_rules (id, institution_id) ON DELETE CASCADE,
        CONSTRAINT fk_official_program_evidence_chunk_id_school_knowledge_chunks FOREIGN
        KEY(chunk_id, institution_id) REFERENCES school_knowledge_chunks (id, institution_id),
        CONSTRAINT ck_official_program_evidence_version CHECK (knowledge_version >= 1), CONSTRAINT
        ck_official_program_evidence_hash CHECK (content_hash ~ '^[0-9a-f]{64}$') )
    """)
    op.execute("""
        CREATE TABLE official_program_course_refs ( program_rule_id UUID NOT NULL, course_id UUID
        NOT NULL, institution_id UUID NOT NULL, catalog_version INTEGER NOT NULL, code VARCHAR(64)
        NOT NULL, name VARCHAR(128) NOT NULL, CONSTRAINT pk_official_program_course_refs PRIMARY
        KEY (program_rule_id, course_id), CONSTRAINT
        fk_official_program_course_refs_program_rule_id_officia_b72d FOREIGN KEY(program_rule_id,
        institution_id) REFERENCES official_program_rules (id, institution_id) ON DELETE CASCADE,
        CONSTRAINT fk_official_program_course_refs_course_id_courses FOREIGN KEY(course_id,
        institution_id) REFERENCES courses (id, institution_id), CONSTRAINT
        ck_official_program_course_refs_version CHECK (catalog_version >= 1) )
    """)
    op.execute("""
        CREATE TABLE official_program_certificate_refs ( program_rule_id UUID NOT NULL,
        certificate_id UUID NOT NULL, institution_id UUID NOT NULL, catalog_version INTEGER NOT
        NULL, code VARCHAR(64) NOT NULL, name VARCHAR(128) NOT NULL, provider_name VARCHAR(128)
        NOT NULL, CONSTRAINT pk_official_program_certificate_refs PRIMARY KEY (program_rule_id,
        certificate_id), CONSTRAINT fk_official_program_certificate_refs_program_rule_id_of_5a46
        FOREIGN KEY(program_rule_id, institution_id) REFERENCES official_program_rules (id,
        institution_id) ON DELETE CASCADE, CONSTRAINT ck_official_program_certificate_refs_version
        CHECK (catalog_version >= 1), CONSTRAINT
        fk_official_program_certificate_refs_certificate_id_cer_ded7 FOREIGN KEY(certificate_id)
        REFERENCES certificates (id) )
    """)


def downgrade():
    op.drop_table("official_program_certificate_refs")
    op.drop_table("official_program_course_refs")
    op.drop_table("official_program_evidence")
    op.drop_table("official_program_rules")
    op.drop_table("official_rule_programs")
    op.drop_table("certificates")
    op.drop_table("certificate_providers")
    op.drop_constraint("uq_school_knowledge_chunks_id", "school_knowledge_chunks", type_="unique")
