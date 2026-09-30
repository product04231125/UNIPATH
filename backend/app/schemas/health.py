from enum import StrEnum

from pydantic import BaseModel


class HealthStatus(StrEnum):
    OK = "ok"
    READY = "ready"


class HealthResponse(BaseModel):
    status: HealthStatus


class ReadyResponse(HealthResponse):
    database: HealthStatus
    pgvector_version: str
    migration_revision: str
