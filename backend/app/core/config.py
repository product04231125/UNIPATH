from enum import StrEnum
from functools import lru_cache
from pathlib import Path

from pydantic import Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy import URL


class Environment(StrEnum):
    LOCAL = "local"
    STAGING = "staging"
    PRODUCTION = "production"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=Path(__file__).resolve().parents[3] / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_env: Environment = Environment.LOCAL
    postgres_host: str = "127.0.0.1"
    postgres_port: int = 5433
    postgres_db: str = "unipath"
    postgres_user: str = "unipath"
    postgres_password: SecretStr
    database_url: SecretStr | None = None
    cors_origins: list[str] = [
        "http://localhost:3000",
        "http://127.0.0.1:3000",
        "http://localhost:5173",
        "http://127.0.0.1:5173",
    ]
    school_rag_corpus_path: Path | None = None
    auth_session_hours: int = Field(default=12, ge=1, le=72)
    # Gemini stays off until all three identifiers are set. Credentials come from ADC.
    vertex_project: str | None = None
    vertex_location: str | None = None
    vertex_model: str | None = None
    vertex_timeout_seconds: int = Field(default=40, ge=5, le=50)
    llm_requests_per_15_minutes: int = Field(default=60, ge=1, le=10_000)

    @field_validator("vertex_project", "vertex_location", "vertex_model", mode="before")
    @classmethod
    def blank_vertex_value_is_unset(cls, value):
        return value or None

    @model_validator(mode="after")
    def validate_local_corpus(self):
        if self.school_rag_corpus_path is not None and self.app_env != Environment.LOCAL:
            raise ValueError("The JSONL school corpus is supported only in the local environment")
        return self

    @model_validator(mode="after")
    def validate_vertex_settings(self):
        values = (self.vertex_project, self.vertex_location, self.vertex_model)
        if any(values) and not all(values):
            raise ValueError("Set VERTEX_PROJECT, VERTEX_LOCATION and VERTEX_MODEL together")
        return self

    @property
    def vertex_configured(self) -> bool:
        return self.vertex_project is not None

    @property
    def resolved_school_corpus_path(self) -> Path | None:
        if self.school_rag_corpus_path is None:
            return None
        if self.school_rag_corpus_path.is_absolute():
            return self.school_rag_corpus_path
        return Path(__file__).resolve().parents[3] / self.school_rag_corpus_path

    @property
    def sqlalchemy_url(self) -> URL | str:
        if self.database_url:
            return self.database_url.get_secret_value()
        return URL.create(
            "postgresql+psycopg",
            username=self.postgres_user,
            password=self.postgres_password.get_secret_value(),
            host=self.postgres_host,
            port=self.postgres_port,
            database=self.postgres_db,
        )


@lru_cache
def get_settings() -> Settings:
    return Settings()
