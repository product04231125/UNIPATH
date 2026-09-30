import os

import pytest
from fastapi.testclient import TestClient

# Unit tests override DB calls; integration tests must preserve actual local settings.
if os.getenv("RUN_DB_TESTS") != "1":
    os.environ.setdefault("POSTGRES_PASSWORD", "synthetic-test-password")

from app.core.config import Settings  # noqa: E402
from app.main import create_app  # noqa: E402


@pytest.fixture
def client():
    settings = Settings(_env_file=None, postgres_password="synthetic-test-password")
    with TestClient(create_app(settings), raise_server_exceptions=False) as test_client:
        yield test_client
