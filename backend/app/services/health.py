from pathlib import Path

from alembic.script import ScriptDirectory
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.schemas.health import HealthStatus, ReadyResponse

EXPECTED_REVISION = ScriptDirectory(
    str(Path(__file__).resolve().parents[2] / "migrations")
).get_current_head()


class NotReadyError(Exception):
    pass


def check_database(session: Session) -> ReadyResponse:
    try:
        version = session.scalar(text("SELECT extversion FROM pg_extension WHERE extname='vector'"))
        revision = session.scalar(text("SELECT version_num FROM alembic_version"))
        if not version or revision != EXPECTED_REVISION:
            raise NotReadyError
    except SQLAlchemyError:
        raise NotReadyError from None
    return ReadyResponse(
        status=HealthStatus.READY,
        database=HealthStatus.OK,
        pgvector_version=version,
        migration_revision=revision,
    )
