"""Owner-isolated personal planning, records and ordered draft references."""

from alembic import op

revision = "0004_personal_records"
down_revision = "0003_academic_catalog"
branch_labels = None
depends_on = None


def upgrade():
    op.execute("""
        CREATE TABLE application_documents ( target VARCHAR(128) NOT NULL, role VARCHAR(128) NOT
        NULL, document_type VARCHAR(128) NOT NULL, body TEXT NOT NULL, id UUID NOT NULL, owner_id
        UUID NOT NULL, client_id UUID, title VARCHAR(128) NOT NULL, detail TEXT NOT NULL, version
        INTEGER NOT NULL, created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, updated_at
        TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, CONSTRAINT pk_application_documents
        PRIMARY KEY (id), CONSTRAINT fk_application_documents_owner_id_users FOREIGN KEY(owner_id)
        REFERENCES users (id), CONSTRAINT uq_application_documents_id UNIQUE (id, owner_id),
        CONSTRAINT uq_application_documents_owner_id UNIQUE (owner_id, client_id), CONSTRAINT
        ck_application_documents_version CHECK (version >= 1) )
    """)
    op.execute("""
        CREATE INDEX ix_application_documents_owner_id ON application_documents (owner_id)
    """)
    op.execute("""
        CREATE TABLE personal_achievement_records ( achievement_type VARCHAR(128) NOT NULL,
        thesis_type VARCHAR(128) NOT NULL, thesis_status_label VARCHAR(128) NOT NULL, thesis_grade
        VARCHAR(128) NOT NULL, thesis_approved_on DATE, started_on DATE, ended_on DATE, role
        VARCHAR(128) NOT NULL, result TEXT NOT NULL, evidence_url VARCHAR(2048) NOT NULL, id UUID
        NOT NULL, owner_id UUID NOT NULL, client_id UUID, title VARCHAR(128) NOT NULL, detail TEXT
        NOT NULL, version INTEGER NOT NULL, created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT
        NULL, updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, CONSTRAINT
        pk_personal_achievement_records PRIMARY KEY (id), CONSTRAINT
        fk_personal_achievement_records_owner_id_users FOREIGN KEY(owner_id) REFERENCES users
        (id), CONSTRAINT uq_personal_achievement_records_id UNIQUE (id, owner_id), CONSTRAINT
        uq_personal_achievement_records_owner_id UNIQUE (owner_id, client_id), CONSTRAINT
        ck_personal_achievement_records_version CHECK (version >= 1), CONSTRAINT
        ck_personal_achievement_records_period CHECK (started_on IS NULL OR ended_on IS NULL OR
        started_on <= ended_on) )
    """)
    op.execute("""
        CREATE INDEX ix_personal_achievement_records_owner_id ON personal_achievement_records
        (owner_id)
    """)
    op.execute("""
        CREATE TABLE personal_activity_records ( organization VARCHAR(128) NOT NULL, started_on
        DATE, ended_on DATE, role VARCHAR(128) NOT NULL, reported_hours NUMERIC(12, 3),
        approved_hours NUMERIC(12, 3), approval VARCHAR(16), observed_on DATE, id UUID NOT NULL,
        owner_id UUID NOT NULL, client_id UUID, title VARCHAR(128) NOT NULL, detail TEXT NOT NULL,
        version INTEGER NOT NULL, created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, CONSTRAINT
        pk_personal_activity_records PRIMARY KEY (id), CONSTRAINT
        ck_personal_activity_records_reported_hours CHECK (reported_hours IS NULL OR
        reported_hours >= 0), CONSTRAINT ck_personal_activity_records_approved_hours CHECK
        (approved_hours IS NULL OR approved_hours >= 0), CONSTRAINT
        ck_personal_activity_records_observed_approval CHECK (approval IS NULL OR approval IN
        ('pending','approved','rejected','needs_review')), CONSTRAINT
        ck_personal_activity_records_observation_required CHECK (approved_hours IS NULL OR
        approved_hours = 0 OR (approval IS NOT NULL AND approval = 'approved' AND observed_on IS
        NOT NULL)), CONSTRAINT fk_personal_activity_records_owner_id_users FOREIGN KEY(owner_id)
        REFERENCES users (id), CONSTRAINT uq_personal_activity_records_id UNIQUE (id, owner_id),
        CONSTRAINT uq_personal_activity_records_owner_id UNIQUE (owner_id, client_id), CONSTRAINT
        ck_personal_activity_records_version CHECK (version >= 1), CONSTRAINT
        ck_personal_activity_records_period CHECK (started_on IS NULL OR ended_on IS NULL OR
        started_on <= ended_on) )
    """)
    op.execute("""
        CREATE INDEX ix_personal_activity_records_owner_id ON personal_activity_records (owner_id)
    """)
    op.execute("""
        CREATE TABLE personal_course_records ( term VARCHAR(128) NOT NULL, category VARCHAR(128)
        NOT NULL, credits NUMERIC(8, 3) NOT NULL, section VARCHAR(128) NOT NULL, course_code
        VARCHAR(128) NOT NULL, grade VARCHAR(128) NOT NULL, completion VARCHAR(16) NOT NULL, id
        UUID NOT NULL, owner_id UUID NOT NULL, client_id UUID, title VARCHAR(128) NOT NULL, detail
        TEXT NOT NULL, version INTEGER NOT NULL, created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
        NOT NULL, updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, CONSTRAINT
        pk_personal_course_records PRIMARY KEY (id), CONSTRAINT ck_personal_course_records_credits
        CHECK (credits > 0 AND credits <= 100), CONSTRAINT ck_personal_course_records_completion
        CHECK (completion IN ('planned','in_progress','recorded')), CONSTRAINT
        fk_personal_course_records_owner_id_users FOREIGN KEY(owner_id) REFERENCES users (id),
        CONSTRAINT uq_personal_course_records_id UNIQUE (id, owner_id), CONSTRAINT
        uq_personal_course_records_owner_id UNIQUE (owner_id, client_id), CONSTRAINT
        ck_personal_course_records_version CHECK (version >= 1) )
    """)
    op.execute("""
        CREATE INDEX ix_personal_course_records_owner_id ON personal_course_records (owner_id)
    """)
    op.execute("""
        CREATE TABLE personal_creation_receipts ( owner_id UUID NOT NULL, resource VARCHAR(48) NOT
        NULL, client_id UUID NOT NULL, record_id UUID NOT NULL, digest VARCHAR(64) NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, CONSTRAINT
        pk_personal_creation_receipts PRIMARY KEY (owner_id, resource, client_id), CONSTRAINT
        fk_personal_creation_receipts_owner_id_users FOREIGN KEY(owner_id) REFERENCES users (id) )
    """)
    op.execute("""
        CREATE TABLE personal_credential_records ( provider VARCHAR(128) NOT NULL, level
        VARCHAR(128) NOT NULL, earned_on DATE, expires_on DATE, status_label VARCHAR(128) NOT
        NULL, evidence_url VARCHAR(2048) NOT NULL, id UUID NOT NULL, owner_id UUID NOT NULL,
        client_id UUID, title VARCHAR(128) NOT NULL, detail TEXT NOT NULL, version INTEGER NOT
        NULL, created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, updated_at TIMESTAMP
        WITH TIME ZONE DEFAULT now() NOT NULL, CONSTRAINT pk_personal_credential_records PRIMARY
        KEY (id), CONSTRAINT ck_personal_credential_records_period CHECK (earned_on IS NULL OR
        expires_on IS NULL OR earned_on <= expires_on), CONSTRAINT
        fk_personal_credential_records_owner_id_users FOREIGN KEY(owner_id) REFERENCES users (id),
        CONSTRAINT uq_personal_credential_records_id UNIQUE (id, owner_id), CONSTRAINT
        uq_personal_credential_records_owner_id UNIQUE (owner_id, client_id), CONSTRAINT
        ck_personal_credential_records_version CHECK (version >= 1) )
    """)
    op.execute("""
        CREATE INDEX ix_personal_credential_records_owner_id ON personal_credential_records
        (owner_id)
    """)
    op.execute("""
        CREATE TABLE personal_curricula ( school VARCHAR(128) NOT NULL, department VARCHAR(128)
        NOT NULL, admission_year INTEGER NOT NULL, curriculum_year INTEGER NOT NULL, evidence_url
        VARCHAR(2048) NOT NULL, id UUID NOT NULL, owner_id UUID NOT NULL, client_id UUID, title
        VARCHAR(128) NOT NULL, detail TEXT NOT NULL, version INTEGER NOT NULL, created_at
        TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, updated_at TIMESTAMP WITH TIME ZONE
        DEFAULT now() NOT NULL, CONSTRAINT pk_personal_curricula PRIMARY KEY (id), CONSTRAINT
        ck_personal_curricula_admission_year CHECK (admission_year BETWEEN 1000 AND 9999),
        CONSTRAINT ck_personal_curricula_curriculum_year CHECK (curriculum_year BETWEEN 1000 AND
        9999), CONSTRAINT fk_personal_curricula_owner_id_users FOREIGN KEY(owner_id) REFERENCES
        users (id), CONSTRAINT uq_personal_curricula_id UNIQUE (id, owner_id), CONSTRAINT
        uq_personal_curricula_owner_id UNIQUE (owner_id, client_id), CONSTRAINT
        ck_personal_curricula_version CHECK (version >= 1) )
    """)
    op.execute("""
        CREATE INDEX ix_personal_curricula_owner_id ON personal_curricula (owner_id)
    """)
    op.execute("""
        CREATE TABLE personal_events ( starts_at TIMESTAMP WITH TIME ZONE NOT NULL, ends_at
        TIMESTAMP WITH TIME ZONE NOT NULL, time_zone VARCHAR(64) NOT NULL, category VARCHAR(16)
        NOT NULL, id UUID NOT NULL, owner_id UUID NOT NULL, client_id UUID, title VARCHAR(128) NOT
        NULL, detail TEXT NOT NULL, version INTEGER NOT NULL, created_at TIMESTAMP WITH TIME ZONE
        DEFAULT now() NOT NULL, updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        CONSTRAINT pk_personal_events PRIMARY KEY (id), CONSTRAINT ck_personal_events_period CHECK
        (ends_at > starts_at), CONSTRAINT ck_personal_events_category CHECK (category IN
        ('academic','personal','activity','deadline')), CONSTRAINT
        fk_personal_events_owner_id_users FOREIGN KEY(owner_id) REFERENCES users (id), CONSTRAINT
        uq_personal_events_id UNIQUE (id, owner_id), CONSTRAINT uq_personal_events_owner_id UNIQUE
        (owner_id, client_id), CONSTRAINT ck_personal_events_version CHECK (version >= 1) )
    """)
    op.execute("""
        CREATE INDEX ix_personal_events_owner_id ON personal_events (owner_id)
    """)
    op.execute("""
        CREATE INDEX ix_personal_events_starts_at ON personal_events (starts_at)
    """)
    op.execute("""
        CREATE TABLE personal_experience_records ( experience_type VARCHAR(128) NOT NULL,
        organization VARCHAR(128) NOT NULL, started_on DATE, ended_on DATE, role VARCHAR(128) NOT
        NULL, result TEXT NOT NULL, status_label VARCHAR(128) NOT NULL, id UUID NOT NULL, owner_id
        UUID NOT NULL, client_id UUID, title VARCHAR(128) NOT NULL, detail TEXT NOT NULL, version
        INTEGER NOT NULL, created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, updated_at
        TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, CONSTRAINT pk_personal_experience_records
        PRIMARY KEY (id), CONSTRAINT fk_personal_experience_records_owner_id_users FOREIGN
        KEY(owner_id) REFERENCES users (id), CONSTRAINT uq_personal_experience_records_id UNIQUE
        (id, owner_id), CONSTRAINT uq_personal_experience_records_owner_id UNIQUE (owner_id,
        client_id), CONSTRAINT ck_personal_experience_records_version CHECK (version >= 1),
        CONSTRAINT ck_personal_experience_records_period CHECK (started_on IS NULL OR ended_on IS
        NULL OR started_on <= ended_on) )
    """)
    op.execute("""
        CREATE INDEX ix_personal_experience_records_owner_id ON personal_experience_records
        (owner_id)
    """)
    op.execute("""
        CREATE TABLE portfolio_compositions ( audience VARCHAR(24) NOT NULL, reviewed BOOLEAN NOT
        NULL, id UUID NOT NULL, owner_id UUID NOT NULL, client_id UUID, title VARCHAR(128) NOT
        NULL, detail TEXT NOT NULL, version INTEGER NOT NULL, created_at TIMESTAMP WITH TIME ZONE
        DEFAULT now() NOT NULL, updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        CONSTRAINT pk_portfolio_compositions PRIMARY KEY (id), CONSTRAINT
        ck_portfolio_compositions_audience CHECK (audience IN
        ('private','application','public_review')), CONSTRAINT
        fk_portfolio_compositions_owner_id_users FOREIGN KEY(owner_id) REFERENCES users (id),
        CONSTRAINT uq_portfolio_compositions_id UNIQUE (id, owner_id), CONSTRAINT
        uq_portfolio_compositions_owner_id UNIQUE (owner_id, client_id), CONSTRAINT
        ck_portfolio_compositions_version CHECK (version >= 1) )
    """)
    op.execute("""
        CREATE INDEX ix_portfolio_compositions_owner_id ON portfolio_compositions (owner_id)
    """)
    op.execute("""
        CREATE TABLE application_document_sources ( document_id UUID NOT NULL, owner_id UUID NOT
        NULL, position INTEGER NOT NULL, achievement_id UUID, experience_id UUID, CONSTRAINT
        pk_application_document_sources PRIMARY KEY (document_id, position), CONSTRAINT
        uq_application_source_achievement UNIQUE (document_id, achievement_id), CONSTRAINT
        uq_application_source_experience UNIQUE (document_id, experience_id), CONSTRAINT
        ck_application_document_sources_position CHECK (position >= 0), CONSTRAINT
        ck_application_document_sources_one_source CHECK (num_nonnulls(achievement_id,
        experience_id) = 1), CONSTRAINT
        fk_application_document_sources_document_id_application_f6f7 FOREIGN KEY(document_id,
        owner_id) REFERENCES application_documents (id, owner_id) ON DELETE CASCADE, CONSTRAINT
        fk_application_document_sources_achievement_id_personal_a717 FOREIGN KEY(achievement_id,
        owner_id) REFERENCES personal_achievement_records (id, owner_id), CONSTRAINT
        fk_application_document_sources_experience_id_personal__56a7 FOREIGN KEY(experience_id,
        owner_id) REFERENCES personal_experience_records (id, owner_id) )
    """)
    op.execute("""
        CREATE TABLE personal_curriculum_courses ( curriculum_id UUID NOT NULL, course_record_id
        UUID, course_code VARCHAR(128) NOT NULL, category VARCHAR(128) NOT NULL, credits
        NUMERIC(8, 3) NOT NULL, required BOOLEAN NOT NULL, id UUID NOT NULL, owner_id UUID NOT
        NULL, client_id UUID, title VARCHAR(128) NOT NULL, detail TEXT NOT NULL, version INTEGER
        NOT NULL, created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, updated_at TIMESTAMP
        WITH TIME ZONE DEFAULT now() NOT NULL, CONSTRAINT pk_personal_curriculum_courses PRIMARY
        KEY (id), CONSTRAINT ck_personal_curriculum_courses_credits CHECK (credits > 0 AND credits
        <= 100), CONSTRAINT fk_personal_curriculum_courses_owner_id_users FOREIGN KEY(owner_id)
        REFERENCES users (id), CONSTRAINT uq_personal_curriculum_courses_id UNIQUE (id, owner_id),
        CONSTRAINT uq_personal_curriculum_courses_owner_id UNIQUE (owner_id, client_id),
        CONSTRAINT ck_personal_curriculum_courses_version CHECK (version >= 1), CONSTRAINT
        uq_personal_course_curriculum_owner UNIQUE (id, curriculum_id, owner_id), CONSTRAINT
        fk_personal_curriculum_courses_curriculum_id_personal_curricula FOREIGN KEY(curriculum_id,
        owner_id) REFERENCES personal_curricula (id, owner_id), CONSTRAINT
        fk_personal_curriculum_courses_course_record_id_persona_dec3 FOREIGN KEY(course_record_id,
        owner_id) REFERENCES personal_course_records (id, owner_id) )
    """)
    op.execute("""
        CREATE INDEX ix_personal_curriculum_courses_course_record_id ON
        personal_curriculum_courses (course_record_id)
    """)
    op.execute("""
        CREATE INDEX ix_personal_curriculum_courses_curriculum_id ON personal_curriculum_courses
        (curriculum_id)
    """)
    op.execute("""
        CREATE INDEX ix_personal_curriculum_courses_owner_id ON personal_curriculum_courses
        (owner_id)
    """)
    op.execute("""
        CREATE TABLE portfolio_sources ( composition_id UUID NOT NULL, owner_id UUID NOT NULL,
        position INTEGER NOT NULL, achievement_id UUID NOT NULL, CONSTRAINT pk_portfolio_sources
        PRIMARY KEY (composition_id, position), CONSTRAINT uq_portfolio_sources_composition_id
        UNIQUE (composition_id, achievement_id), CONSTRAINT ck_portfolio_sources_position CHECK
        (position >= 0), CONSTRAINT fk_portfolio_sources_composition_id_portfolio_compositions
        FOREIGN KEY(composition_id, owner_id) REFERENCES portfolio_compositions (id, owner_id) ON
        DELETE CASCADE, CONSTRAINT fk_portfolio_sources_achievement_id_personal_achievemen_07ed
        FOREIGN KEY(achievement_id, owner_id) REFERENCES personal_achievement_records (id,
        owner_id) )
    """)
    op.execute("""
        CREATE TABLE personal_graduation_rules ( curriculum_id UUID NOT NULL, curriculum_course_id
        UUID, rule_code VARCHAR(128) NOT NULL, rule_type VARCHAR(128) NOT NULL, scope VARCHAR(16)
        NOT NULL, required_value NUMERIC(18, 6), current_value NUMERIC(18, 6), unit VARCHAR(128)
        NOT NULL, condition TEXT NOT NULL, effective_from DATE, effective_to DATE, evidence_url
        VARCHAR(2048) NOT NULL, related_course_id UUID, related_activity_id UUID,
        related_experience_id UUID, related_credential_id UUID, related_achievement_id UUID, id
        UUID NOT NULL, owner_id UUID NOT NULL, client_id UUID, title VARCHAR(128) NOT NULL, detail
        TEXT NOT NULL, version INTEGER NOT NULL, created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
        NOT NULL, updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, CONSTRAINT
        pk_personal_graduation_rules PRIMARY KEY (id), CONSTRAINT
        ck_personal_graduation_rules_scope CHECK (scope IN
        ('institution','department','curriculum')), CONSTRAINT
        ck_personal_graduation_rules_required_value CHECK (required_value IS NULL OR
        required_value >= 0), CONSTRAINT ck_personal_graduation_rules_current_value CHECK
        (current_value IS NULL OR current_value >= 0), CONSTRAINT
        ck_personal_graduation_rules_period CHECK (effective_from IS NULL OR effective_to IS NULL
        OR effective_from <= effective_to), CONSTRAINT
        ck_personal_graduation_rules_one_related_record CHECK
        (num_nonnulls(related_course_id,related_activity_id,related_experience_id,related_credential_id,related_achievement_id)
        <= 1), CONSTRAINT fk_personal_graduation_rules_owner_id_users FOREIGN KEY(owner_id)
        REFERENCES users (id), CONSTRAINT uq_personal_graduation_rules_id UNIQUE (id, owner_id),
        CONSTRAINT uq_personal_graduation_rules_owner_id UNIQUE (owner_id, client_id), CONSTRAINT
        ck_personal_graduation_rules_version CHECK (version >= 1), CONSTRAINT
        fk_personal_graduation_rules_curriculum_id_personal_curricula FOREIGN KEY(curriculum_id,
        owner_id) REFERENCES personal_curricula (id, owner_id), CONSTRAINT
        fk_personal_graduation_rules_curriculum_course_id_perso_bb9b FOREIGN
        KEY(curriculum_course_id, curriculum_id, owner_id) REFERENCES personal_curriculum_courses
        (id, curriculum_id, owner_id), CONSTRAINT
        fk_personal_graduation_rules_related_course_id_personal_e42f FOREIGN
        KEY(related_course_id, owner_id) REFERENCES personal_course_records (id, owner_id),
        CONSTRAINT fk_personal_graduation_rules_related_activity_id_person_2630 FOREIGN
        KEY(related_activity_id, owner_id) REFERENCES personal_activity_records (id, owner_id),
        CONSTRAINT fk_personal_graduation_rules_related_experience_id_pers_7821 FOREIGN
        KEY(related_experience_id, owner_id) REFERENCES personal_experience_records (id,
        owner_id), CONSTRAINT fk_personal_graduation_rules_related_credential_id_pers_03cb FOREIGN
        KEY(related_credential_id, owner_id) REFERENCES personal_credential_records (id,
        owner_id), CONSTRAINT fk_personal_graduation_rules_related_achievement_id_per_6321 FOREIGN
        KEY(related_achievement_id, owner_id) REFERENCES personal_achievement_records (id,
        owner_id) )
    """)
    op.execute("""
        CREATE INDEX ix_personal_graduation_rules_curriculum_course_id ON
        personal_graduation_rules (curriculum_course_id)
    """)
    op.execute("""
        CREATE INDEX ix_personal_graduation_rules_curriculum_id ON personal_graduation_rules
        (curriculum_id)
    """)
    op.execute("""
        CREATE INDEX ix_personal_graduation_rules_owner_id ON personal_graduation_rules (owner_id)
    """)
    op.execute("""
        CREATE TABLE planning_profiles ( owner_id UUID NOT NULL, school VARCHAR(128) NOT NULL,
        department VARCHAR(128) NOT NULL, admission_year INTEGER, track VARCHAR(128),
        academic_year_override INTEGER, week_starts_on VARCHAR(16) NOT NULL, institution_id UUID,
        department_id UUID, curriculum_id UUID, version INTEGER NOT NULL, created_at TIMESTAMP
        WITH TIME ZONE DEFAULT now() NOT NULL, updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
        NOT NULL, CONSTRAINT pk_planning_profiles PRIMARY KEY (owner_id), CONSTRAINT
        ck_planning_profiles_version CHECK (version >= 1), CONSTRAINT ck_planning_profiles_year
        CHECK (admission_year IS NULL OR admission_year BETWEEN 1900 AND 9999), CONSTRAINT
        ck_planning_profiles_academic_year CHECK (academic_year_override IS NULL OR
        academic_year_override BETWEEN 1 AND 4), CONSTRAINT ck_planning_profiles_week_start CHECK
        (week_starts_on IN
        ('sunday','monday','tuesday','wednesday','thursday','friday','saturday')), CONSTRAINT
        ck_planning_profiles_hierarchy CHECK ((department_id IS NULL OR institution_id IS NOT
        NULL) AND (curriculum_id IS NULL OR department_id IS NOT NULL)), CONSTRAINT
        fk_planning_profiles_department_id_departments FOREIGN KEY(department_id, institution_id)
        REFERENCES departments (id, institution_id), CONSTRAINT
        fk_planning_profiles_curriculum_id_curricula FOREIGN KEY(curriculum_id, department_id,
        institution_id) REFERENCES curricula (id, department_id, institution_id), CONSTRAINT
        fk_planning_profiles_owner_id_users FOREIGN KEY(owner_id) REFERENCES users (id),
        CONSTRAINT fk_planning_profiles_institution_id_institutions FOREIGN KEY(institution_id)
        REFERENCES institutions (id) )
    """)


def downgrade():
    op.drop_table("planning_profiles")
    op.drop_table("personal_graduation_rules")
    op.drop_table("portfolio_sources")
    op.drop_table("personal_curriculum_courses")
    op.drop_table("application_document_sources")
    op.drop_table("portfolio_compositions")
    op.drop_table("personal_experience_records")
    op.drop_table("personal_events")
    op.drop_table("personal_curricula")
    op.drop_table("personal_credential_records")
    op.drop_table("personal_creation_receipts")
    op.drop_table("personal_course_records")
    op.drop_table("personal_activity_records")
    op.drop_table("personal_achievement_records")
    op.drop_table("application_documents")
