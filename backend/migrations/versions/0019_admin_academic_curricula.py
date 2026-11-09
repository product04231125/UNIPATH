"""Add curriculum-specific course classifications without rewriting legacy records.

Revision ID: 0019_admin_academic_curricula
Revises: 0018_admin_academic_foundation
"""

from alembic import op

revision = "0019_admin_academic_curricula"
down_revision = "0018_admin_academic_foundation"
branch_labels = None
depends_on = None


def upgrade():
    op.execute(r"""
CREATE TABLE academic_curriculum_revisions (
	id UUID NOT NULL,
	institution_id UUID NOT NULL,
	lineage_id UUID NOT NULL,
	legacy_curriculum_id UUID,
	classification_revision_id UUID NOT NULL,
	revision INTEGER NOT NULL,
	version INTEGER NOT NULL,
	name VARCHAR(128) NOT NULL,
	curriculum_year INTEGER,
	scope_json JSONB NOT NULL,
	status VARCHAR(16) NOT NULL,
	digest VARCHAR(64),
	review_note VARCHAR(1000) NOT NULL,
	published_at TIMESTAMP WITH TIME ZONE,
	published_by UUID,
	created_by UUID NOT NULL,
	updated_by UUID NOT NULL,
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
	CONSTRAINT pk_academic_curriculum_revisions PRIMARY KEY (id),
	CONSTRAINT uq_academic_curriculum_revisions_id UNIQUE (id, institution_id),
	CONSTRAINT uq_ac_cur_class UNIQUE (id, classification_revision_id, institution_id),
	CONSTRAINT uq_academic_curriculum_revisions_lineage_id UNIQUE (lineage_id, revision),
        CONSTRAINT fk_academic_curriculum_revisions_legacy_curriculum_id_curricula FOREIGN
KEY(legacy_curriculum_id, institution_id) REFERENCES curricula (id, institution_id),
        CONSTRAINT fk_academic_curriculum_revisions_classification_revisio_21a2 FOREIGN
KEY(classification_revision_id, institution_id) REFERENCES academic_classification_revisions
(id, institution_id),
	CONSTRAINT ck_academic_curriculum_revisions_versions CHECK (version >= 1 AND revision >= 1),
        CONSTRAINT ck_academic_curriculum_revisions_status CHECK (status IN
('draft','published','withdrawn')),
        CONSTRAINT ck_academic_curriculum_revisions_year CHECK (curriculum_year IS NULL OR
curriculum_year BETWEEN 1000 AND 9999),
	CONSTRAINT ck_academic_curriculum_revisions_scope CHECK (jsonb_typeof(scope_json) = 'object'),
        CONSTRAINT fk_academic_curriculum_revisions_institution_id_institutions FOREIGN
KEY(institution_id) REFERENCES institutions (id),
        CONSTRAINT fk_academic_curriculum_revisions_published_by_users FOREIGN KEY(published_by)
REFERENCES users (id),
        CONSTRAINT fk_academic_curriculum_revisions_created_by_users FOREIGN KEY(created_by)
REFERENCES users (id),
        CONSTRAINT fk_academic_curriculum_revisions_updated_by_users FOREIGN KEY(updated_by)
REFERENCES users (id)
);

CREATE INDEX ix_academic_curriculum_revisions_institution_id ON academic_curriculum_revisions
(institution_id);

CREATE INDEX ix_academic_curriculum_revisions_lineage_id ON academic_curriculum_revisions
(lineage_id);

CREATE UNIQUE INDEX uq_academic_curriculum_draft ON academic_curriculum_revisions (lineage_id)
WHERE status = 'draft';

CREATE TABLE academic_curriculum_courses (
	id UUID NOT NULL,
	logical_id UUID NOT NULL,
	institution_id UUID NOT NULL,
	curriculum_revision_id UUID NOT NULL,
	classification_revision_id UUID NOT NULL,
	course_id UUID NOT NULL,
	course_version INTEGER NOT NULL,
	course_name VARCHAR(128) NOT NULL,
	course_code VARCHAR(64) NOT NULL,
	classification_node_id UUID NOT NULL,
	requirement VARCHAR(20) NOT NULL,
	recognized_credits NUMERIC(8, 3) NOT NULL,
	position INTEGER NOT NULL,
	CONSTRAINT pk_academic_curriculum_courses PRIMARY KEY (id),
	CONSTRAINT uq_academic_curriculum_courses_id UNIQUE (id, institution_id),
        CONSTRAINT uq_academic_curriculum_courses_curriculum_revision_id UNIQUE
(curriculum_revision_id, course_id),
	CONSTRAINT uq_ac_cur_course_logical UNIQUE (curriculum_revision_id, logical_id),
	CONSTRAINT uq_ac_cur_course_position UNIQUE (curriculum_revision_id, position),
        CONSTRAINT fk_academic_curriculum_courses_curriculum_revision_id_a_f478 FOREIGN
KEY(curriculum_revision_id, classification_revision_id, institution_id) REFERENCES
academic_curriculum_revisions (id, classification_revision_id, institution_id) ON DELETE
CASCADE,
        CONSTRAINT fk_academic_curriculum_courses_course_id_courses FOREIGN KEY(course_id,
institution_id) REFERENCES courses (id, institution_id),
        CONSTRAINT fk_academic_curriculum_courses_classification_node_id_a_a87d FOREIGN
KEY(classification_node_id, classification_revision_id, institution_id) REFERENCES
academic_classification_nodes (id, revision_id, institution_id),
        CONSTRAINT ck_academic_curriculum_courses_versions CHECK (course_version >= 1 AND
position >= 0),
        CONSTRAINT ck_academic_curriculum_courses_credits CHECK (recognized_credits >= 0 AND
recognized_credits <= 100),
        CONSTRAINT ck_academic_curriculum_courses_requirement CHECK (requirement IN
('required','elective','not_specified'))
);

CREATE INDEX ix_academic_curriculum_courses_curriculum_revision_id ON
academic_curriculum_courses (curriculum_revision_id);

CREATE TABLE academic_curriculum_department_refs (
	curriculum_revision_id UUID NOT NULL,
	department_id UUID NOT NULL,
	institution_id UUID NOT NULL,
        CONSTRAINT pk_academic_curriculum_department_refs PRIMARY KEY (curriculum_revision_id,
department_id),
        CONSTRAINT fk_academic_curriculum_department_refs_curriculum_revis_8eb9 FOREIGN
KEY(curriculum_revision_id, institution_id) REFERENCES academic_curriculum_revisions (id,
institution_id) ON DELETE CASCADE,
        CONSTRAINT fk_academic_curriculum_department_refs_department_id_de_3097 FOREIGN
KEY(department_id, institution_id) REFERENCES departments (id, institution_id)
);

CREATE TABLE academic_curriculum_track_refs (
	curriculum_revision_id UUID NOT NULL,
	track_id UUID NOT NULL,
	institution_id UUID NOT NULL,
	CONSTRAINT pk_academic_curriculum_track_refs PRIMARY KEY (curriculum_revision_id, track_id),
        CONSTRAINT fk_academic_curriculum_track_refs_curriculum_revision_i_72de FOREIGN
KEY(curriculum_revision_id, institution_id) REFERENCES academic_curriculum_revisions (id,
institution_id) ON DELETE CASCADE,
        CONSTRAINT fk_academic_curriculum_track_refs_track_id_academic_stu_1769 FOREIGN
KEY(track_id, institution_id) REFERENCES academic_study_tracks (id, institution_id)
);
""")


def downgrade():
    op.drop_table("academic_curriculum_track_refs")
    op.drop_table("academic_curriculum_department_refs")
    op.drop_table("academic_curriculum_courses")
    op.drop_table("academic_curriculum_revisions")
