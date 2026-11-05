"""Identity, opaque sessions and institution-scoped authorization.

Revision ID: 0002_identity_sessions
Revises: 0001_enable_pgvector
"""

from alembic import op

revision = "0002_identity_sessions"
down_revision = "0001_enable_pgvector"
branch_labels = None
depends_on = None


def upgrade():
    op.execute("""
CREATE TABLE auth_throttles (
	bucket VARCHAR(64) NOT NULL,
	window_start TIMESTAMP WITH TIME ZONE NOT NULL,
	attempts INTEGER NOT NULL,
	CONSTRAINT pk_auth_throttles PRIMARY KEY (bucket)
);

CREATE TABLE institutions (
	id UUID NOT NULL,
	name VARCHAR(128) NOT NULL,
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
	CONSTRAINT pk_institutions PRIMARY KEY (id),
	CONSTRAINT uq_institutions_name UNIQUE (name)
);

CREATE TABLE users (
	id UUID NOT NULL,
	email VARCHAR(254) NOT NULL,
	display_name VARCHAR(128) NOT NULL,
	password_hash VARCHAR(512) NOT NULL,
	role VARCHAR(24) NOT NULL,
	account_status VARCHAR(16) NOT NULL,
	version INTEGER NOT NULL,
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
	updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
	CONSTRAINT pk_users PRIMARY KEY (id),
	CONSTRAINT ck_users_role CHECK (role IN ('user', 'school_admin', 'super_admin')),
	CONSTRAINT ck_users_account_status CHECK (account_status IN ('active', 'suspended')),
	CONSTRAINT uq_users_email UNIQUE (email)
);

CREATE TABLE admin_scopes (
	id UUID NOT NULL,
	user_id UUID NOT NULL,
	institution_id UUID NOT NULL,
	status VARCHAR(16) NOT NULL,
	version INTEGER NOT NULL,
	reason VARCHAR(500) NOT NULL,
	granted_by UUID NOT NULL,
	granted_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
	revoked_by UUID,
	revoked_at TIMESTAMP WITH TIME ZONE,
	CONSTRAINT pk_admin_scopes PRIMARY KEY (id),
	CONSTRAINT ck_admin_scopes_status CHECK (status IN ('active', 'revoked')),
        CONSTRAINT fk_admin_scopes_user_id_users FOREIGN KEY(user_id) REFERENCES users (id) ON
DELETE CASCADE,
        CONSTRAINT fk_admin_scopes_institution_id_institutions FOREIGN KEY(institution_id)
REFERENCES institutions (id),
	CONSTRAINT fk_admin_scopes_granted_by_users FOREIGN KEY(granted_by) REFERENCES users (id),
	CONSTRAINT fk_admin_scopes_revoked_by_users FOREIGN KEY(revoked_by) REFERENCES users (id)
);

CREATE INDEX ix_admin_scopes_institution_id ON admin_scopes (institution_id);

CREATE INDEX ix_admin_scopes_user_id ON admin_scopes (user_id);

CREATE UNIQUE INDEX uq_admin_scopes_active ON admin_scopes (user_id, institution_id) WHERE
status = 'active';

CREATE TABLE auth_sessions (
	token_hash VARCHAR(64) NOT NULL,
	user_id UUID NOT NULL,
	mode VARCHAR(8) NOT NULL,
	created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
	expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
	revoked_at TIMESTAMP WITH TIME ZONE,
	CONSTRAINT pk_auth_sessions PRIMARY KEY (token_hash),
	CONSTRAINT ck_auth_sessions_mode CHECK (mode IN ('cookie', 'bearer')),
        CONSTRAINT fk_auth_sessions_user_id_users FOREIGN KEY(user_id) REFERENCES users (id) ON
DELETE CASCADE
);

CREATE INDEX ix_auth_sessions_expires_at ON auth_sessions (expires_at);

CREATE INDEX ix_auth_sessions_user_id ON auth_sessions (user_id);

CREATE TABLE identity_audits (
	id UUID NOT NULL,
	actor_id UUID,
	action VARCHAR(40) NOT NULL,
	target_id UUID NOT NULL,
	institution_id UUID,
	request_id UUID,
	occurred_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
	CONSTRAINT pk_identity_audits PRIMARY KEY (id),
        CONSTRAINT fk_identity_audits_actor_id_users FOREIGN KEY(actor_id) REFERENCES users (id)
ON DELETE SET NULL,
        CONSTRAINT fk_identity_audits_institution_id_institutions FOREIGN KEY(institution_id)
REFERENCES institutions (id)
);

CREATE INDEX ix_identity_audits_target_id ON identity_audits (target_id);
    """)


def downgrade():
    for table in (
        "identity_audits",
        "admin_scopes",
        "institutions",
        "auth_throttles",
        "auth_sessions",
        "users",
    ):
        op.execute(f"DROP TABLE {table}")
