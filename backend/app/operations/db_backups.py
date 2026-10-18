"""Read-only PostgreSQL backups and verification in a disposable database."""

import argparse
import hashlib
import json
import os
import re
import secrets
import subprocess
import tempfile
import time
from contextlib import contextmanager
from datetime import UTC, datetime
from pathlib import Path
from typing import Literal
from uuid import UUID, uuid4

import psycopg
from psycopg import sql
from pydantic import BaseModel, ConfigDict, Field

from app.core.config import Environment, Settings

ROOT = Path(__file__).resolve().parents[3]
BACKUPS = ROOT / "backups"
IMAGE_PATTERN = r"^pgvector/pgvector:[A-Za-z0-9._-]+@sha256:[a-f0-9]{64}$"


class BackupError(Exception):
    """A safe, fixed diagnostic with no SQL, credentials, or record contents."""


class BackupSettings(Settings):
    @classmethod
    def settings_customise_sources(
        cls, settings_cls, init_settings, env_settings, dotenv_settings, file_secret_settings
    ):
        # Shell variables must not silently redirect a staging backup to another DB.
        return init_settings, dotenv_settings


class Manifest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    format_version: Literal[1] = 1
    backup_id: UUID
    environment: Environment
    created_at: datetime
    source_commit: str = Field(pattern=r"^[a-f0-9]{40}$")
    worktree_dirty: bool | None = Field(default=None, strict=True)
    postgres_major: Literal[17]
    image: str = Field(pattern=IMAGE_PATTERN)
    dump_file: Literal["database.dump"] = "database.dump"
    dump_sha256: str = Field(pattern=r"^[a-f0-9]{64}$")
    dump_bytes: int = Field(gt=0)
    inventory: dict


def _run(args, *, stdout=subprocess.PIPE, stdin=None, env=None, timeout=180):
    try:
        return subprocess.run(
            args,
            check=True,
            stdin=stdin,
            stdout=stdout,
            stderr=subprocess.PIPE,
            env=env,
            timeout=timeout,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        raise BackupError("Operational command failed; no data was overwritten") from None


def _inspect(container: str, template: str):
    return json.loads(_run(["docker", "inspect", "--format", template, container]))


def connect(settings: Settings):
    return psycopg.connect(
        host=settings.postgres_host,
        port=settings.postgres_port,
        dbname=settings.postgres_db,
        user=settings.postgres_user,
        password=settings.postgres_password.get_secret_value(),
        connect_timeout=3,
        options="-c statement_timeout=120000 -c lock_timeout=10000",
    )


def source(environment: Environment) -> tuple[str, str, Settings]:
    project, env_name = {
        Environment.LOCAL: ("unipath", ".env"),
        Environment.STAGING: ("unipath-staging", ".env.staging"),
        Environment.PRODUCTION: ("unipath-product", ".env.production"),
    }[environment]
    env_file = ROOT / env_name
    if not env_file.is_file():
        raise BackupError("The selected environment file does not exist")
    settings = BackupSettings(_env_file=env_file)
    if settings.app_env != environment or settings.database_url is not None:
        raise BackupError("Environment or external database configuration does not match")
    if settings.postgres_host not in ("127.0.0.1", "localhost"):
        raise BackupError("Only the selected loopback Compose database is supported")
    args = [
        "docker",
        "compose",
        "-p",
        project,
        "--env-file",
        str(env_file),
        "-f",
        str(ROOT / "compose.yaml"),
        "ps",
        "-q",
        "db",
    ]
    environment_vars = {
        k: v
        for k, v in os.environ.items()
        if not k.startswith("POSTGRES_")
        and k not in {"APP_ENV", "DATABASE_URL", "COMPOSE_ENV_FILES"}
    }
    container = _run(args, env=environment_vars).decode().strip()
    if not container or "\n" in container:
        raise BackupError("Exactly one selected database container must be running")
    labels = _inspect(container, "{{json .Config.Labels}}")
    if labels.get("com.docker.compose.project") != project:
        raise BackupError("Database container belongs to a different environment")
    ports = _inspect(container, "{{json .NetworkSettings.Ports}}")
    if not any(
        p["HostIp"] == "127.0.0.1" and int(p["HostPort"]) == settings.postgres_port
        for p in ports.get("5432/tcp") or []
    ):
        raise BackupError("Configured loopback database port does not match its container")
    identity = _run(["docker", "exec", container, "printenv", "POSTGRES_DB", "POSTGRES_USER"])
    if identity.decode().splitlines() != [settings.postgres_db, settings.postgres_user]:
        raise BackupError("Configured database identity does not match its container")
    image = _inspect(container, "{{json .Config.Image}}")
    return container, image, settings


def inventory(connection) -> dict:
    """Schema, row counts and order-independent row fingerprints, never row text."""
    connection.execute("SET LOCAL search_path = pg_catalog")
    connection.execute("SET LOCAL TimeZone = 'UTC'")
    connection.execute("SET LOCAL DateStyle = 'ISO, YMD'")
    tables = connection.execute("""
        SELECT n.nspname, c.relname FROM pg_class c
        JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE c.relkind IN ('r','p') AND n.nspname NOT LIKE 'pg_%'
          AND n.nspname <> 'information_schema' ORDER BY 1,2
    """).fetchall()
    data = []
    for schema, table in tables:
        query = sql.SQL("""
            SELECT count(*), md5(coalesce(string_agg(row_hash, ''
                ORDER BY row_hash COLLATE "C"), ''))
            FROM (SELECT md5(to_jsonb(t)::text) AS row_hash FROM {}.{} t) records
        """).format(sql.Identifier(schema), sql.Identifier(table))
        count, fingerprint = connection.execute(query).fetchone()
        columns = connection.execute(
            """
            SELECT a.attname, format_type(a.atttypid,a.atttypmod), a.attnotnull,
                   pg_get_expr(d.adbin,d.adrelid)
            FROM pg_attribute a
            LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
            WHERE a.attrelid=%s::regclass AND a.attnum>0 AND NOT a.attisdropped
            ORDER BY a.attnum
        """,
            (sql.Identifier(schema, table).as_string(connection),),
        ).fetchall()
        data.append(
            {
                "schema": schema,
                "table": table,
                "count": count,
                "fingerprint": fingerprint,
                "columns": columns,
            }
        )
    extensions = connection.execute(
        "SELECT extname,extversion FROM pg_extension ORDER BY extname",
    ).fetchall()
    indexes = connection.execute("""
        SELECT schemaname,tablename,indexname,indexdef FROM pg_indexes
        WHERE schemaname NOT LIKE 'pg_%' ORDER BY 1,2,3
    """).fetchall()
    constraints = connection.execute("""
        SELECT n.nspname,c.relname,p.conname,pg_get_constraintdef(p.oid)
        FROM pg_constraint p JOIN pg_class c ON p.conrelid=c.oid
        JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname NOT LIKE 'pg_%' ORDER BY 1,2,3
    """).fetchall()
    # Convert database tuples to JSON arrays before comparing a restored manifest.
    return json.loads(
        json.dumps(
            {
                "tables": data,
                "extensions": extensions,
                "indexes": indexes,
                "constraints": constraints,
            }
        )
    )


def _private_directory(path: Path):
    if path.is_symlink():
        raise BackupError("Backup directories must not be symbolic links")
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.chmod(0o700)


def _write_private(path: Path, text: str):
    with path.open("x", encoding="utf-8") as stream:
        path.chmod(0o600)
        stream.write(text)


def backup_database(
    container: str, image: str, settings: Settings, environment: Environment, output: Path = BACKUPS
) -> Path:
    """The source transaction is read-only, shared with pg_dump by exported snapshot."""
    _private_directory(output)
    identity = uuid4()
    created = datetime.now(UTC)
    directory = output / (created.strftime("%Y%m%dT%H%M%SZ") + "-" + identity.hex[:12])
    directory.mkdir(mode=0o700)
    dump = directory / "database.dump"
    try:
        with connect(settings) as connection:
            connection.execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
            major = connection.info.server_version // 10000
            if major != 17:
                raise BackupError("This backup format requires PostgreSQL 17")
            snapshot = connection.execute("SELECT pg_export_snapshot()").fetchone()[0]
            args = [
                "docker",
                "exec",
                container,
                "pg_dump",
                "-U",
                settings.postgres_user,
                "-d",
                settings.postgres_db,
                "--format=custom",
                "--no-owner",
                "--no-acl",
                "--snapshot=" + snapshot,
            ]
            with dump.open("xb") as stream:
                dump.chmod(0o600)
                _run(args, stdout=stream)
            state = inventory(connection)
        with dump.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        commit = _run(["git", "-C", str(ROOT), "rev-parse", "HEAD"]).decode().strip()
        dirty = bool(_run(["git", "-C", str(ROOT), "status", "--porcelain"]).strip())
        manifest = Manifest(
            backup_id=identity,
            environment=environment,
            created_at=created,
            source_commit=commit,
            worktree_dirty=dirty,
            postgres_major=major,
            image=image,
            dump_sha256=digest,
            dump_bytes=dump.stat().st_size,
            inventory=state,
        )
        _write_private(directory / "manifest.json", manifest.model_dump_json(indent=2))
        return directory
    except BaseException:
        # Partial archives never masquerade as completed backups. Preserve files
        # privately for inspection; validation requires a completed manifest.
        raise


def validate_backup(directory: Path) -> Manifest:
    for path in (directory, directory / "manifest.json", directory / "database.dump"):
        if path.is_symlink() or not path.exists():
            raise BackupError("Backup is incomplete or contains symbolic links")
        if os.name == "posix" and path.stat().st_mode & 0o077:
            raise BackupError("Backup directory and files must be private (700/600)")
    manifest_path = directory / "manifest.json"
    if manifest_path.stat().st_size > 16 * 1024 * 1024:
        raise BackupError("Backup manifest exceeds its size limit")
    manifest = Manifest.model_validate_json(manifest_path.read_text())
    dump = directory / manifest.dump_file
    with dump.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != manifest.dump_sha256 or dump.stat().st_size != manifest.dump_bytes:
        raise BackupError("Backup checksum or size does not match")
    return manifest


@contextmanager
def disposable_database(image: str):
    """Only this newly created container is ever used as a restore target."""
    identity = uuid4().hex
    name = "unipath-restorecheck-" + identity
    password = secrets.token_urlsafe(32)
    created = False
    with tempfile.TemporaryDirectory(prefix="unipath-restorecheck-") as temporary:
        env_file = Path(temporary) / "postgres.env"
        _write_private(
            env_file,
            "POSTGRES_USER=restorecheck\nPOSTGRES_DB=restorecheck\n"
            + "POSTGRES_PASSWORD="
            + password
            + "\n",
        )
        try:
            _run(
                [
                    "docker",
                    "run",
                    "-d",
                    "--name",
                    name,
                    "--label",
                    "unipath.restorecheck=" + identity,
                    "--env-file",
                    str(env_file),
                    "-p",
                    "127.0.0.1::5432",
                    image,
                ]
            )
            created = True
            ports = _inspect(name, "{{json .NetworkSettings.Ports}}")
            port = int(ports["5432/tcp"][0]["HostPort"])
            settings = BackupSettings(
                _env_file=None,
                postgres_host="127.0.0.1",
                postgres_port=port,
                postgres_db="restorecheck",
                postgres_user="restorecheck",
                postgres_password=password,
            )
            deadline = time.monotonic() + 40
            while True:
                try:
                    with connect(settings):
                        break
                except psycopg.Error:
                    if time.monotonic() >= deadline:
                        raise BackupError("Disposable database did not become ready") from None
                    time.sleep(0.5)
            yield name, settings
        finally:
            if created:
                labels = _inspect(name, "{{json .Config.Labels}}")
                if labels.get("unipath.restorecheck") != identity:
                    raise BackupError("Restore container ownership did not match; cleanup refused")
                _run(["docker", "rm", "-f", "-v", name])


def verify_backup(directory: Path) -> Manifest:
    manifest = validate_backup(directory)
    with disposable_database(manifest.image) as (container, settings):
        args = [
            "docker",
            "exec",
            "-i",
            container,
            "pg_restore",
            "-U",
            settings.postgres_user,
            "-d",
            settings.postgres_db,
            "--no-owner",
            "--no-acl",
            "--exit-on-error",
            "--single-transaction",
        ]
        with (directory / manifest.dump_file).open("rb") as stream:
            _run(args, stdin=stream)
        with connect(settings) as connection:
            actual = inventory(connection)
        if comparable_inventory(actual) != comparable_inventory(manifest.inventory):
            raise BackupError("Restored schema or row fingerprints differ from the snapshot")
    report = {
        "backup_id": str(manifest.backup_id),
        "dump_sha256": manifest.dump_sha256,
        "verified_at": datetime.now(UTC).isoformat(),
        "status": "verified",
        "method": "disposable_postgresql_schema_and_rows",
    }
    report_path = directory / ("verification-" + uuid4().hex[:12] + ".json")
    _write_private(report_path, json.dumps(report, indent=2) + "\n")
    return manifest


def comparable_inventory(state: dict) -> dict:
    """Normalize only PostgreSQL's equivalent varchar-literal array text casts.

    pg_dump/restoration can distribute an array's varchar->text cast across
    its literal elements. Keep all other schema and row comparisons exact,
    and accept existing manifests without rewriting their signed-off contents.
    """
    literal = r"'(?:[^']|'')*'::character varying"
    literals = literal + r"(?:, " + literal + r")*"
    element = r"\(" + literal + r"\)::text"
    # Match the entire generated enum-like CHECK, never SQL inside a string
    # literal or an unrelated expression with different cast semantics.
    enum_check = re.compile(
        r"CHECK \(\(\([a-z_][a-z0-9_]*\)::text = ANY "
        + r"(?:\(\(ARRAY\["
        + literals
        + r"\]\)::text\[\]\)|\(ARRAY\["
        + element
        + r"(?:, "
        + element
        + r")*\]\))\)\)"
    )
    array_cast = re.compile(r"\(\(ARRAY\[(" + literal + r"(?:, " + literal + r")*)\]\)::text\[\]\)")
    element_cast = re.compile(r"\((" + literal + r")\)::text")

    def canonical(definition: str) -> str:
        if not enum_check.fullmatch(definition):
            return definition
        definition = array_cast.sub(lambda match: "(ARRAY[" + match[1] + "])", definition)
        return element_cast.sub(lambda match: match[1], definition)

    return {
        **state,
        "constraints": [[*row[:-1], canonical(row[-1])] for row in state.get("constraints", [])],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    backup = commands.add_parser("backup", help="Read-only snapshot of the selected Compose DB")
    backup.add_argument("--environment", type=Environment, choices=list(Environment), required=True)
    verify = commands.add_parser("verify", help="Restore into a NEW disposable database only")
    verify.add_argument("directory", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "backup":
            container, image, settings = source(args.environment)
            directory = backup_database(container, image, settings, args.environment)
            print("Backup completed:", directory)
        else:
            manifest = verify_backup(args.directory)
            print("Restore verification passed:", manifest.backup_id)
    except BackupError as error:
        parser.exit(1, str(error) + "\n")
    except (OSError, ValueError, psycopg.Error):
        parser.exit(1, "Database operation failed; credentials and data are not displayed\n")


if __name__ == "__main__":
    main()
