from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.schemas.health import HealthStatus, ReadyResponse


class NotReadyError(Exception):
    pass


def check_database(session: Session) -> ReadyResponse:
    try:
        version = session.scalar(text("SELECT extversion FROM pg_extension WHERE extname='vector'"))
        revision = session.scalar(text("SELECT version_num FROM alembic_version"))
        if not version or not revision:
            raise NotReadyError
    except SQLAlchemyError:
        raise NotReadyError from None
    return ReadyResponse(
        status=HealthStatus.READY,
        database=HealthStatus.OK,
        pgvector_version=version,
        migration_revision=revision,
    )
