"""Prove restoration using synthetic data in two disposable PostgreSQL containers."""

import hashlib
import os
import subprocess
import tempfile
from pathlib import Path
from unittest.mock import patch

from app.core.config import Environment
from app.operations import db_backups
from app.operations.db_backups import (
    BackupError,
    backup_database,
    connect,
    disposable_database,
    verify_backup,
)

IMAGE = (
    "pgvector/pgvector:0.8.6-pg17-bookworm@sha256:"
    "cf134a767f474095eeba57e0117be8e568e011a63f33fbf252f14c9b760f8e6f"
)


def application_schema_backup(directory: Path):
    """Check the actual migration CHECKs/FKs too, beyond the small data fixture."""
    with disposable_database(IMAGE) as (container, settings):
        environment = {
            **os.environ,
            "APP_ENV": "local",
            "POSTGRES_HOST": settings.postgres_host,
            "POSTGRES_PORT": str(settings.postgres_port),
            "POSTGRES_DB": settings.postgres_db,
            "POSTGRES_USER": settings.postgres_user,
            "POSTGRES_PASSWORD": settings.postgres_password.get_secret_value(),
        }
        environment.pop("DATABASE_URL", None)
        subprocess.run(
            ["uv", "run", "--frozen", "alembic", "upgrade", "head"],
            cwd=Path(__file__).resolve().parents[1],
            env=environment,
            check=True,
        )
        backup = backup_database(container, IMAGE, settings, Environment.LOCAL, directory)
        manifest = verify_backup(backup)
        tables = {row["table"] for row in manifest.inventory["tables"]}
        assert {
            "users",
            "personal_evaluations",
            "school_knowledge_documents",
            "school_knowledge_chunks",
            "certificate_providers",
            "certificates",
            "official_rule_programs",
            "official_program_rules",
            "official_program_evidence",
            "official_program_course_refs",
            "official_program_certificate_refs",
            "personal_import_receipts",
            "official_record_sources",
            "official_record_source_events",
        } <= tables
    print("Application migration backup restored with all constraints and indexes intact.")


def main():
    with tempfile.TemporaryDirectory(prefix="unipath-backup-smoke-") as temporary:
        with disposable_database(IMAGE) as (container, settings):
            with connect(settings) as connection:
                connection.execute("CREATE EXTENSION vector")
                connection.execute("CREATE TABLE students (id integer PRIMARY KEY, label text)")
                connection.execute("""
                    CREATE TABLE courses (id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                        student_id integer REFERENCES students(id), credits numeric(4,2),
                        embedding vector(3), UNIQUE(student_id,credits))
                """)
                connection.execute(
                    "INSERT INTO students VALUES (1, '합성 학생 — 실제 개인정보 아님')"
                )
                connection.execute("""
                    INSERT INTO courses(student_id,credits,embedding)
                    VALUES (1,3.25,'[1,0,0]'),(1,2.75,'[0,1,0]')
                """)
                connection.execute('CREATE TABLE "합성 기록" ("값" text, meta jsonb)')
                connection.execute("""INSERT INTO "합성 기록" VALUES
                    ('synthetic', '{"nested":[1,2],"approved":true}')""")
                connection.execute(
                    "CREATE TABLE private_source_files (id integer PRIMARY KEY, original bytea)"
                )
                connection.execute(
                    "INSERT INTO private_source_files VALUES (1, %s)",
                    (b"%PDF-1.7\n% SYNTHETIC BINARY SOURCE\x00\xff\n%%EOF\n",),
                )
            original_run = db_backups._run

            def write_after_snapshot_export(args, **kwargs):
                if "pg_dump" in args:
                    with connect(settings) as concurrent:
                        concurrent.execute("INSERT INTO students VALUES (2, '동시 합성 변경')")
                        concurrent.execute("UPDATE students SET label='백업 중 변경' WHERE id=1")
                return original_run(args, **kwargs)

            with patch.object(db_backups, "_run", side_effect=write_after_snapshot_export):
                directory = backup_database(
                    container, IMAGE, settings, Environment.LOCAL, Path(temporary) / "backups"
                )
            # A write AFTER the backup must also remain outside its snapshot.
            with connect(settings) as connection:
                connection.execute("INSERT INTO students VALUES (3, '백업 이후 합성 변경')")
            manifest = verify_backup(directory)
            tables = {t["table"]: t for t in manifest.inventory["tables"]}
            assert tables["students"]["count"] == 1
            assert tables["courses"]["count"] == 2
            assert tables["합성 기록"]["count"] == 1
            assert tables["private_source_files"]["count"] == 1
            assert ["vector", "0.8.6"] in manifest.inventory["extensions"]
            assert manifest.inventory["constraints"]
            assert manifest.inventory["indexes"]
            assert list(directory.glob("verification-*.json"))
            archive = directory / "database.dump"
            with archive.open("ab") as stream:
                stream.write(b"synthetic corruption")
            try:
                verify_backup(directory)
            except BackupError:
                pass
            else:
                raise AssertionError("Corrupt backup was accepted")
            # A checksum-valid but unreadable archive must fail restore and clean
            # up its temporary container/volume rather than reporting success.
            archive.write_bytes(b"PGDMP unreadable synthetic archive")
            broken = manifest.model_copy(
                update={
                    "dump_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
                    "dump_bytes": archive.stat().st_size,
                }
            )
            (directory / "manifest.json").write_text(broken.model_dump_json())
            before = original_run(["docker", "ps", "-aq", "--filter", "label=unipath.restorecheck"])
            try:
                verify_backup(directory)
            except BackupError:
                pass
            else:
                raise AssertionError("Unreadable archive was accepted")
            after = original_run(["docker", "ps", "-aq", "--filter", "label=unipath.restorecheck"])
            assert before == after, "Failed restore left a container behind"
        application_schema_backup(Path(temporary) / "application-backups")
    print(
        "Backup smoke passed: Unicode, decimals, JSON, vectors, constraints, snapshot, corruption."
    )


if __name__ == "__main__":
    main()
