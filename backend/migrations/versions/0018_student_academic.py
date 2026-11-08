"""Add owner-only student academic bindings without rewriting existing records."""

from alembic import op

revision = "0018_student_academic"
down_revision = "0017_admin_academic_requirements"
branch_labels = None
depends_on = None


def upgrade():
    op.execute(r"""

CREATE TABLE student_academic_activations (
	id UUID NOT NULL,
	owner_id UUID NOT NULL,
	context_digest VARCHAR(64) NOT NULL,
	selection_digest VARCHAR(64) NOT NULL,
	contexts_json JSONB NOT NULL,
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
	CONSTRAINT pk_student_academic_activations PRIMARY KEY (id),
	CONSTRAINT uq_student_academic_activations_id UNIQUE (id, owner_id),
        CONSTRAINT fk_student_academic_activations_owner_id_users FOREIGN KEY(owner_id)
REFERENCES users (id)
)

;

CREATE INDEX ix_student_academic_activations_owner_id ON student_academic_activations
(owner_id);


CREATE TABLE student_academic_receipts (
	owner_id UUID NOT NULL,
	client_id UUID NOT NULL,
	request_digest VARCHAR(64) NOT NULL,
	response_json JSONB NOT NULL,
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
	CONSTRAINT pk_student_academic_receipts PRIMARY KEY (owner_id, client_id),
        CONSTRAINT fk_student_academic_receipts_owner_id_users FOREIGN KEY(owner_id) REFERENCES
users (id)
)

;


CREATE TABLE student_academic_workspaces (
	owner_id UUID NOT NULL,
	version INTEGER NOT NULL,
	active_activation_id UUID,
	CONSTRAINT pk_student_academic_workspaces PRIMARY KEY (owner_id),
        CONSTRAINT fk_student_academic_workspaces_active_activation_id_stu_db28 FOREIGN
KEY(active_activation_id, owner_id) REFERENCES student_academic_activations (id, owner_id),
	CONSTRAINT ck_student_academic_workspaces_version CHECK (version >= 0),
        CONSTRAINT fk_student_academic_workspaces_owner_id_users FOREIGN KEY(owner_id)
REFERENCES users (id)
)

;


CREATE TABLE student_academic_contexts (
	id UUID NOT NULL,
	owner_id UUID NOT NULL,
	institution_id UUID NOT NULL,
	department_id UUID NOT NULL,
	track_id UUID NOT NULL,
	curriculum_revision_id UUID NOT NULL,
	admission_year INTEGER NOT NULL,
	"primary" BOOLEAN NOT NULL,
	active BOOLEAN NOT NULL,
	position INTEGER NOT NULL,
	CONSTRAINT pk_student_academic_contexts PRIMARY KEY (id),
	CONSTRAINT uq_student_academic_contexts_id UNIQUE (id, owner_id),
	CONSTRAINT ck_student_academic_contexts_year CHECK (admission_year BETWEEN 1000 AND 9999),
	CONSTRAINT ck_student_academic_contexts_position CHECK (position >= 0),
        CONSTRAINT fk_student_academic_contexts_owner_id_student_academic__cade FOREIGN
KEY(owner_id) REFERENCES student_academic_workspaces (owner_id),
        CONSTRAINT fk_student_academic_contexts_institution_id_institutions FOREIGN
KEY(institution_id) REFERENCES institutions (id),
        CONSTRAINT fk_student_academic_contexts_department_id_departments FOREIGN
KEY(department_id) REFERENCES departments (id),
        CONSTRAINT fk_student_academic_contexts_track_id_academic_study_tracks FOREIGN
KEY(track_id) REFERENCES academic_study_tracks (id),
        CONSTRAINT fk_student_academic_contexts_curriculum_revision_id_aca_560d FOREIGN
KEY(curriculum_revision_id) REFERENCES academic_curriculum_revisions (id)
)

;


CREATE TABLE student_academic_course_links (
	id UUID NOT NULL,
	owner_id UUID NOT NULL,
	course_record_id UUID NOT NULL,
	context_id UUID NOT NULL,
	entry_id UUID NOT NULL,
	record_version INTEGER NOT NULL,
	result VARCHAR(20) NOT NULL,
	earned_credits NUMERIC(8, 3),
	included BOOLEAN NOT NULL,
	version INTEGER NOT NULL,
	CONSTRAINT pk_student_academic_course_links PRIMARY KEY (id),
        CONSTRAINT uq_student_academic_course_links_owner_id UNIQUE (owner_id, course_record_id,
 context_id),
        CONSTRAINT fk_student_academic_course_links_course_record_id_perso_8c98 FOREIGN
KEY(course_record_id, owner_id) REFERENCES personal_course_records (id, owner_id) ON DELETE
CASCADE,
        CONSTRAINT fk_student_academic_course_links_context_id_student_aca_c5d4 FOREIGN
KEY(context_id, owner_id) REFERENCES student_academic_contexts (id, owner_id),
        CONSTRAINT ck_student_academic_course_links_result CHECK (result IN
('completed','not_completed','needs_review')),
        CONSTRAINT ck_student_academic_course_links_credits CHECK (earned_credits IS NULL OR
earned_credits BETWEEN 0 AND 100),
        CONSTRAINT ck_student_academic_course_links_versions CHECK (version >= 1 AND
record_version >= 1),
        CONSTRAINT fk_student_academic_course_links_owner_id_users FOREIGN KEY(owner_id)
REFERENCES users (id),
        CONSTRAINT fk_student_academic_course_links_entry_id_academic_curr_f589 FOREIGN
KEY(entry_id) REFERENCES academic_curriculum_courses (id)
)

;

CREATE INDEX ix_student_academic_course_links_owner_id ON student_academic_course_links
(owner_id);


CREATE TABLE student_academic_documents (
	activation_id UUID NOT NULL,
	requirement_revision_id UUID NOT NULL,
	snapshot_json JSONB NOT NULL,
	CONSTRAINT pk_student_academic_documents PRIMARY KEY (activation_id, requirement_revision_id),
        CONSTRAINT fk_student_academic_documents_activation_id_student_aca_af5b FOREIGN
KEY(activation_id) REFERENCES student_academic_activations (id),
        CONSTRAINT fk_student_academic_documents_requirement_revision_id_a_8f64 FOREIGN
KEY(requirement_revision_id) REFERENCES academic_requirement_revisions (id)
)

;


CREATE TABLE student_academic_responses (
	id UUID NOT NULL,
	owner_id UUID NOT NULL,
	activation_id UUID NOT NULL,
	requirement_revision_id UUID NOT NULL,
	item_id UUID NOT NULL,
	value BOOLEAN,
	previous_value BOOLEAN,
	needs_confirmation BOOLEAN NOT NULL,
	version INTEGER NOT NULL,
	confirmed_at TIMESTAMP WITH TIME ZONE NOT NULL,
	records_json JSONB NOT NULL,
	CONSTRAINT pk_student_academic_responses PRIMARY KEY (id),
        CONSTRAINT uq_student_academic_responses_activation_id UNIQUE (activation_id,
requirement_revision_id, item_id),
        CONSTRAINT fk_student_academic_responses_activation_id_student_aca_6b2e FOREIGN
KEY(activation_id, owner_id) REFERENCES student_academic_activations (id, owner_id),
        CONSTRAINT fk_student_academic_responses_activation_id_student_aca_0815 FOREIGN
KEY(activation_id, requirement_revision_id) REFERENCES student_academic_documents
(activation_id, requirement_revision_id),
	CONSTRAINT ck_student_academic_responses_version CHECK (version >= 1),
        CONSTRAINT fk_student_academic_responses_owner_id_users FOREIGN KEY(owner_id) REFERENCES
 users (id)
)

;

CREATE INDEX ix_student_academic_responses_owner_id ON student_academic_responses (owner_id);
""")


def downgrade():
    op.drop_table("student_academic_responses")
    op.drop_table("student_academic_documents")
    op.drop_table("student_academic_course_links")
    op.drop_table("student_academic_contexts")
    op.drop_table("student_academic_workspaces")
    op.drop_table("student_academic_receipts")
    op.drop_table("student_academic_activations")
