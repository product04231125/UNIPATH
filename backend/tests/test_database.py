import os

import pytest
from sqlalchemy import create_engine, text

from app.core.config import Settings

pytestmark = [
    pytest.mark.integration,
    pytest.mark.skipif(
        os.getenv("RUN_DB_TESTS") != "1", reason="Set RUN_DB_TESTS=1 for PostgreSQL"
    ),
]


def test_migration_and_vector_distance_on_postgresql():
    engine = create_engine(Settings().sqlalchemy_url, hide_parameters=True)
    try:
        with engine.begin() as connection:
            assert connection.scalar(text("SELECT version_num FROM alembic_version"))
            assert connection.scalar(
                text("SELECT extversion FROM pg_extension WHERE extname='vector'")
            )
            # Synthetic vectors in a temporary table leave no domain data behind.
            connection.execute(
                text("CREATE TEMP TABLE test_vectors (id int, embedding vector(3)) ON COMMIT DROP")
            )
            connection.execute(
                text("INSERT INTO test_vectors VALUES (1, '[1,0,0]'), (2, '[0,1,0]')")
            )
            nearest = connection.scalar(
                text("SELECT id FROM test_vectors ORDER BY embedding <-> '[1,0,0]' LIMIT 1")
            )
            assert nearest == 1
    finally:
        engine.dispose()
