"""Academic catalog and immutable reviewed metadata revisions."""

from alembic import op

revision = "0003_academic_catalog"
down_revision = "0002_identity_sessions"
branch_labels = None
depends_on = None


def upgrade():
    op.execute("""
        ALTER TABLE institutions ADD COLUMN country_code VARCHAR(2) NOT NULL DEFAULT ''
    """)
    op.execute("""
        ALTER TABLE institutions ADD COLUMN official_url VARCHAR(2048) NOT NULL DEFAULT ''
    """)
    op.execute("""
        ALTER TABLE institutions ADD COLUMN version INTEGER NOT NULL DEFAULT 1
    """)
    op.execute("""
        ALTER TABLE institutions ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT
        now()
    """)
    op.execute("""
        ALTER TABLE institutions ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE
    """)
    op.execute("""
        ALTER TABLE admin_scopes ADD COLUMN revocation_reason VARCHAR(500) NOT NULL DEFAULT ''
    """)
    op.execute("""
        CREATE TABLE courses ( code VARCHAR(64) NOT NULL, credits NUMERIC(8, 3) NOT NULL, id UUID
        NOT NULL, institution_id UUID NOT NULL, name VARCHAR(128) NOT NULL, version INTEGER NOT
        NULL, created_by UUID NOT NULL, updated_by UUID NOT NULL, created_at TIMESTAMP WITH TIME
        ZONE DEFAULT now() NOT NULL, updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        CONSTRAINT pk_courses PRIMARY KEY (id), CONSTRAINT uq_courses_institution_id UNIQUE
        (institution_id, code), CONSTRAINT ck_courses_credits CHECK (credits >= 0 AND credits <=
        100), CONSTRAINT fk_courses_institution_id_institutions FOREIGN KEY(institution_id)
        REFERENCES institutions (id), CONSTRAINT fk_courses_created_by_users FOREIGN
        KEY(created_by) REFERENCES users (id), CONSTRAINT fk_courses_updated_by_users FOREIGN
        KEY(updated_by) REFERENCES users (id), CONSTRAINT uq_courses_id UNIQUE (id,
        institution_id) )
    """)
    op.execute("""
        CREATE INDEX ix_courses_institution_id ON courses (institution_id)
    """)
    op.execute("""
        CREATE TABLE departments ( code VARCHAR(64) NOT NULL, id UUID NOT NULL, institution_id
        UUID NOT NULL, name VARCHAR(128) NOT NULL, version INTEGER NOT NULL, created_by UUID NOT
        NULL, updated_by UUID NOT NULL, created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT
        NULL, updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, CONSTRAINT
        pk_departments PRIMARY KEY (id), CONSTRAINT uq_departments_institution_id UNIQUE
        (institution_id, code), CONSTRAINT fk_departments_institution_id_institutions FOREIGN
        KEY(institution_id) REFERENCES institutions (id), CONSTRAINT
        fk_departments_created_by_users FOREIGN KEY(created_by) REFERENCES users (id), CONSTRAINT
        fk_departments_updated_by_users FOREIGN KEY(updated_by) REFERENCES users (id), CONSTRAINT
        uq_departments_id UNIQUE (id, institution_id) )
    """)
    op.execute("""
        CREATE INDEX ix_departments_institution_id ON departments (institution_id)
    """)
    op.execute("""
        CREATE TABLE curricula ( department_id UUID NOT NULL, year INTEGER NOT NULL, id UUID NOT
        NULL, institution_id UUID NOT NULL, name VARCHAR(128) NOT NULL, version INTEGER NOT NULL,
        created_by UUID NOT NULL, updated_by UUID NOT NULL, created_at TIMESTAMP WITH TIME ZONE
        DEFAULT now() NOT NULL, updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        CONSTRAINT pk_curricula PRIMARY KEY (id), CONSTRAINT uq_curricula_department_id UNIQUE
        (department_id, year, name), CONSTRAINT ck_curricula_year CHECK (year BETWEEN 1000 AND
        9999), CONSTRAINT fk_curricula_institution_id_institutions FOREIGN KEY(institution_id)
        REFERENCES institutions (id), CONSTRAINT fk_curricula_created_by_users FOREIGN
        KEY(created_by) REFERENCES users (id), CONSTRAINT fk_curricula_updated_by_users FOREIGN
        KEY(updated_by) REFERENCES users (id), CONSTRAINT uq_curricula_id UNIQUE (id,
        institution_id), CONSTRAINT uq_curricula_scope UNIQUE (id, department_id, institution_id),
        CONSTRAINT fk_curricula_department_id_departments FOREIGN KEY(department_id,
        institution_id) REFERENCES departments (id, institution_id) )
    """)
    op.execute("""
        CREATE INDEX ix_curricula_department_id ON curricula (department_id)
    """)
    op.execute("""
        CREATE INDEX ix_curricula_institution_id ON curricula (institution_id)
    """)
    op.execute("""
        CREATE TABLE curriculum_courses ( curriculum_id UUID NOT NULL, course_id UUID NOT NULL,
        category VARCHAR(16) NOT NULL, required BOOLEAN NOT NULL, id UUID NOT NULL, institution_id
        UUID NOT NULL, name VARCHAR(128) NOT NULL, version INTEGER NOT NULL, created_by UUID NOT
        NULL, updated_by UUID NOT NULL, created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT
        NULL, updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, CONSTRAINT
        pk_curriculum_courses PRIMARY KEY (id), CONSTRAINT uq_curriculum_courses_curriculum_id
        UNIQUE (curriculum_id, course_id), CONSTRAINT ck_curriculum_courses_category CHECK
        (category IN ('major', 'general', 'other')), CONSTRAINT
        fk_curriculum_courses_institution_id_institutions FOREIGN KEY(institution_id) REFERENCES
        institutions (id), CONSTRAINT fk_curriculum_courses_created_by_users FOREIGN
        KEY(created_by) REFERENCES users (id), CONSTRAINT fk_curriculum_courses_updated_by_users
        FOREIGN KEY(updated_by) REFERENCES users (id), CONSTRAINT
        fk_curriculum_courses_course_id_courses FOREIGN KEY(course_id, institution_id) REFERENCES
        courses (id, institution_id), CONSTRAINT fk_curriculum_courses_curriculum_id_curricula
        FOREIGN KEY(curriculum_id, institution_id) REFERENCES curricula (id, institution_id) )
    """)
    op.execute("""
        CREATE INDEX ix_curriculum_courses_course_id ON curriculum_courses (course_id)
    """)
    op.execute("""
        CREATE INDEX ix_curriculum_courses_curriculum_id ON curriculum_courses (curriculum_id)
    """)
    op.execute("""
        CREATE INDEX ix_curriculum_courses_institution_id ON curriculum_courses (institution_id)
    """)
    op.execute("""
        CREATE TABLE rule_sets ( department_id UUID, curriculum_id UUID, lineage_id UUID NOT NULL,
        revision INTEGER NOT NULL, status VARCHAR(16) NOT NULL, effective_from DATE, effective_to
        DATE, applied_by UUID, applied_at TIMESTAMP WITH TIME ZONE, id UUID NOT NULL,
        institution_id UUID NOT NULL, name VARCHAR(128) NOT NULL, version INTEGER NOT NULL,
        created_by UUID NOT NULL, updated_by UUID NOT NULL, created_at TIMESTAMP WITH TIME ZONE
        DEFAULT now() NOT NULL, updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        CONSTRAINT pk_rule_sets PRIMARY KEY (id), CONSTRAINT fk_rule_sets_applied_by_users FOREIGN
        KEY(applied_by) REFERENCES users (id), CONSTRAINT fk_rule_sets_institution_id_institutions
        FOREIGN KEY(institution_id) REFERENCES institutions (id), CONSTRAINT
        fk_rule_sets_created_by_users FOREIGN KEY(created_by) REFERENCES users (id), CONSTRAINT
        fk_rule_sets_updated_by_users FOREIGN KEY(updated_by) REFERENCES users (id), CONSTRAINT
        ck_rule_sets_status CHECK (status IN ('draft', 'applied')), CONSTRAINT
        ck_rule_sets_versions CHECK (revision >= 1 AND version >= 1), CONSTRAINT
        ck_rule_sets_effective_period CHECK (effective_from IS NULL OR effective_to IS NULL OR
        effective_from <= effective_to), CONSTRAINT ck_rule_sets_scope_hierarchy CHECK
        (curriculum_id IS NULL OR department_id IS NOT NULL), CONSTRAINT uq_rule_sets_lineage_id
        UNIQUE (lineage_id, revision), CONSTRAINT uq_rule_sets_id UNIQUE (id, institution_id),
        CONSTRAINT fk_rule_sets_department_id_departments FOREIGN KEY(department_id,
        institution_id) REFERENCES departments (id, institution_id), CONSTRAINT
        fk_rule_sets_curriculum_id_curricula FOREIGN KEY(curriculum_id, department_id,
        institution_id) REFERENCES curricula (id, department_id, institution_id) )
    """)
    op.execute("""
        CREATE INDEX ix_rule_sets_curriculum_id ON rule_sets (curriculum_id)
    """)
    op.execute("""
        CREATE INDEX ix_rule_sets_department_id ON rule_sets (department_id)
    """)
    op.execute("""
        CREATE INDEX ix_rule_sets_institution_id ON rule_sets (institution_id)
    """)
    op.execute("""
        CREATE UNIQUE INDEX uq_rule_sets_draft ON rule_sets (lineage_id) WHERE status = 'draft'
    """)
    op.execute("""
        CREATE TABLE graduation_rules ( rule_set_id UUID, rule_type VARCHAR(32) NOT NULL,
        definition TEXT NOT NULL, source_url VARCHAR(2048) NOT NULL, department_id UUID,
        curriculum_id UUID, lineage_id UUID NOT NULL, revision INTEGER NOT NULL, status
        VARCHAR(16) NOT NULL, effective_from DATE, effective_to DATE, applied_by UUID, applied_at
        TIMESTAMP WITH TIME ZONE, id UUID NOT NULL, institution_id UUID NOT NULL, name
        VARCHAR(128) NOT NULL, version INTEGER NOT NULL, created_by UUID NOT NULL, updated_by UUID
        NOT NULL, created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, updated_at TIMESTAMP
        WITH TIME ZONE DEFAULT now() NOT NULL, CONSTRAINT pk_graduation_rules PRIMARY KEY (id),
        CONSTRAINT fk_graduation_rules_applied_by_users FOREIGN KEY(applied_by) REFERENCES users
        (id), CONSTRAINT fk_graduation_rules_institution_id_institutions FOREIGN
        KEY(institution_id) REFERENCES institutions (id), CONSTRAINT
        fk_graduation_rules_created_by_users FOREIGN KEY(created_by) REFERENCES users (id),
        CONSTRAINT fk_graduation_rules_updated_by_users FOREIGN KEY(updated_by) REFERENCES users
        (id), CONSTRAINT ck_graduation_rules_status CHECK (status IN ('draft', 'applied')),
        CONSTRAINT ck_graduation_rules_versions CHECK (revision >= 1 AND version >= 1), CONSTRAINT
        ck_graduation_rules_effective_period CHECK (effective_from IS NULL OR effective_to IS NULL
        OR effective_from <= effective_to), CONSTRAINT ck_graduation_rules_scope_hierarchy CHECK
        (curriculum_id IS NULL OR department_id IS NOT NULL), CONSTRAINT
        uq_graduation_rules_lineage_id UNIQUE (lineage_id, revision), CONSTRAINT
        uq_graduation_rules_id UNIQUE (id, institution_id), CONSTRAINT
        fk_graduation_rules_department_id_departments FOREIGN KEY(department_id, institution_id)
        REFERENCES departments (id, institution_id), CONSTRAINT
        fk_graduation_rules_curriculum_id_curricula FOREIGN KEY(curriculum_id, department_id,
        institution_id) REFERENCES curricula (id, department_id, institution_id), CONSTRAINT
        ck_graduation_rules_rule_type CHECK (rule_type IN ('credits', 'required_course',
        'volunteer', 'thesis', 'certificate', 'custom')), CONSTRAINT
        fk_graduation_rules_rule_set_id_rule_sets FOREIGN KEY(rule_set_id, institution_id)
        REFERENCES rule_sets (id, institution_id) )
    """)
    op.execute("""
        CREATE INDEX ix_graduation_rules_curriculum_id ON graduation_rules (curriculum_id)
    """)
    op.execute("""
        CREATE INDEX ix_graduation_rules_department_id ON graduation_rules (department_id)
    """)
    op.execute("""
        CREATE INDEX ix_graduation_rules_institution_id ON graduation_rules (institution_id)
    """)
    op.execute("""
        CREATE INDEX ix_graduation_rules_rule_set_id ON graduation_rules (rule_set_id)
    """)
    op.execute("""
        CREATE UNIQUE INDEX uq_graduation_rules_draft ON graduation_rules (lineage_id) WHERE
        status = 'draft'
    """)
    op.execute("""
        CREATE TABLE official_documents ( source_url VARCHAR(2048) NOT NULL, document_type
        VARCHAR(24) NOT NULL, rule_id UUID, department_id UUID, curriculum_id UUID, lineage_id
        UUID NOT NULL, revision INTEGER NOT NULL, status VARCHAR(16) NOT NULL, effective_from
        DATE, effective_to DATE, applied_by UUID, applied_at TIMESTAMP WITH TIME ZONE, id UUID NOT
        NULL, institution_id UUID NOT NULL, name VARCHAR(128) NOT NULL, version INTEGER NOT NULL,
        created_by UUID NOT NULL, updated_by UUID NOT NULL, created_at TIMESTAMP WITH TIME ZONE
        DEFAULT now() NOT NULL, updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        CONSTRAINT pk_official_documents PRIMARY KEY (id), CONSTRAINT
        fk_official_documents_applied_by_users FOREIGN KEY(applied_by) REFERENCES users (id),
        CONSTRAINT fk_official_documents_institution_id_institutions FOREIGN KEY(institution_id)
        REFERENCES institutions (id), CONSTRAINT fk_official_documents_created_by_users FOREIGN
        KEY(created_by) REFERENCES users (id), CONSTRAINT fk_official_documents_updated_by_users
        FOREIGN KEY(updated_by) REFERENCES users (id), CONSTRAINT ck_official_documents_status
        CHECK (status IN ('draft', 'applied')), CONSTRAINT ck_official_documents_versions CHECK
        (revision >= 1 AND version >= 1), CONSTRAINT ck_official_documents_effective_period CHECK
        (effective_from IS NULL OR effective_to IS NULL OR effective_from <= effective_to),
        CONSTRAINT ck_official_documents_scope_hierarchy CHECK (curriculum_id IS NULL OR
        department_id IS NOT NULL), CONSTRAINT uq_official_documents_lineage_id UNIQUE
        (lineage_id, revision), CONSTRAINT fk_official_documents_department_id_departments FOREIGN
        KEY(department_id, institution_id) REFERENCES departments (id, institution_id), CONSTRAINT
        fk_official_documents_curriculum_id_curricula FOREIGN KEY(curriculum_id, department_id,
        institution_id) REFERENCES curricula (id, department_id, institution_id), CONSTRAINT
        fk_official_documents_rule_id_graduation_rules FOREIGN KEY(rule_id, institution_id)
        REFERENCES graduation_rules (id, institution_id), CONSTRAINT
        ck_official_documents_document_type CHECK (document_type IN ('academic', 'graduation',
        'other')) )
    """)
    op.execute("""
        CREATE INDEX ix_official_documents_curriculum_id ON official_documents (curriculum_id)
    """)
    op.execute("""
        CREATE INDEX ix_official_documents_department_id ON official_documents (department_id)
    """)
    op.execute("""
        CREATE INDEX ix_official_documents_institution_id ON official_documents (institution_id)
    """)
    op.execute("""
        CREATE INDEX ix_official_documents_rule_id ON official_documents (rule_id)
    """)
    op.execute("""
        CREATE UNIQUE INDEX uq_official_documents_draft ON official_documents (lineage_id) WHERE
        status = 'draft'
    """)


def downgrade():
    op.drop_column("admin_scopes", "revocation_reason")
    op.drop_table("official_documents")
    op.drop_table("graduation_rules")
    op.drop_table("rule_sets")
    op.drop_table("curriculum_courses")
    op.drop_table("curricula")
    op.drop_table("departments")
    op.drop_table("courses")
    op.drop_column("institutions", "deleted_at")
    op.drop_column("institutions", "updated_at")
    op.drop_column("institutions", "version")
    op.drop_column("institutions", "official_url")
    op.drop_column("institutions", "country_code")
