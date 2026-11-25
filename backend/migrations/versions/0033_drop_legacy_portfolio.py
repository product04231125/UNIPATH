"""Drop the old portfolio compositions and application documents (no screen used them).

The 포트폴리오 구성 and 자기소개서·포트폴리오 drafts now live in writing requests and
`writing_documents`. Import receipts drop their mappings to the removed resources, and creation
receipts for them go too. Downgrade restores the empty tables only.

Revision ID: 0033_drop_legacy_portfolio
Revises: 0032_event_completion
"""

from collections.abc import Sequence

from alembic import op

revision: str = "0033_drop_legacy_portfolio"
down_revision: str | Sequence[str] | None = "0032_event_completion"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

LEGACY = "('portfolio-compositions', 'application-documents')"


def upgrade() -> None:
    op.execute(f"DELETE FROM personal_creation_receipts WHERE resource IN {LEGACY}")
    # Keep each import receipt replayable: drop mappings to the removed resources. A receipt
    # left with nothing (no records, no profile) has nothing to replay and goes.
    op.execute(
        f"""
        UPDATE personal_import_receipts r
        SET mappings_json = kept.mappings, record_count = jsonb_array_length(kept.mappings)
        FROM (
            SELECT owner_id, import_id,
                   COALESCE(
                       jsonb_agg(m) FILTER (WHERE m->>'resource' NOT IN {LEGACY}), '[]'::jsonb
                   ) AS mappings
            FROM personal_import_receipts, jsonb_array_elements(mappings_json) AS m
            GROUP BY owner_id, import_id
        ) kept
        WHERE r.owner_id = kept.owner_id AND r.import_id = kept.import_id
          AND r.record_count <> jsonb_array_length(kept.mappings)
          AND (jsonb_array_length(kept.mappings) > 0 OR r.profile_version IS NOT NULL)
        """
    )
    op.execute(
        f"""
        DELETE FROM personal_import_receipts r
        WHERE r.profile_version IS NULL AND NOT EXISTS (
            SELECT 1 FROM jsonb_array_elements(r.mappings_json) AS m
            WHERE m->>'resource' NOT IN {LEGACY}
        )
        """
    )
    for table in (
        "application_document_sources",
        "portfolio_sources",
        "application_documents",
        "portfolio_compositions",
    ):
        op.drop_table(table)


def downgrade() -> None:
    op.execute(
        """
        CREATE TABLE application_documents ( target VARCHAR(128) NOT NULL, role VARCHAR(128) NOT
        NULL, document_type VARCHAR(128) NOT NULL, body TEXT NOT NULL, id UUID NOT NULL, owner_id
        UUID NOT NULL, client_id UUID, title VARCHAR(128) NOT NULL, detail TEXT NOT NULL, version
        INTEGER NOT NULL, created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, updated_at
        TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL, CONSTRAINT pk_application_documents
        PRIMARY KEY (id), CONSTRAINT fk_application_documents_owner_id_users FOREIGN KEY(owner_id)
        REFERENCES users (id), CONSTRAINT uq_application_documents_id UNIQUE (id, owner_id),
        CONSTRAINT uq_application_documents_owner_id UNIQUE (owner_id, client_id), CONSTRAINT
        ck_application_documents_version CHECK (version >= 1) )
        """
    )
    op.execute(
        """
        CREATE INDEX ix_application_documents_owner_id ON application_documents (owner_id)
        """
    )
    op.execute(
        """
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
        """
    )
    op.execute(
        """
        CREATE INDEX ix_portfolio_compositions_owner_id ON portfolio_compositions (owner_id)
        """
    )
    op.execute(
        """
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
        """
    )
    op.execute(
        """
        CREATE TABLE portfolio_sources ( composition_id UUID NOT NULL, owner_id UUID NOT NULL,
        position INTEGER NOT NULL, achievement_id UUID NOT NULL, CONSTRAINT pk_portfolio_sources
        PRIMARY KEY (composition_id, position), CONSTRAINT uq_portfolio_sources_composition_id
        UNIQUE (composition_id, achievement_id), CONSTRAINT ck_portfolio_sources_position CHECK
        (position >= 0), CONSTRAINT fk_portfolio_sources_composition_id_portfolio_compositions
        FOREIGN KEY(composition_id, owner_id) REFERENCES portfolio_compositions (id, owner_id) ON
        DELETE CASCADE, CONSTRAINT fk_portfolio_sources_achievement_id_personal_achievemen_07ed
        FOREIGN KEY(achievement_id, owner_id) REFERENCES personal_achievement_records (id,
        owner_id) )
        """
    )
