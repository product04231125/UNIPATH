from enum import StrEnum
from functools import lru_cache
from pathlib import Path

from pydantic import Field, SecretStr, model_validator
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
    cors_origins: list[str] = ["http://localhost:3000", "http://localhost:5173"]
    school_rag_corpus_path: Path | None = None
    auth_session_hours: int = Field(default=12, ge=1, le=72)

    @model_validator(mode="after")
    def validate_local_corpus(self):
        if self.school_rag_corpus_path is not None and self.app_env != Environment.LOCAL:
            raise ValueError("The JSONL school corpus is supported only in the local environment")
        return self

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
