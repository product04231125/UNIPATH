import json
from pathlib import Path

from app.core.config import Settings
from app.main import create_app


def test_published_openapi_matches_live_contract():
    published = Path(__file__).resolve().parents[2] / "docs/api/openapi.json"
    settings = Settings(_env_file=None, postgres_password="synthetic-test-password")
    assert json.loads(published.read_text()) == create_app(settings).openapi()
