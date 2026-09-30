"""Enable pgvector without fixing the pending domain schema.

Revision ID: 0001_enable_pgvector
"""

from alembic import op

revision = "0001_enable_pgvector"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS vector")


def downgrade() -> None:
    # Leave a shared extension intact; later migrations may store vector columns.
    pass
