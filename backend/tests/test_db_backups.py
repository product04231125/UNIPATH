import hashlib
import json
import os
from datetime import UTC, datetime
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.operations import db_backups as backups

IMAGE = "pgvector/pgvector:0.8.6-pg17-bookworm@sha256:" + "a" * 64


def completed_backup(directory):
    directory.mkdir(mode=0o700)
    data = b"PGDMP synthetic archive bytes"
    dump = directory / "database.dump"
    dump.write_bytes(data)
    dump.chmod(0o600)
    manifest = backups.Manifest(
        backup_id=uuid4(),
        environment="local",
        created_at=datetime.now(UTC),
        source_commit="a" * 40,
        postgres_major=17,
        image=IMAGE,
        dump_sha256=hashlib.sha256(data).hexdigest(),
        dump_bytes=len(data),
        inventory={"tables": [], "extensions": [], "indexes": [], "constraints": []},
    )
    backups._write_private(directory / "manifest.json", manifest.model_dump_json())
    return manifest


def test_private_completed_backup_manifest_roundtrip(tmp_path):
    directory = tmp_path / "backup"
    expected = completed_backup(directory)
    assert backups.validate_backup(directory) == expected
    assert expected.model_dump_json().find("password") == -1


def test_corruption_rejected_before_any_disposable_database_is_created(tmp_path, monkeypatch):
    directory = tmp_path / "backup"
    completed_backup(directory)
    (directory / "database.dump").write_bytes(b"corrupt")
    commands = []
    monkeypatch.setattr(backups, "_run", lambda *a, **kw: commands.append(a))
    with pytest.raises(backups.BackupError, match="checksum"):
        backups.verify_backup(directory)
    assert not commands


@pytest.mark.skipif(os.name != "posix", reason="POSIX permissions")
@pytest.mark.parametrize("target", [".", "manifest.json", "database.dump"])
def test_world_readable_files_are_refused(tmp_path, target):
    directory = tmp_path / "backup"
    completed_backup(directory)
    (directory / target).chmod(0o755 if target == "." else 0o644)
    with pytest.raises(backups.BackupError, match="private"):
        backups.validate_backup(directory)


def test_symlinks_incomplete_archives_and_manifest_traversal_refused(tmp_path):
    directory = tmp_path / "backup"
    completed_backup(directory)
    original = directory / "database.dump"
    original.rename(directory / "real.dump")
    original.symlink_to(directory / "real.dump")
    with pytest.raises(backups.BackupError, match="symbolic"):
        backups.validate_backup(directory)
    original.unlink()
    with pytest.raises(backups.BackupError, match="incomplete"):
        backups.validate_backup(directory)
    (directory / "real.dump").rename(original)
    manifest_path = directory / "manifest.json"
    data = json.loads(manifest_path.read_text())
    data["dump_file"] = "../database.dump"
    manifest_path.write_text(json.dumps(data))
    with pytest.raises(ValidationError):
        backups.validate_backup(directory)


@pytest.mark.parametrize("image", ["postgres:17", "pgvector/pgvector:latest", "evil/image:latest"])
def test_unpinned_or_unrelated_restore_images_refused(tmp_path, image):
    directory = tmp_path / "backup"
    completed_backup(directory)
    path = directory / "manifest.json"
    data = json.loads(path.read_text())
    data["image"] = image
    path.write_text(json.dumps(data))
    with pytest.raises(ValidationError):
        backups.validate_backup(directory)


def test_selected_environment_file_wins_over_shell_database_variables(tmp_path, monkeypatch):
    env = tmp_path / ".env.staging"
    env.write_text(
        "APP_ENV=staging\nPOSTGRES_PASSWORD=synthetic-file-password\nPOSTGRES_PORT=5434\n"
    )
    monkeypatch.setenv("POSTGRES_PORT", "5435")
    monkeypatch.setenv("POSTGRES_PASSWORD", "synthetic-other-environment")
    settings = backups.BackupSettings(_env_file=env)
    assert settings.postgres_port == 5434
    assert settings.postgres_password.get_secret_value() == "synthetic-file-password"


def test_environment_mismatch_is_rejected_before_docker_commands(tmp_path, monkeypatch):
    (tmp_path / ".env").write_text("APP_ENV=production\nPOSTGRES_PASSWORD=synthetic\n")
    monkeypatch.setattr(backups, "ROOT", tmp_path)
    commands = []
    monkeypatch.setattr(backups, "_run", lambda *a, **kw: commands.append(a))
    with pytest.raises(backups.BackupError, match="does not match"):
        backups.source(backups.Environment.LOCAL)
    assert not commands


def test_restore_check_accepts_only_equivalent_literal_array_casts():
    original = (
        "CHECK (((role)::text = ANY ((ARRAY['user'::character varying, "
        "'school_admin'::character varying])::text[])))"
    )
    restored = (
        "CHECK (((role)::text = ANY (ARRAY[('user'::character varying)::text, "
        "('school_admin'::character varying)::text])))"
    )

    def state(definition):
        return {"constraints": [["public", "users", "ck_users_role", definition]], "tables": []}

    before = state(original)
    assert backups.comparable_inventory(before) == backups.comparable_inventory(state(restored))
    assert before == state(original)  # Existing manifests remain untouched.
    for changed in [
        restored.replace("school_admin", "super_admin"),
        restored.replace(" = ANY", " <> ANY"),
        restored.replace("::character varying", "::integer"),
        restored.replace(" = ANY", " <> ALL"),
    ]:
        assert backups.comparable_inventory(before) != backups.comparable_inventory(state(changed))
    assert backups.comparable_inventory(before) != backups.comparable_inventory(
        {**before, "tables": [{"count": 1, "fingerprint": "different"}]}
    )
    unrelated = state("CHECK (note = '" + restored.replace("'", "''") + "')")
    assert backups.comparable_inventory(unrelated) == unrelated
