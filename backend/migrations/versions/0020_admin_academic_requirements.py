"""Persist the three administrator graduation editors, leaving students unchanged.

Revision ID: 0020_admin_academic_requirements
Revises: 0019_admin_academic_curricula
"""

from alembic import op

revision = "0020_admin_academic_requirements"
down_revision = "0019_admin_academic_curricula"
branch_labels = None
depends_on = None


def upgrade():
    op.execute(r"""
CREATE TABLE academic_requirement_revisions (
	id UUID NOT NULL,
	institution_id UUID NOT NULL,
	lineage_id UUID NOT NULL,
	revision INTEGER NOT NULL,
	version INTEGER NOT NULL,
	name VARCHAR(128) NOT NULL,
	effective_from DATE,
	effective_to DATE,
	kind VARCHAR(24) NOT NULL,
	scope_json JSONB NOT NULL,
	content_json JSONB NOT NULL,
	classification_revision_id UUID,
	curriculum_revision_id UUID,
	legacy_rule_id UUID,
	legacy_rule_version INTEGER,
	status VARCHAR(16) NOT NULL,
	digest VARCHAR(64),
	review_note VARCHAR(1000) NOT NULL,
	published_at TIMESTAMP WITH TIME ZONE,
	published_by UUID,
	withdrawn_at TIMESTAMP WITH TIME ZONE,
	withdrawal_reason VARCHAR(1000),
	created_by UUID NOT NULL,
	updated_by UUID NOT NULL,
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
	CONSTRAINT pk_academic_requirement_revisions PRIMARY KEY (id),
	CONSTRAINT uq_academic_requirement_revisions_id UNIQUE (id, institution_id),
	CONSTRAINT uq_ac_req_class UNIQUE (id, classification_revision_id, institution_id),
	CONSTRAINT uq_academic_requirement_revisions_lineage_id UNIQUE (lineage_id, revision),
        CONSTRAINT fk_academic_requirement_revisions_classification_revisi_2e49 FOREIGN
KEY(classification_revision_id, institution_id) REFERENCES academic_classification_revisions
(id, institution_id),
        CONSTRAINT fk_academic_requirement_revisions_curriculum_revision_i_8dfd FOREIGN
KEY(curriculum_revision_id, institution_id) REFERENCES academic_curriculum_revisions (id,
institution_id),
        CONSTRAINT fk_academic_requirement_revisions_legacy_rule_id_gradua_c079 FOREIGN
KEY(legacy_rule_id, institution_id) REFERENCES graduation_rules (id, institution_id),
	CONSTRAINT ck_academic_requirement_revisions_versions CHECK (version >= 1 AND revision >= 1),
        CONSTRAINT ck_academic_requirement_revisions_kind CHECK (kind IN
('checklist','certification','credit_table')),
        CONSTRAINT ck_academic_requirement_revisions_status CHECK (status IN
('draft','published','withdrawn')),
        CONSTRAINT ck_academic_requirement_revisions_period CHECK (effective_from IS NULL OR
effective_to IS NULL OR effective_from <= effective_to),
        CONSTRAINT ck_academic_requirement_revisions_content CHECK (jsonb_typeof(scope_json) =
'object' AND jsonb_typeof(content_json) = 'object' AND coalesce(content_json->>'kind' = kind,
false)),
        CONSTRAINT ck_academic_requirement_revisions_publication CHECK ((status='draft' AND
published_at IS NULL AND published_by IS NULL AND digest IS NULL) OR (status<>'draft' AND
published_at IS NOT NULL AND published_by IS NOT NULL AND digest IS NOT NULL)),
        CONSTRAINT ck_academic_requirement_revisions_withdrawal CHECK ((status='withdrawn' AND
withdrawn_at IS NOT NULL AND withdrawal_reason IS NOT NULL AND length(trim(withdrawal_reason)) >
0) OR (status<>'withdrawn' AND withdrawn_at IS NULL AND withdrawal_reason IS NULL)),
        CONSTRAINT fk_academic_requirement_revisions_institution_id_institutions FOREIGN
KEY(institution_id) REFERENCES institutions (id),
        CONSTRAINT fk_academic_requirement_revisions_published_by_users FOREIGN
KEY(published_by) REFERENCES users (id),
        CONSTRAINT fk_academic_requirement_revisions_created_by_users FOREIGN KEY(created_by)
REFERENCES users (id),
        CONSTRAINT fk_academic_requirement_revisions_updated_by_users FOREIGN KEY(updated_by)
REFERENCES users (id)
);

CREATE INDEX ix_academic_requirement_revisions_institution_id ON academic_requirement_revisions
(institution_id);

CREATE INDEX ix_academic_requirement_revisions_lineage_id ON academic_requirement_revisions
(lineage_id);

CREATE UNIQUE INDEX uq_academic_requirement_draft ON academic_requirement_revisions (lineage_id)
WHERE status = 'draft';

CREATE TABLE academic_requirement_department_refs (
	requirement_revision_id UUID NOT NULL,
	department_id UUID NOT NULL,
	institution_id UUID NOT NULL,
        CONSTRAINT pk_academic_requirement_department_refs PRIMARY KEY (requirement_revision_id,
department_id),
        CONSTRAINT fk_academic_requirement_department_refs_requirement_rev_e73f FOREIGN
KEY(requirement_revision_id, institution_id) REFERENCES academic_requirement_revisions (id,
institution_id) ON DELETE CASCADE,
        CONSTRAINT fk_academic_requirement_department_refs_department_id_d_eb9b FOREIGN
KEY(department_id, institution_id) REFERENCES departments (id, institution_id)
);

CREATE TABLE academic_requirement_node_refs (
	requirement_revision_id UUID NOT NULL,
	node_id UUID NOT NULL,
	institution_id UUID NOT NULL,
	classification_revision_id UUID NOT NULL,
	CONSTRAINT pk_academic_requirement_node_refs PRIMARY KEY (requirement_revision_id, node_id),
        CONSTRAINT fk_academic_requirement_node_refs_requirement_revision__a871 FOREIGN
KEY(requirement_revision_id, classification_revision_id, institution_id) REFERENCES
academic_requirement_revisions (id, classification_revision_id, institution_id) ON DELETE
CASCADE,
        CONSTRAINT fk_academic_requirement_node_refs_node_id_academic_clas_ae4c FOREIGN
KEY(node_id, classification_revision_id, institution_id) REFERENCES
academic_classification_nodes (id, revision_id, institution_id)
);

CREATE TABLE academic_requirement_track_refs (
	requirement_revision_id UUID NOT NULL,
	track_id UUID NOT NULL,
	institution_id UUID NOT NULL,
	CONSTRAINT pk_academic_requirement_track_refs PRIMARY KEY (requirement_revision_id, track_id),
        CONSTRAINT fk_academic_requirement_track_refs_requirement_revision_e866 FOREIGN
KEY(requirement_revision_id, institution_id) REFERENCES academic_requirement_revisions (id,
institution_id) ON DELETE CASCADE,
        CONSTRAINT fk_academic_requirement_track_refs_track_id_academic_st_25d3 FOREIGN
KEY(track_id, institution_id) REFERENCES academic_study_tracks (id, institution_id)
);
""")


def downgrade():
    op.drop_table("academic_requirement_track_refs")
    op.drop_table("academic_requirement_node_refs")
    op.drop_table("academic_requirement_department_refs")
    op.drop_table("academic_requirement_revisions")
