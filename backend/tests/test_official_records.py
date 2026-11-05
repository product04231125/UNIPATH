from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from datetime import date
from uuid import UUID, uuid4

import pytest
from sqlalchemy import func, select
from test_academic import department, post, school
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register
from test_record_sources import ADMIN as SOURCE_ADMIN
from test_record_sources import ME as SOURCE_ME
from test_record_sources import PDF, setup, upload, verify

from app.models.identity import AuthSession, IdentityAudit, User
from app.models.official_records import OfficialRecordBatch as Batch
from app.models.official_records import OfficialRecordBatchEvent as Event
from app.models.record_sources import OfficialRecordSource
from app.rules.contracts import AcademicContext
from app.services import official_records as service
from app.services.auth import Identity, token_hash

ADMIN = "/api/v1/admin/official-record-batches"
ME = "/api/v1/me/official-record-batches"
pytestmark = pytest.mark.integration


def fixture(c, factory):
    root, institution, student, owner, metadata = setup(c, factory)
    dep = department(c, root, institution)
    course = post(
        c,
        root,
        "courses",
        {
            "name": "합성 과목",
            "institution_id": institution["id"],
            "code": "SYN001",
            "credits": "3.5",
        },
    )
    source = verify(c, root, upload(c, owner, metadata))
    data = {
        "kind": "academics",
        "coverage": "complete",
        "page_count": 1,
        "records_as_of": metadata["issued_on"],
        "context": {"department_id": dep["id"], "admission_year": 2026, "track": "single_major"},
        "records": [
            {
                "client_id": str(uuid4()),
                "source_page": 1,
                "course_id": course["id"],
                "expected_course_version": course["version"],
                "completion_status": "completed",
                "earned_credits": "3.5000",
                "category": "major",
                "original_grade": "A+",
            }
        ],
    }
    return root, institution, student, owner, metadata, source, data, course


def create(c, actor, source, data, *, client_id=None, expected=201):
    response = c.post(
        ADMIN,
        headers=actor,
        json={
            "source_id": source["id"],
            "expected_source_version": source["version"],
            "client_id": client_id or str(uuid4()),
            "data": data,
        },
    )
    assert response.status_code == expected, response.text
    return response.json()


def approve(c, actor, batch, *, expected=200, **extra):
    response = c.post(
        ADMIN + "/" + batch["id"] + "/approve",
        headers=actor,
        json={
            "expected_version": batch["version"],
            "expected_source_sha256": batch["source_sha256"],
            "records_reviewed": True,
            "context_reviewed": True,
            "coverage_reviewed": True,
            **extra,
        },
    )
    assert response.status_code == expected, response.text
    return response.json()


def snapshot(factory, student, headers, institution, data, on=date(2026, 1, 1)):
    with factory() as db:
        identity = Identity(
            db.get(User, UUID(student["user"]["id"])),
            db.get(AuthSession, token_hash(headers["Authorization"][7:])),
        )
        ctx = AcademicContext(institution_id=institution["id"], **data["context"])
        return service.owned_snapshot(db, identity, ctx, on)


def test_staff_draft_replace_approval_and_owner_history_have_immutable_provenance(
    auth_client, auth_db
):
    c = auth_client
    root, inst, student, owner, _, source, data, course = fixture(c, auth_db)
    batch = create(c, root, source, data)
    assert batch["status"] == "draft" and batch["owner_id"] == student["user"]["id"]
    assert batch["data"]["records"][0]["earned_credits"] == "3.5"
    assert batch["data"]["records"][0]["grade_points"] is None
    assert c.get(ME, headers=owner).json()["items"] == []
    assert c.get(ME + "/" + batch["id"], headers=owner).status_code == 404
    changed = deepcopy(data)
    changed["records"][0]["earned_credits"] = "4"
    response = c.put(
        ADMIN + "/" + batch["id"],
        headers=root,
        json={"expected_version": batch["version"], "data": changed},
    )
    assert response.status_code == 200, response.text
    batch = approve(c, root, response.json())
    assert batch["status"] == "approved" and batch["usable_for_audit"] is True
    assert batch["graduation_eligible"] is False
    assert batch["references"][0]["name"] == course["name"]
    assert (
        c.put(
            ADMIN + "/" + batch["id"],
            headers=root,
            json={"expected_version": batch["version"], "data": data},
        ).status_code
        == 409
    )
    viewed = c.get(ME + "/" + batch["id"], headers=owner).json()
    assert viewed["data"] == batch["data"]
    header = c.get(ME, headers=owner).json()["items"][0]
    assert "data" not in header and "references" not in header
    events = c.get(ME + "/" + batch["id"] + "/events", headers=owner).json()["items"]
    assert [e["action"] for e in events] == ["created", "replaced", "approved"]
    result, selected, _ = snapshot(auth_db, student, owner, inst, changed)
    assert str(selected[0]) == batch["id"] and result.academics[0].earned_credits == 4
    assert result.academics[0].grade_points is None and result.volunteers is None
    with auth_db() as db:
        logs = list(
            db.scalars(select(IdentityAudit).where(IdentityAudit.target_id == UUID(batch["id"])))
        )
        assert len(logs) == 3 and all(log.request_id is not None for log in logs)


def test_create_replays_normalized_decimal_without_duplicate_records_or_events(
    auth_client, auth_db
):
    c = auth_client
    root, _, _, _, _, source, data, _ = fixture(c, auth_db)
    key = str(uuid4())
    first = create(c, root, source, data, client_id=key)
    changed = deepcopy(data)
    changed["records"][0]["earned_credits"] = "3.50"
    assert create(c, root, source, changed, client_id=key)["id"] == first["id"]
    changed["records"][0]["earned_credits"] = "100"
    create(c, root, source, changed, client_id=key, expected=409)
    with auth_db() as db:
        assert db.scalar(select(func.count()).select_from(Batch)) == 1
        assert db.scalar(select(func.count()).select_from(Event)) == 1


@pytest.mark.parametrize("action", ["revoke", "withdraw"])
def test_ending_source_invalidates_approved_records_and_drafts_atomically(
    auth_client, auth_db, action
):
    c = auth_client
    root, inst, student, owner, _, source, data, _ = fixture(c, auth_db)
    approved = approve(c, root, create(c, root, source, data))
    pending_data = {**data, "kind": "volunteers", "records": []}
    pending = create(c, root, source, pending_data)
    prefix, headers = (SOURCE_ADMIN, root) if action == "revoke" else (SOURCE_ME, owner)
    body = {"expected_version": source["version"]}
    if action == "revoke":
        body["reason"] = "합성 원본 확인 회수"
    ended = c.post(prefix + "/" + source["id"] + "/" + action, headers=headers, json=body)
    assert ended.status_code == 200, ended.text
    with auth_db() as db:
        assert db.get(Batch, UUID(approved["id"])).status == "revoked"
        assert db.get(Batch, UUID(pending["id"])).status == "discarded"
    old = c.get(ME + "/" + approved["id"], headers=owner)
    assert old.status_code == 200 and old.json()["usable_for_audit"] is False
    assert c.get(ME + "/" + pending["id"], headers=owner).status_code == 404
    if action == "withdraw":
        assert c.get(ADMIN + "/" + approved["id"], headers=root).status_code == 404
    result, selected, _ = snapshot(auth_db, student, owner, inst, data)
    assert result.academics is None and selected == ()


def test_current_approval_requires_explicit_predecessor_and_preserves_old_snapshot(
    auth_client, auth_db
):
    c = auth_client
    root, inst, student, owner, _, source, data, _ = fixture(c, auth_db)
    first = approve(c, root, create(c, root, source, data))
    changed = deepcopy(data)
    changed["records"][0]["earned_credits"] = "5"
    second = create(c, root, source, changed)
    approve(c, root, second, expected=409)
    second = approve(
        c, root, second, replaces_batch_id=first["id"], expected_replaced_version=first["version"]
    )
    previous = c.get(ME + "/" + first["id"], headers=owner).json()
    assert (
        previous["status"] == "superseded"
        and previous["data"]["records"][0]["earned_credits"] == "3.5"
    )
    result, selected, _ = snapshot(auth_db, student, owner, inst, data)
    assert str(selected[0]) == second["id"] and result.academics[0].earned_credits == 5


def test_partial_is_not_known_empty_and_snapshot_date_must_match(auth_client, auth_db):
    c = auth_client
    root, inst, student, owner, _, source, data, _ = fixture(c, auth_db)
    partial = approve(c, root, create(c, root, source, {**data, "coverage": "partial"}))
    assert "partial_records" in partial["issues"] and partial["usable_for_audit"] is False
    result, _, _ = snapshot(auth_db, student, owner, inst, data)
    assert result.academics is None
    empty = approve(
        c,
        root,
        create(c, root, source, {**data, "records": []}),
        replaces_batch_id=partial["id"],
        expected_replaced_version=partial["version"],
    )
    assert empty["usable_for_audit"] is True
    result, _, _ = snapshot(auth_db, student, owner, inst, data)
    assert result.academics == ()
    result, _, issues = snapshot(auth_db, student, owner, inst, data, on=date(2026, 1, 2))
    assert result.academics is None and ("academics", "snapshot_date_mismatch") in issues


def test_master_changes_are_visible_but_do_not_rewrite_approved_values(auth_client, auth_db):
    c = auth_client
    root, _, _, owner, _, source, data, course = fixture(c, auth_db)
    batch = approve(c, root, create(c, root, source, data))
    updated = c.patch(
        "/api/v1/admin/courses/" + course["id"],
        headers=root,
        json={
            "expected_version": course["version"],
            "institution_id": course["institution_id"],
            "code": course["code"],
            "name": "정정된 합성 과목",
            "credits": "4",
        },
    )
    assert updated.status_code == 200, updated.text
    result = c.get(ME + "/" + batch["id"], headers=owner).json()
    assert result["usable_for_audit"] is False and "reference_changed" in result["issues"]
    assert result["references"][0]["name"] == course["name"]
    refs = c.get("/api/v1/admin/courses/" + course["id"] + "/references", headers=root).json()
    assert refs["items"] == [
        {"id": course["id"], "kind": "protected_reference", "name": "보호된 연결 참조"}
    ]
    assert (
        c.delete(
            "/api/v1/admin/courses/" + course["id"] + "?expected_version=2", headers=root
        ).status_code
        == 409
    )


def test_corrupt_records_never_produce_trusted_numeric_inputs(auth_client, auth_db):
    c = auth_client
    root, _, _, owner, _, source, data, _ = fixture(c, auth_db)
    batch = approve(c, root, create(c, root, source, data))
    with auth_db() as db:
        row = db.get(Batch, UUID(batch["id"]))
        raw = deepcopy(row.data_json)
        raw["records"][0]["earned_credits"] = "999"
        row.data_json = raw
        db.commit()
    response = c.get(ME + "/" + batch["id"], headers=owner)
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "SERVICE_UNAVAILABLE"
    assert "999" not in response.text


def test_original_corruption_invalidates_snapshot_and_blocks_new_approval(auth_client, auth_db):
    c = auth_client
    root, inst, student, owner, _, source, data, _ = fixture(c, auth_db)
    approved = approve(c, root, create(c, root, source, data))
    draft = create(c, root, source, {**data, "kind": "volunteers", "records": []})
    with auth_db() as db:
        db.get(OfficialRecordSource, UUID(source["id"])).file_data = PDF.replace(b"TEST", b"EDIT")
        db.commit()
    viewed = c.get(ME + "/" + approved["id"], headers=owner).json()
    assert "source_changed" in viewed["issues"] and viewed["usable_for_audit"] is False
    approve(c, root, draft, expected=409)
    result, selected, _ = snapshot(auth_db, student, owner, inst, data)
    assert result.academics is None and selected == ()


def test_all_record_kinds_round_trip_without_inventing_unknown_values(auth_client, auth_db):
    c = auth_client
    root, inst, student, owner, _, source, data, _ = fixture(c, auth_db)
    provider = post(
        c,
        root,
        "certificate-providers",
        {
            "code": "SYN",
            "name": "합성 발급처",
            "official_url": "https://example.invalid/provider",
        },
    )
    certificate = post(
        c,
        root,
        "certificates",
        {
            "code": "SYN-CERT",
            "name": "합성 자격",
            "provider_id": provider["id"],
            "official_url": "https://example.invalid/certificate",
        },
    )
    records = {
        "academics": data["records"],
        "volunteers": [
            {
                "client_id": str(uuid4()),
                "source_page": 1,
                "approval_status": "pending",
                "approved_hours": None,
            }
        ],
        "certificates": [
            {
                "client_id": str(uuid4()),
                "source_page": 1,
                "certificate_id": certificate["id"],
                "expected_certificate_version": 1,
                "approval_status": "approved",
                "expires_on": None,
                "validity_known": False,
            }
        ],
        "theses": [
            {
                "client_id": str(uuid4()),
                "source_page": 1,
                "thesis_type": "capstone",
                "approval_status": "approved",
                "is_completed": None,
            }
        ],
    }
    approved = {}
    for kind, items in records.items():
        approved[kind] = approve(
            c, root, create(c, root, source, {**data, "kind": kind, "records": items})
        )
        assert approved[kind]["usable_for_audit"] is True
    result, selected, issues = snapshot(auth_db, student, owner, inst, data)
    assert len(selected) == 4 and issues == ()
    assert result.academics[0].grade_points is None
    assert result.volunteers[0].approved_hours is None
    assert result.certificates[0].validity_known is False
    assert result.certificates[0].expires_on is None
    assert result.theses[0].is_completed is None
    refs = c.get(
        "/api/v1/admin/certificates/" + certificate["id"] + "/references", headers=root
    ).json()
    assert refs["items"] == [
        {"id": certificate["id"], "kind": "protected_reference", "name": "보호된 연결 참조"}
    ]
    deactivated = post(
        c,
        root,
        "certificate-providers/" + provider["id"] + "/deactivate",
        {"expected_version": 1},
        expected=200,
    )
    assert deactivated["status"] == "inactive"
    viewed = c.get(ME + "/" + approved["certificates"]["id"], headers=owner).json()
    assert "reference_changed" in viewed["issues"]
    assert viewed["references"][0]["provider_name"] == provider["name"]
    result, selected, _ = snapshot(auth_db, student, owner, inst, data)
    assert result.certificates is None and len(selected) == 3


def test_scope_revocation_applies_to_existing_capabilities_and_no_self_approval(
    auth_client, auth_db
):
    c = auth_client
    root, inst, student, owner, _, source, data, _ = fixture(c, auth_db)
    reviewer = register(c, email="reviewer@example.test")
    staff = authorization(reviewer)
    foreign = school(c, root, "다른 합성대")
    post(
        c,
        root,
        "scopes",
        {
            "user_id": reviewer.json()["user"]["id"],
            "institution_id": foreign["id"],
            "reason": "합성 범위 검증",
        },
    )
    create(c, staff, source, data, expected=403)
    scope = post(
        c,
        root,
        "scopes",
        {
            "user_id": reviewer.json()["user"]["id"],
            "institution_id": inst["id"],
            "reason": "합성 검토 권한",
        },
    )
    own_scope = post(
        c,
        root,
        "scopes",
        {
            "user_id": student["user"]["id"],
            "institution_id": inst["id"],
            "reason": "합성 자기 승인 차단 검증",
        },
    )
    batch = create(c, staff, source, data)
    approve(c, owner, batch, expected=403)
    batch = approve(c, staff, batch)
    assert own_scope["institution_id"] == inst["id"]
    post(
        c,
        root,
        "scopes/" + scope["id"] + "/revoke",
        {"expected_version": scope["version"], "reason": "합성 범위 회수"},
        expected=200,
    )
    assert c.get(ADMIN + "/" + batch["id"], headers=staff).status_code == 403
    assert c.get(ADMIN, headers=staff).json()["items"] == []
    assert c.get(ME + "/" + batch["id"], headers=owner).status_code == 200


def test_contexts_are_independent_and_replay_does_not_revive_discarded_draft(auth_client, auth_db):
    c = auth_client
    root, inst, student, owner, _, source, data, _ = fixture(c, auth_db)
    first = approve(c, root, create(c, root, source, data))
    other_data = deepcopy(data)
    other_data["context"]["admission_year"] = 2025
    other = approve(c, root, create(c, root, source, other_data))
    assert first["status"] == other["status"] == "approved"
    _, selected, _ = snapshot(auth_db, student, owner, inst, other_data)
    assert tuple(map(str, selected)) == (other["id"],)
    key = str(uuid4())
    draft = create(c, root, source, data, client_id=key)
    discarded = c.post(
        ADMIN + "/" + draft["id"] + "/discard",
        headers=root,
        json={"expected_version": 1, "reason": "합성 초안 폐기"},
    )
    assert discarded.status_code == 200
    replayed = create(c, root, source, data, client_id=key)
    assert replayed["id"] == draft["id"] and replayed["status"] == "discarded"
    approve(c, root, replayed, expected=409)
    assert c.get(ME + "/" + draft["id"], headers=owner).status_code == 404


def test_incomplete_context_can_be_drafted_but_never_approved(auth_client, auth_db):
    c = auth_client
    root, _, _, _, _, source, data, _ = fixture(c, auth_db)
    incomplete = {**data, "context": {}}
    draft = create(c, root, source, incomplete)
    assert "context_incomplete" in draft["issues"]
    approve(c, root, draft, expected=409)


def test_users_cannot_normalize_and_peers_cannot_read_approved_records(auth_client, auth_db):
    c = auth_client
    root, _, _, owner, _, source, data, _ = fixture(c, auth_db)
    create(c, owner, source, data, expected=403)
    batch = approve(c, root, create(c, root, source, data))
    other = authorization(register(c, email="other-student@example.test"))
    for suffix in ["", "/events"]:
        assert c.get(ME + "/" + batch["id"] + suffix, headers=other).status_code == 404
    assert c.get(ME, headers=other).json()["items"] == []
    assert (
        c.post(
            ADMIN + "/" + batch["id"] + "/revoke",
            headers=owner,
            json={"expected_version": batch["version"], "reason": "untrusted"},
        ).status_code
        == 403
    )


def test_source_withdrawal_and_approval_are_serialized_without_a_stale_approved_batch(
    auth_client, auth_db
):
    c = auth_client
    root, _, _, owner, _, source, data, _ = fixture(c, auth_db)
    batch = create(c, root, source, data)

    def act(kind):
        if kind == "approve":
            return c.post(
                ADMIN + "/" + batch["id"] + "/approve",
                headers=root,
                json={
                    "expected_version": batch["version"],
                    "expected_source_sha256": batch["source_sha256"],
                    "records_reviewed": True,
                    "context_reviewed": True,
                    "coverage_reviewed": True,
                },
            ).status_code
        return c.post(
            SOURCE_ME + "/" + source["id"] + "/withdraw",
            headers=owner,
            json={"expected_version": source["version"]},
        ).status_code

    with ThreadPoolExecutor(max_workers=2) as pool:
        first, second = list(pool.map(act, ["approve", "withdraw"]))
    assert second == 200 and first in (200, 404)
    with auth_db() as db:
        assert db.get(Batch, UUID(batch["id"])).status in ("discarded", "revoked")
        assert (
            db.scalar(select(func.count()).select_from(Batch).where(Batch.status == "approved"))
            == 0
        )
