"""Persist administrator school classifications without changing student data.

Revision ID: 0015_admin_academic_foundation
Revises: 0014_school_admin_signups
"""

from alembic import op

revision = "0015_admin_academic_foundation"
down_revision = "0014_school_admin_signups"
branch_labels = None
depends_on = None


def upgrade():
    op.execute(r"""
CREATE TABLE academic_classification_revisions (
	id UUID NOT NULL,
	institution_id UUID NOT NULL,
	revision INTEGER NOT NULL,
	version INTEGER NOT NULL,
	status VARCHAR(16) NOT NULL,
	published_at TIMESTAMP WITH TIME ZONE,
	published_by UUID,
	digest VARCHAR(64),
	review_note VARCHAR(1000) NOT NULL,
	created_by UUID NOT NULL,
	updated_by UUID NOT NULL,
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
	CONSTRAINT pk_academic_classification_revisions PRIMARY KEY (id),
	CONSTRAINT uq_academic_classification_revisions_id UNIQUE (id, institution_id),
        CONSTRAINT uq_academic_classification_revisions_institution_id UNIQUE (institution_id,
revision),
        CONSTRAINT ck_academic_classification_revisions_versions CHECK (revision >= 1 AND
version >= 1),
        CONSTRAINT ck_academic_classification_revisions_status CHECK (status IN
('draft','published','withdrawn')),
        CONSTRAINT ck_academic_classification_revisions_publication CHECK ((status = 'draft' AND
published_at IS NULL AND published_by IS NULL AND digest IS NULL) OR (status <> 'draft' AND
published_at IS NOT NULL AND published_by IS NOT NULL AND digest IS NOT NULL)),
        CONSTRAINT fk_academic_classification_revisions_institution_id_ins_00ac FOREIGN
KEY(institution_id) REFERENCES institutions (id),
        CONSTRAINT fk_academic_classification_revisions_published_by_users FOREIGN
KEY(published_by) REFERENCES users (id),
        CONSTRAINT fk_academic_classification_revisions_created_by_users FOREIGN KEY(created_by)
REFERENCES users (id),
        CONSTRAINT fk_academic_classification_revisions_updated_by_users FOREIGN KEY(updated_by)
REFERENCES users (id)
);

CREATE INDEX ix_academic_classification_revisions_institution_id ON
academic_classification_revisions (institution_id);

CREATE UNIQUE INDEX uq_academic_classifications_draft ON academic_classification_revisions
(institution_id) WHERE status = 'draft';

CREATE TABLE academic_mutation_receipts (
	actor_id UUID NOT NULL,
	client_id UUID NOT NULL,
	institution_id UUID NOT NULL,
	operation VARCHAR(128) NOT NULL,
	request_digest VARCHAR(64) NOT NULL,
	response_json JSONB NOT NULL,
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
	CONSTRAINT pk_academic_mutation_receipts PRIMARY KEY (actor_id, client_id),
	CONSTRAINT ck_academic_mutation_receipts_digest CHECK (request_digest ~ '^[0-9a-f]{64}$'),
        CONSTRAINT ck_academic_mutation_receipts_response CHECK (jsonb_typeof(response_json) =
'object'),
        CONSTRAINT fk_academic_mutation_receipts_actor_id_users FOREIGN KEY(actor_id) REFERENCES
users (id),
        CONSTRAINT fk_academic_mutation_receipts_institution_id_institutions FOREIGN
KEY(institution_id) REFERENCES institutions (id)
);

CREATE TABLE academic_study_tracks (
	id UUID NOT NULL,
	institution_id UUID NOT NULL,
	name VARCHAR(128) NOT NULL,
	version INTEGER NOT NULL,
	inactive_at TIMESTAMP WITH TIME ZONE,
	created_by UUID NOT NULL,
	updated_by UUID NOT NULL,
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
	CONSTRAINT pk_academic_study_tracks PRIMARY KEY (id),
	CONSTRAINT uq_academic_study_tracks_id UNIQUE (id, institution_id),
	CONSTRAINT ck_academic_study_tracks_version CHECK (version >= 1),
	CONSTRAINT ck_academic_study_tracks_name CHECK (length(trim(name)) > 0),
        CONSTRAINT fk_academic_study_tracks_institution_id_institutions FOREIGN
KEY(institution_id) REFERENCES institutions (id),
        CONSTRAINT fk_academic_study_tracks_created_by_users FOREIGN KEY(created_by) REFERENCES
users (id),
        CONSTRAINT fk_academic_study_tracks_updated_by_users FOREIGN KEY(updated_by) REFERENCES
users (id)
);

CREATE INDEX ix_academic_study_tracks_institution_id ON academic_study_tracks (institution_id);

CREATE TABLE academic_classification_nodes (
	id UUID NOT NULL,
	institution_id UUID NOT NULL,
	revision_id UUID NOT NULL,
	logical_id UUID NOT NULL,
	parent_id UUID,
	label VARCHAR(128) NOT NULL,
	position INTEGER NOT NULL,
	selectable BOOLEAN NOT NULL,
	CONSTRAINT pk_academic_classification_nodes PRIMARY KEY (id),
	CONSTRAINT uq_academic_node_revision UNIQUE (id, revision_id, institution_id),
	CONSTRAINT uq_academic_classification_nodes_id UNIQUE (id, institution_id),
	CONSTRAINT uq_academic_classification_nodes_revision_id UNIQUE (revision_id, logical_id),
        CONSTRAINT fk_academic_classification_nodes_revision_id_academic_c_651b FOREIGN
KEY(revision_id, institution_id) REFERENCES academic_classification_revisions (id,
institution_id) ON DELETE CASCADE,
        CONSTRAINT fk_academic_classification_nodes_parent_id_academic_cla_7e70 FOREIGN
KEY(parent_id, revision_id, institution_id) REFERENCES academic_classification_nodes (id,
revision_id, institution_id) DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT ck_academic_classification_nodes_position CHECK (position >= 0),
        CONSTRAINT ck_academic_classification_nodes_parent CHECK (parent_id IS NULL OR parent_id
<> id),
	CONSTRAINT ck_academic_classification_nodes_label CHECK (length(trim(label)) > 0)
);

CREATE INDEX ix_academic_classification_nodes_revision_id ON academic_classification_nodes
(revision_id);

CREATE UNIQUE INDEX uq_academic_node_child_position ON academic_classification_nodes
(revision_id, parent_id, position) WHERE parent_id IS NOT NULL;

CREATE UNIQUE INDEX uq_academic_node_root_position ON academic_classification_nodes
(revision_id, position) WHERE parent_id IS NULL;
""")


def downgrade():
    op.drop_table("academic_classification_nodes")
    op.drop_table("academic_study_tracks")
    op.drop_table("academic_mutation_receipts")
    op.drop_table("academic_classification_revisions")
