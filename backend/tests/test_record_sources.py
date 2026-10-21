import base64
import hashlib
import json
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from pydantic import ValidationError
from sqlalchemy import func, select
from test_academic import department, operator, post, school
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register

from app.api.record_sources import upload_metadata
from app.core.auth_errors import AuthError
from app.models.identity import IdentityAudit
from app.models.record_sources import OfficialRecordSource, OfficialRecordSourceEvent
from app.schemas.record_sources import MAX_FILE_BYTES, SourceUpload, SourceVerify
from app.services.record_sources import validate_pdf

ME = "/api/v1/me/official-record-sources"
ADMIN = "/api/v1/admin/official-record-sources"
PDF = b"%PDF-1.7\n% SYNTHETIC TEST FILE; NOT A SCHOOL RECORD\n%%EOF\n"
integration = pytest.mark.integration


@pytest.mark.parametrize("data", [b"", b"not a pdf", b"PK\x03\x04zip", b"%PDF-1.7\nno eof"])
def test_only_bounded_pdf_signatures_are_accepted(data):
    with pytest.raises(AuthError) as error:
        validate_pdf(data)
    assert error.value.status == 422


def test_pdf_limit_and_explicit_source_review_attestations():
    validate_pdf(PDF)
    with pytest.raises(AuthError) as error:
        validate_pdf(b" " * (MAX_FILE_BYTES + 1))
    assert error.value.status == 413
    payload = {
        "expected_version": 1,
        "expected_sha256": "a" * 64,
        "school_issued_confirmed": True,
        "subject_identity_confirmed": True,
    }
    for invalid in [False, 1, "true", None]:
        with pytest.raises(ValidationError):
            SourceVerify.model_validate({**payload, "school_issued_confirmed": invalid})


def test_private_metadata_header_is_bounded_typed_and_allowed_by_cors(client):
    for invalid in [
        "@@bad@@",
        base64.urlsafe_b64encode(b"not json").decode(),
        base64.urlsafe_b64encode(b'{"owner_id":"override"}').decode(),
    ]:
        with pytest.raises(AuthError) as error:
            upload_metadata(invalid)
        assert error.value.status == 422
    result = client.options(
        ME,
        headers={
            "Origin": "http://localhost:3000",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": (
                "Content-Type,X-Unipath-Source-Metadata,X-Unipath-Owner"
            ),
        },
    )
    assert result.status_code == 200
    assert "x-unipath-source-metadata" in result.headers["access-control-allow-headers"].lower()


@pytest.mark.parametrize(
    "filename", ["../x.pdf", "x\\y.pdf", ".pdf", "x.exe", "x\r\n.pdf", "x\u202e.pdf"]
)
def test_filenames_cannot_be_paths_controls_or_other_formats(filename):
    with pytest.raises(ValidationError):
        SourceUpload.model_validate(
            {
                "client_id": str(uuid4()),
                "institution_id": str(uuid4()),
                "document_kind": "transcript",
                "issued_on": "2026-01-01",
                "filename": filename,
                "review_consent_confirmed": True,
            }
        )


def setup(c, factory):
    root = operator(c, factory)
    institution = school(c, root)
    student = register(c).json()
    headers = {"Authorization": "Bearer " + student["access_token"]}
    metadata = {
        "client_id": str(uuid4()),
        "institution_id": institution["id"],
        "document_kind": "transcript",
        "issued_on": "2026-01-01",
        "filename": "합성 성적증명서.pdf",
        "review_consent_confirmed": True,
    }
    return root, institution, student, headers, metadata


def upload(c, headers, metadata, data=PDF, *, expected=201, extra_headers=None):
    result = c.post(
        ME,
        content=data,
        headers={
            **headers,
            "Content-Type": "application/pdf",
            "X-Unipath-Source-Metadata": base64.urlsafe_b64encode(
                json.dumps(metadata).encode()
            ).decode(),
            **(extra_headers or {}),
        },
    )
    assert result.status_code == expected, result.text
    return result.json()


def verify(c, root, source, *, expected=200, **extra):
    result = c.post(
        ADMIN + "/" + source["id"] + "/verify",
        headers=root,
        json={
            "expected_version": source["version"],
            "expected_sha256": source["sha256"],
            "school_issued_confirmed": True,
            "subject_identity_confirmed": True,
            **extra,
        },
    )
    assert result.status_code == expected, result.text
    return result.json()


@integration
def test_private_pdf_lifecycle_preserves_exact_original_and_review_history(auth_client, auth_db):
    c = auth_client
    root, inst, student, headers, metadata = setup(c, auth_db)
    source = upload(c, headers, metadata)
    assert source["owner_id"] == student["user"]["id"] and source["status"] == "submitted"
    assert source["sha256"] == hashlib.sha256(PDF).hexdigest()
    assert source["byte_count"] == len(PDF) and source["graduation_eligible"] is False
    assert "file_data" not in source
    for prefix, credential in [(ME, headers), (ADMIN, root)]:
        downloaded = c.get(prefix + "/" + source["id"] + "/file", headers=credential)
        assert downloaded.content == PDF and downloaded.headers["cache-control"] == "no-store"
        assert downloaded.headers["content-type"] == "application/octet-stream"
        assert downloaded.headers["content-disposition"].startswith("attachment;")
        assert "filename*=UTF-8''" in downloaded.headers["content-disposition"]
        assert downloaded.headers["x-content-type-options"] == "nosniff"
    checked = verify(c, root, source)
    assert checked["status"] == "verified" and checked["version"] == 2
    assert checked["graduation_eligible"] is False
    verify(c, root, source, expected=409)
    revoked = c.post(
        ADMIN + "/" + source["id"] + "/revoke",
        headers=root,
        json={"expected_version": 2, "reason": "합성 발급기관 검토 정정"},
    )
    assert revoked.status_code == 200 and revoked.json()["status"] == "revoked"
    withdrawn = c.post(
        ME + "/" + source["id"] + "/withdraw", headers=headers, json={"expected_version": 3}
    )
    assert withdrawn.status_code == 200 and withdrawn.json()["status"] == "withdrawn"
    assert c.get(ADMIN + "/" + source["id"] + "/file", headers=root).status_code == 404
    assert c.get(ADMIN, headers=root).json()["items"] == []
    assert c.get(ME + "/" + source["id"] + "/file", headers=headers).content == PDF
    events = c.get(ME + "/" + source["id"] + "/events", headers=headers).json()["items"]
    assert [e["action"] for e in events] == ["submitted", "verified", "revoked", "withdrawn"]
    assert [e["version"] for e in events] == [1, 2, 3, 4]
    assert events[2]["reason"] == "합성 발급기관 검토 정정"
    with auth_db() as db:
        rows = list(
            db.scalars(select(IdentityAudit).where(IdentityAudit.target_id == UUID(source["id"])))
        )
        assert len(rows) == 4 and all(row.institution_id == UUID(inst["id"]) for row in rows)
        assert all(row.request_id is not None for row in rows)
        assert all("성적" not in row.action and "정정" not in row.action for row in rows)


@integration
def test_replays_are_idempotent_and_never_revive_withdrawn_evidence(auth_client, auth_db):
    c = auth_client
    _, _, _, headers, metadata = setup(c, auth_db)
    first = upload(c, headers, metadata)
    assert upload(c, headers, metadata)["id"] == first["id"]
    upload(c, headers, {**metadata, "filename": "다른 증명서.pdf"}, expected=409)
    upload(c, headers, metadata, data=PDF.replace(b"SYNTHETIC", b"DIFFERENT"), expected=409)
    assert (
        c.post(
            ME + "/" + first["id"] + "/withdraw", headers=headers, json={"expected_version": 1}
        ).status_code
        == 200
    )
    replay = upload(c, headers, metadata)
    assert replay["id"] == first["id"] and replay["status"] == "withdrawn"
    with auth_db() as db:
        assert db.scalar(select(func.count()).select_from(OfficialRecordSource)) == 1
        assert db.scalar(select(func.count()).select_from(OfficialRecordSourceEvent)) == 2


@integration
def test_other_owners_wrong_workspace_and_ordinary_roles_cannot_access_sources(
    auth_client, auth_db
):
    c = auth_client
    root, _, _, headers, metadata = setup(c, auth_db)
    source = upload(c, headers, metadata)
    other = register(c, email="other@example.test")
    other_headers = authorization(other)
    for suffix in ["", "/file", "/events"]:
        assert c.get(ME + "/" + source["id"] + suffix, headers=other_headers).status_code == 404
        assert c.get(ADMIN + "/" + source["id"] + suffix, headers=other_headers).status_code == 403
    assert c.get(ME, headers=other_headers).json()["items"] == []
    upload(c, {**headers, "X-Unipath-Owner": other.json()["user"]["id"]}, metadata, expected=403)
    verify(c, other_headers, source, expected=403)
    verify(c, root, source)


@integration
def test_school_review_is_scoped_and_revocation_is_effective(auth_client, auth_db):
    c = auth_client
    root, inst, _, headers, metadata = setup(c, auth_db)
    other_school = school(c, root, "다른 합성대")
    admin = register(c, email="school-admin@example.test")
    admin_headers = authorization(admin)
    scope = post(
        c,
        root,
        "scopes",
        {
            "user_id": admin.json()["user"]["id"],
            "institution_id": other_school["id"],
            "reason": "합성 검증",
        },
    )
    source = upload(c, headers, metadata)
    assert c.get(ADMIN, headers=admin_headers).json()["items"] == []
    verify(c, admin_headers, source, expected=403)
    allowed_scope = post(
        c,
        root,
        "scopes",
        {
            "user_id": admin.json()["user"]["id"],
            "institution_id": inst["id"],
            "reason": "합성 검증",
        },
    )
    assert len(c.get(ADMIN, headers=admin_headers).json()["items"]) == 1
    assert c.get(ADMIN + "/" + source["id"] + "/file", headers=admin_headers).content == PDF
    response = c.post(
        "/api/v1/admin/scopes/" + allowed_scope["id"] + "/revoke",
        headers=root,
        json={"expected_version": allowed_scope["version"]},
    )
    assert response.status_code == 200
    verify(c, admin_headers, source, expected=403)
    assert c.get(ADMIN + "/" + source["id"] + "/file", headers=admin_headers).status_code == 403
    assert scope["institution_id"] != inst["id"]


@integration
def test_invalid_upload_metadata_and_truncated_or_oversized_bodies_leave_no_source(
    auth_client, auth_db
):
    c = auth_client
    _, _, _, headers, metadata = setup(c, auth_db)
    for change in [
        {"review_consent_confirmed": False},
        {"owner_id": str(uuid4())},
        {"status": "verified"},
        {"filename": "../test.pdf"},
        {"issued_on": (datetime.now(UTC).date() + timedelta(days=1)).isoformat()},
    ]:
        upload(c, headers, {**metadata, **change}, expected=422)
    upload(c, headers, metadata, data=b"not PDF", expected=422)
    upload(c, headers, metadata, extra_headers={"Content-Type": "application/json"}, expected=415)
    upload(c, headers, metadata, extra_headers={"Content-Length": "1"}, expected=422)
    upload(
        c,
        headers,
        metadata,
        extra_headers={"Content-Length": str(MAX_FILE_BYTES + 1)},
        expected=413,
    )
    streamed = c.post(
        ME,
        headers={
            **headers,
            "Content-Type": "application/pdf",
            "X-Unipath-Source-Metadata": base64.urlsafe_b64encode(
                json.dumps(metadata).encode()
            ).decode(),
        },
        content=iter([PDF, b" " * MAX_FILE_BYTES]),
    )
    assert streamed.status_code == 413 and streamed.json()["error"]["code"] == "HTTP_ERROR"
    assert c.get(ME, headers=headers).json()["items"] == []


@integration
def test_verification_checks_exact_bytes_subject_attestation_and_prevents_self_approval(
    auth_client, auth_db
):
    c = auth_client
    root, _, _, headers, metadata = setup(c, auth_db)
    source = upload(c, headers, metadata)
    verify(c, root, source, expected=422, subject_identity_confirmed=False)
    verify(c, root, source, expected=422, school_issued_confirmed=1)
    verify(c, root, source, expected=409, expected_sha256="0" * 64)
    own_source = upload(c, root, {**metadata, "client_id": str(uuid4())})
    verify(c, root, own_source, expected=403)
    with auth_db() as db:
        row = db.get(OfficialRecordSource, UUID(source["id"]))
        row.file_data = PDF.replace(b"SYNTHETIC", b"CORRUPTED")
        db.commit()
    assert c.get(ME + "/" + source["id"] + "/file", headers=headers).status_code == 503
    verify(c, root, source, expected=503)
    assert c.get(ME + "/" + source["id"], headers=headers).json()["status"] == "submitted"


@integration
def test_conflicting_department_and_size_quota_do_not_create_partial_events(
    auth_client, auth_db, monkeypatch
):
    c = auth_client
    root, _, _, headers, metadata = setup(c, auth_db)
    other = school(c, root, "다른 합성대")
    dep = department(c, root, other)
    upload(c, headers, {**metadata, "department_id": dep["id"]}, expected=404)
    monkeypatch.setattr("app.services.record_sources.MAX_OWNER_BYTES", len(PDF) - 1)
    upload(c, headers, metadata, expected=409)
    with auth_db() as db:
        assert db.scalar(select(func.count()).select_from(OfficialRecordSourceEvent)) == 0


@integration
def test_concurrent_verify_and_withdraw_have_one_versioned_winner(auth_client, auth_db):
    c = auth_client
    root, _, _, headers, metadata = setup(c, auth_db)
    source = upload(c, headers, metadata)

    def act(kind):
        if kind == "verify":
            return c.post(
                ADMIN + "/" + source["id"] + "/verify",
                headers=root,
                json={
                    "expected_version": 1,
                    "expected_sha256": source["sha256"],
                    "school_issued_confirmed": True,
                    "subject_identity_confirmed": True,
                },
            ).status_code
        return c.post(
            ME + "/" + source["id"] + "/withdraw", headers=headers, json={"expected_version": 1}
        ).status_code

    with ThreadPoolExecutor(max_workers=2) as pool:
        statuses = list(pool.map(act, ["verify", "withdraw"]))
    assert statuses.count(200) == 1 and statuses.count(409) + statuses.count(404) == 1
    events = c.get(ME + "/" + source["id"] + "/events", headers=headers).json()["items"]
    assert [e["version"] for e in events] == [1, 2]


@integration
def test_concurrent_identical_uploads_have_one_original_and_one_event(auth_client, auth_db):
    c = auth_client
    _, _, _, headers, metadata = setup(c, auth_db)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: upload(c, headers, metadata), [1, 2]))
    assert results[0]["id"] == results[1]["id"]
    with auth_db() as db:
        assert db.scalar(select(func.count()).select_from(OfficialRecordSource)) == 1
        assert db.scalar(select(func.count()).select_from(OfficialRecordSourceEvent)) == 1


@integration
def test_cookie_account_switch_does_not_submit_or_read_for_stale_owner(auth_client, auth_db):
    c = auth_client
    _, _, _, _, metadata = setup(c, auth_db)
    first = register(c, email="cookie-first@example.test", mode="cookie").json()
    headers = {"Origin": "http://localhost:3000", "X-Unipath-Owner": first["user"]["id"]}
    source = upload(c, headers, metadata)
    register(c, email="cookie-second@example.test", mode="cookie")
    upload(c, headers, {**metadata, "client_id": str(uuid4())}, expected=403)
    assert c.get(ME + "/" + source["id"] + "/file", headers=headers).status_code == 403
    assert c.get(ME).json()["items"] == []


@integration
def test_rejected_source_and_file_quota_preserve_originals(auth_client, auth_db, monkeypatch):
    c = auth_client
    root, _, _, headers, metadata = setup(c, auth_db)
    source = upload(c, headers, metadata)
    monkeypatch.setattr("app.services.record_sources.MAX_OWNER_FILES", 1)
    upload(c, headers, {**metadata, "client_id": str(uuid4())}, expected=409)
    response = c.post(
        ADMIN + "/" + source["id"] + "/reject",
        headers=root,
        json={"expected_version": 1, "reason": "합성 발급 확인 불가"},
    )
    assert response.status_code == 200 and response.json()["status"] == "rejected"
    verify(c, root, response.json(), expected=409)
    assert c.get(ME + "/" + source["id"] + "/file", headers=headers).content == PDF


@integration
@pytest.mark.parametrize("size", [300 * 1024, MAX_FILE_BYTES])
def test_binary_original_at_proxy_and_api_boundaries_round_trips(auth_client, auth_db, size):
    c = auth_client
    root, _, _, headers, metadata = setup(c, auth_db)
    data = b"%PDF-1.7\n" + b"x" * (size - 15) + b"%%EOF\n"
    source = upload(c, headers, metadata, data=data)
    assert source["byte_count"] == size and source["sha256"] == hashlib.sha256(data).hexdigest()
    assert c.get(ME + "/" + source["id"] + "/file", headers=headers).content == data
    assert verify(c, root, source)["status"] == "verified"


@integration
@pytest.mark.parametrize("withdrawn", [False, True])
def test_private_source_catalog_links_are_redacted_and_do_not_reveal_counts(
    auth_client, auth_db, withdrawn
):
    c = auth_client
    root, institution, student, headers, metadata = setup(c, auth_db)
    dep = department(c, root, institution)
    cur = post(
        c,
        root,
        "curricula",
        {
            "name": "합성 보호 과정",
            "institution_id": institution["id"],
            "department_id": dep["id"],
            "year": 2026,
        },
    )
    assert (
        c.get("/api/v1/admin/curricula/" + cur["id"] + "/references", headers=root).json()["items"]
        == []
    )
    for _ in range(2):
        source = upload(
            c,
            headers,
            {
                **metadata,
                "client_id": str(uuid4()),
                "department_id": dep["id"],
                "curriculum_id": cur["id"],
            },
        )
        if withdrawn:
            assert (
                c.post(
                    ME + "/" + source["id"] + "/withdraw",
                    headers=headers,
                    json={"expected_version": 1},
                ).status_code
                == 200
            )
        for collection, parent in [("departments", dep), ("curricula", cur)]:
            response = c.get(
                "/api/v1/admin/" + collection + "/" + parent["id"] + "/references", headers=root
            )
            private = [r for r in response.json()["items"] if r["kind"] == "protected_reference"]
            assert private == [
                {"id": parent["id"], "kind": "protected_reference", "name": "보호된 연결 참조"}
            ]
            for secret in [
                student["user"]["id"],
                student["user"]["email"],
                metadata["filename"],
                source["id"],
                source["sha256"],
            ]:
                assert secret not in response.text
    assert (
        c.delete(
            "/api/v1/admin/curricula/" + cur["id"] + "?expected_version=1", headers=root
        ).status_code
        == 409
    )
    assert c.get(ME + "/" + source["id"] + "/file", headers=headers).content == PDF
