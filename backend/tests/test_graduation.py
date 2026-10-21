"""Only synthetic school rules, students and documents are used in this suite."""

from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from sqlalchemy import func, select
from test_academic import post, school
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register
from test_official_records import approve as approve_records
from test_official_records import create as create_records
from test_record_sources import ME as SOURCES
from test_record_sources import upload, verify
from test_rule_programs import approve as approve_program
from test_rule_programs import metadata, payload, registry, setup

from app.models.graduation import GraduationAudit, GraduationCatalogReview
from app.models.identity import IdentityAudit
from app.models.knowledge import KnowledgeChunk
from app.services import graduation_audits

ADMIN = "/api/v1/admin/graduation-catalog-reviews"
ME = "/api/v1/me/graduation-audits"
TODAY = datetime.now(UTC).date().isoformat()
pytestmark = pytest.mark.integration


def fixture(c, db, *, records=True, complete=True, credits="3.5", kind="credits", minimum="3"):
    root, inst, ctx, _, chunk = setup(c, db)
    group, rules = metadata(c, root, inst, [kind])
    condition = (
        {"kind": "minimum_credits", "minimum": minimum}
        if kind == "credits"
        else {"kind": "manual_review", "instruction": "합성 수동 확인 필요"}
    )
    program = approve_program(
        c, root, post(c, root, "rule-programs", payload(group, rules, [condition], chunk))
    )
    student = register(c)
    owner = authorization(student)
    source = verify(
        c,
        root,
        upload(
            c,
            owner,
            {
                "client_id": str(uuid4()),
                "institution_id": inst["id"],
                "department_id": ctx["department_id"],
                "curriculum_id": ctx["curriculum_id"],
                "document_kind": "transcript",
                "issued_on": TODAY,
                "filename": "합성 감사 성적.pdf",
                "review_consent_confirmed": True,
            },
        ),
    )
    course = post(
        c,
        root,
        "courses",
        {
            "name": "합성 감사 과목",
            "code": "AUDIT1",
            "credits": "3.5",
            "institution_id": inst["id"],
        },
    )
    data = {
        "kind": "academics",
        "page_count": 1,
        "records_as_of": TODAY,
        "coverage": "complete" if complete else "partial",
        "context": {k: v for k, v in ctx.items() if k != "institution_id"},
        "records": [
            {
                "client_id": str(uuid4()),
                "source_page": 1,
                "course_id": course["id"],
                "expected_course_version": course["version"],
                "completion_status": "completed",
                "earned_credits": credits,
                "original_grade": "A+",
            }
        ],
    }
    batch = approve_records(c, root, create_records(c, root, source, data)) if records else None
    return root, inst, ctx, owner, source, batch, program, chunk


def review(c, root, ctx, *, expected=201, on=TODAY, **extra):
    shown = c.get(ADMIN + "/preview", headers=root, params={**ctx, "as_of": on})
    assert shown.status_code == 200, shown.text
    body = {
        "context": ctx,
        "as_of": on,
        "client_id": str(uuid4()),
        "expected_catalog_digest": shown.json()["snapshot_digest"],
        "all_requirements_reviewed": True,
        "all_levels_reviewed": True,
        "sources_reviewed": True,
        "review_note": "합성 학교·학과·교육과정 전체 요건 검토",
        **extra,
    }
    response = c.post(ADMIN, headers=root, json=body)
    assert response.status_code == expected, response.text
    return response.json(), body


def audit(c, owner, ctx, *, expected=201, **extra):
    body = {"context": ctx, "as_of": TODAY, "client_id": str(uuid4()), **extra}
    response = c.post(ME, headers=owner, json=body)
    assert response.status_code == expected, response.text
    return response.json(), body


def test_reviewed_rules_and_records_produce_reproducible_private_official_audit(
    auth_client, auth_db
):
    c = auth_client
    root, _, ctx, owner, source, batch, program, _ = fixture(c, auth_db)
    reviewed, _ = review(c, root, ctx)
    assert reviewed["usable"] is True
    result, body = audit(c, owner, ctx)
    assert result["official"] is True and result["status"] == "satisfied"
    assert result["eligible_as_of"] is True and result["current_usable"] is True
    assert result["catalog_complete"] is True and result["catalog_review_id"] == reviewed["id"]
    assert result["issues"] == result["current_issues"] == []
    assert result["criteria"][0]["id"] == program["id"]
    assert result["records"][0]["id"] == batch["id"]
    assert result["records"][0]["source_sha256"] == source["sha256"]
    assert (
        result["record_evidence"][0]["record_id"] == result["results"][0]["evidence_record_ids"][0]
    )
    assert result["record_evidence"][0]["batch_id"] == batch["id"]
    assert result["record_evidence"][0]["source_page"] == 1
    assert result["results"][0]["current"] == "3.5" and result["results"][0]["required"] == "3"
    evidence = result["criteria"][0]["rules"][0]["evidence"][0]
    assert evidence["page"] == 1 and evidence["source_url"].startswith("https://")
    assert "excerpt" not in evidence and "core_input" not in result
    assert "review_note" not in result and "original_grade" not in str(result)
    assert c.get(ME + "/" + result["id"], headers=owner).json() == result
    listed = c.get(ME, headers=owner).json()["items"][0]
    assert "criteria" not in listed and "records" not in listed and "results" not in listed
    assert c.post(ME, headers=owner, json=body).json()["id"] == result["id"]
    with auth_db() as db:
        assert db.scalar(select(func.count()).select_from(GraduationAudit)) == 1
        assert (
            db.scalar(
                select(func.count())
                .select_from(IdentityAudit)
                .where(IdentityAudit.action == "graduation_audit_created")
            )
            == 1
        )


@pytest.mark.parametrize(
    "case", ["no_review", "no_records", "partial", "unknown_credits", "failed_threshold"]
)
def test_missing_review_records_and_numeric_knowledge_do_not_turn_into_eligibility(
    auth_client, auth_db, case
):
    c = auth_client
    root, _, ctx, owner, *_ = fixture(
        c,
        auth_db,
        records=case != "no_records",
        complete=case != "partial",
        credits=None if case == "unknown_credits" else "2" if case == "failed_threshold" else "3.5",
    )
    if case != "no_review":
        review(c, root, ctx)
    result, _ = audit(c, owner, ctx)
    assert result["eligible_as_of"] is False
    assert result["status"] == ("not_satisfied" if case == "failed_threshold" else "needs_review")
    if case == "no_review":
        assert result["catalog_complete"] is False
    if case in ("no_records", "partial"):
        assert result["results"][0]["deficit"] is None


def test_complete_known_empty_is_a_failure_and_personal_records_never_supply_official_inputs(
    auth_client, auth_db
):
    c = auth_client
    root, _, ctx, owner, source, batch, *_ = fixture(c, auth_db, records=False)
    profile = c.get("/api/v1/me/planning-profile", headers=owner).json()
    assert profile["official"] is False
    personal = c.post(
        "/api/v1/me/course-records",
        headers=owner,
        json={
            "title": "합성 감사 과목",
            "term": "2026-1",
            "category": "전공",
            "credits": "99",
            "course_code": "AUDIT1",
            "grade": "A+",
        },
    )
    assert personal.status_code == 201 and personal.json()["official"] is False
    empty = {
        "kind": "academics",
        "page_count": 1,
        "records_as_of": TODAY,
        "coverage": "complete",
        "context": {k: v for k, v in ctx.items() if k != "institution_id"},
        "records": [],
    }
    batch = approve_records(c, root, create_records(c, root, source, empty))
    review(c, root, ctx)
    result, _ = audit(c, owner, ctx)
    assert result["status"] == "not_satisfied" and result["results"][0]["current"] == "0"
    assert result["results"][0]["deficit"] == "3" and result["records"][0]["id"] == batch["id"]


def test_manual_requirements_remain_needs_review_even_with_complete_catalogue_attestation(
    auth_client, auth_db
):
    c = auth_client
    root, _, ctx, owner, *_ = fixture(c, auth_db, kind="custom")
    reviewed, _ = review(c, root, ctx)
    assert reviewed["usable"] is True
    result, _ = audit(c, owner, ctx)
    assert result["catalog_complete"] is True and result["eligible_as_of"] is False
    assert (
        result["status"] == "needs_review"
        and result["results"][0]["reason"] == "manual_requirement"
    )
    assert result["records"] == []


def test_all_applicable_levels_are_required_and_stale_preview_cannot_be_attested(
    auth_client, auth_db
):
    c = auth_client
    root, inst, ctx, owner, _, _, _, chunk = fixture(c, auth_db)
    approved, _ = review(c, root, ctx)
    shown = c.get(ADMIN + "/preview", headers=root, params={**ctx, "as_of": TODAY}).json()
    group, rules = metadata(
        c,
        root,
        inst,
        ["credits"],
        department_id=ctx["department_id"],
        curriculum_id=ctx["curriculum_id"],
    )
    invalid = c.post(
        ADMIN,
        headers=root,
        json={
            "context": ctx,
            "as_of": TODAY,
            "client_id": str(uuid4()),
            "expected_catalog_digest": shown["snapshot_digest"],
            "all_requirements_reviewed": True,
            "all_levels_reviewed": True,
            "sources_reviewed": True,
            "review_note": "합성 오래된 검토",
        },
    )
    assert invalid.status_code == 409
    assert c.get(ADMIN + "/" + approved["id"], headers=root).json()["usable"] is False
    review(c, root, ctx, expected=409)
    approve_program(
        c,
        root,
        post(
            c,
            root,
            "rule-programs",
            payload(group, rules, [{"kind": "minimum_credits", "minimum": "100"}], chunk),
        ),
    )
    revised, _ = review(
        c,
        root,
        ctx,
        replaces_review_id=approved["id"],
        expected_replaced_version=approved["version"],
    )
    result, _ = audit(c, owner, ctx)
    assert len(result["criteria"]) == 2 and result["status"] == "not_satisfied"
    assert any(r["required"] == "100" and r["status"] == "not_satisfied" for r in result["results"])
    assert revised["version"] == 1


@pytest.mark.parametrize(
    "end", ["source_withdraw", "catalog_revoke", "source_corrupt", "catalog_text_corrupt"]
)
def test_historical_result_is_retained_but_stale_evidence_cannot_be_used_as_current(
    auth_client, auth_db, end
):
    c = auth_client
    root, _, ctx, owner, source, _, _, chunk = fixture(c, auth_db)
    reviewed, _ = review(c, root, ctx)
    original, body = audit(c, owner, ctx)
    if end == "source_withdraw":
        response = c.post(
            SOURCES + "/" + source["id"] + "/withdraw",
            headers=owner,
            json={"expected_version": source["version"]},
        )
        assert response.status_code == 200
    elif end == "catalog_revoke":
        response = c.post(
            ADMIN + "/" + reviewed["id"] + "/revoke",
            headers=root,
            json={"expected_version": 1, "reason": "합성 검토 회수"},
        )
        assert response.status_code == 200
    elif end == "source_corrupt":
        from app.models.record_sources import OfficialRecordSource

        with auth_db() as db:
            row = db.get(OfficialRecordSource, UUID(source["id"]))
            row.file_data = row.file_data.replace(b"TEST", b"EDIT")
            db.commit()
    else:
        with auth_db() as db:
            row = db.get(KnowledgeChunk, UUID(chunk))
            row.content = "x" * len(row.content)
            db.commit()
    viewed = c.get(ME + "/" + original["id"], headers=owner)
    assert viewed.status_code == 200, viewed.text
    viewed = viewed.json()
    assert viewed["status"] == "satisfied" and viewed["eligible_as_of"] is True
    assert viewed["results"] == original["results"] and viewed["criteria"] == original["criteria"]
    assert viewed["current_usable"] is False and viewed["current_issues"]
    assert c.post(ME, headers=owner, json=body).json()["id"] == original["id"]
    fresh, _ = audit(c, owner, ctx)
    assert fresh["eligible_as_of"] is False


def test_owner_only_history_and_no_student_criteria_or_role_overrides(auth_client, auth_db):
    c = auth_client
    root, _, ctx, owner, *_ = fixture(c, auth_db)
    review(c, root, ctx)
    result, body = audit(c, owner, ctx)
    peer = authorization(register(c, email="peer-audit@example.test"))
    for actor in (peer, root):
        assert c.get(ME + "/" + result["id"], headers=actor).status_code == 404
        assert c.get(ME, headers=actor).json()["items"] == []
    assert (
        c.get(ADMIN + "/preview", headers=owner, params={**ctx, "as_of": TODAY}).status_code == 403
    )
    for extra in (
        {"owner_id": str(uuid4())},
        {"catalog_complete": True},
        {"snapshot": {}},
        {"rule_ids": []},
    ):
        assert c.post(ME, headers=owner, json={**body, **extra}).status_code == 422
    changed = {**body, "as_of": (datetime.now(UTC).date() - timedelta(days=1)).isoformat()}
    assert c.post(ME, headers=owner, json=changed).status_code == 409
    assert c.delete(ME + "/" + result["id"], headers=owner).status_code == 405


def test_review_scope_revocation_and_idempotency_do_not_reopen_old_authority(auth_client, auth_db):
    c = auth_client
    root, inst, ctx, _, *_ = fixture(c, auth_db)
    member = register(c, email="audit-reviewer@example.test")
    staff = authorization(member)
    other = school(c, root, "다른 합성 감사 학교")
    post(
        c,
        root,
        "scopes",
        {
            "user_id": member.json()["user"]["id"],
            "institution_id": other["id"],
            "reason": "합성 다른 학교",
        },
    )
    assert (
        c.get(ADMIN + "/preview", headers=staff, params={**ctx, "as_of": TODAY}).status_code == 403
    )
    scope = post(
        c,
        root,
        "scopes",
        {
            "user_id": member.json()["user"]["id"],
            "institution_id": inst["id"],
            "reason": "합성 감사 검토",
        },
    )
    reviewed, body = review(c, staff, ctx)
    assert c.post(ADMIN, headers=staff, json=body).json()["id"] == reviewed["id"]
    post(
        c,
        root,
        "scopes/" + scope["id"] + "/revoke",
        {"expected_version": scope["version"]},
        expected=200,
    )
    assert c.get(ADMIN + "/" + reviewed["id"], headers=staff).status_code == 403
    assert c.post(ADMIN, headers=staff, json=body).status_code == 403
    assert c.get(ADMIN, headers=staff).json()["items"] == []


def test_audit_and_source_withdrawal_are_serialized_and_final_history_is_not_current(
    auth_client, auth_db
):
    c = auth_client
    root, _, ctx, owner, source, *_ = fixture(c, auth_db)
    review(c, root, ctx)

    def act(which):
        return (
            c.post(
                ME, headers=owner, json={"context": ctx, "as_of": TODAY, "client_id": str(uuid4())}
            )
            if which == "audit"
            else c.post(
                SOURCES + "/" + source["id"] + "/withdraw",
                headers=owner,
                json={"expected_version": source["version"]},
            )
        )

    with ThreadPoolExecutor(max_workers=2) as pool:
        result, ended = list(pool.map(act, ["audit", "withdraw"]))
    assert result.status_code == 201 and ended.status_code == 200
    final = c.get(ME + "/" + result.json()["id"], headers=owner).json()
    assert final["current_usable"] is False and final["status"] in ("satisfied", "needs_review")


def test_corrupt_saved_audit_is_not_returned_and_storage_limit_does_not_duplicate_replay(
    auth_client, auth_db, monkeypatch
):
    c = auth_client
    root, _, ctx, owner, *_ = fixture(c, auth_db)
    review(c, root, ctx)
    result, body = audit(c, owner, ctx)
    monkeypatch.setattr(graduation_audits, "MAX_AUDITS", 1)
    assert c.post(ME, headers=owner, json=body).status_code == 201
    audit(c, owner, ctx, expected=409)
    with auth_db() as db:
        row = db.get(GraduationAudit, UUID(result["id"]))
        raw = deepcopy(row.payload_json)
        raw["evaluation"]["results"][0]["current"] = "999999"
        row.payload_json = raw
        db.commit()
    response = c.get(ME + "/" + result["id"], headers=owner)
    assert response.status_code == 503 and "999999" not in response.text


def test_catalogue_review_replay_after_revocation_retains_events_and_old_snapshot(
    auth_client, auth_db
):
    c = auth_client
    root, _, ctx, _, *_ = fixture(c, auth_db)
    reviewed, body = review(c, root, ctx)
    post(
        c,
        root,
        "graduation-catalog-reviews/" + reviewed["id"] + "/revoke",
        {"expected_version": 1, "reason": "합성 회수"},
        expected=200,
    )
    replay = c.post(ADMIN, headers=root, json=body).json()
    assert (
        replay["id"] == reviewed["id"]
        and replay["status"] == "revoked"
        and replay["usable"] is False
    )
    events = c.get(ADMIN + "/" + reviewed["id"] + "/events", headers=root).json()["items"]
    assert [e["action"] for e in events] == ["approved", "revoked"]
    with auth_db() as db:
        assert db.scalar(select(func.count()).select_from(GraduationCatalogReview)) == 1


@pytest.mark.parametrize("numeric_grade_required", [False, True])
def test_all_five_requirement_types_use_verified_owner_records_and_never_convert_letter_grades(
    auth_client, auth_db, numeric_grade_required
):
    c = auth_client
    root, inst, ctx, owner, source, batch, _, chunk = fixture(c, auth_db)
    academic = batch["data"]["records"][0]
    _, certificate = registry(c, root)
    group, rules = metadata(
        c,
        root,
        inst,
        ["required_course", "volunteer", "certificate", "thesis"],
        department_id=ctx["department_id"],
        curriculum_id=ctx["curriculum_id"],
    )
    course_condition = {
        "course_id": academic["course_id"],
        "expected_version": 1,
        "minimum_credits": "3",
    }
    if numeric_grade_required:
        course_condition.update(minimum_grade_points="2.5", comparison_grade_scale="GPA-4.5")
    conditions = [
        {"kind": "required_courses", "courses": [course_condition]},
        {"kind": "minimum_volunteer_hours", "minimum": "10"},
        {
            "kind": "any_certificate",
            "certificates": [{"certificate_id": certificate["id"], "expected_version": 1}],
        },
        {
            "kind": "thesis",
            "thesis_type": "capstone",
            "requires_approval": True,
            "accepted_grades": ["PASS"],
        },
    ]
    approve_program(
        c, root, post(c, root, "rule-programs", payload(group, rules, conditions, chunk))
    )
    rows = {
        "volunteers": [
            {
                "client_id": str(uuid4()),
                "source_page": 1,
                "approval_status": "approved",
                "approved_hours": "10",
            }
        ],
        "certificates": [
            {
                "client_id": str(uuid4()),
                "source_page": 1,
                "certificate_id": certificate["id"],
                "expected_certificate_version": 1,
                "approval_status": "approved",
                "expires_on": TODAY,
                "validity_known": True,
            }
        ],
        "theses": [
            {
                "client_id": str(uuid4()),
                "source_page": 1,
                "thesis_type": "capstone",
                "approval_status": "approved",
                "is_completed": True,
                "grade": "PASS",
            }
        ],
    }
    for kind, records in rows.items():
        data = {
            "kind": kind,
            "context": {k: v for k, v in ctx.items() if k != "institution_id"},
            "page_count": 1,
            "records_as_of": TODAY,
            "coverage": "complete",
            "records": records,
        }
        approve_records(c, root, create_records(c, root, source, data))
    review(c, root, ctx)
    result, _ = audit(c, owner, ctx)
    assert (
        len(result["results"]) == 5
        and len(result["records"]) == 4
        and len(result["record_evidence"]) == 4
    )
    assert result["status"] == ("needs_review" if numeric_grade_required else "satisfied")
    assert result["eligible_as_of"] is (not numeric_grade_required)
    assert {r["source_id"] for r in result["records"]} == {source["id"]}


def test_official_review_pins_master_versions_and_public_view_keeps_snapshot(auth_client, auth_db):
    c = auth_client
    root, inst, ctx, _, _, _, _, chunk = fixture(c, auth_db)
    _, certificate = registry(c, root)
    group, rules = metadata(c, root, inst, ["certificate"], department_id=ctx["department_id"])
    program = approve_program(
        c,
        root,
        post(
            c,
            root,
            "rule-programs",
            payload(
                group,
                rules,
                [
                    {
                        "kind": "any_certificate",
                        "certificates": [
                            {"certificate_id": certificate["id"], "expected_version": 1}
                        ],
                    }
                ],
                chunk,
            ),
        ),
    )
    reviewed, _ = review(c, root, ctx)
    changed = c.patch(
        "/api/v1/admin/certificates/" + certificate["id"],
        headers=root,
        json={
            "expected_version": 1,
            "name": "새 합성 자격 이름",
            "official_url": certificate["official_url"],
        },
    )
    assert changed.status_code == 200
    displayed = c.get("/api/v1/catalog/rule-programs/" + program["id"], headers=root).json()
    assert displayed["rules"][0]["references"][0]["name"] == certificate["name"]
    shown = c.get(ADMIN + "/preview", headers=root, params={**ctx, "as_of": TODAY}).json()
    assert shown["reviewable"] is False
    assert any(i["reason"] == "program_dependency_unavailable" for i in shown["issues"])
    assert c.get(ADMIN + "/" + reviewed["id"], headers=root).json()["usable"] is False


@pytest.mark.parametrize("has_metadata", [False, True])
def test_missing_execution_is_needs_review_and_no_metadata_is_not_applicable(
    auth_client, auth_db, has_metadata
):
    c = auth_client
    root, inst, ctx, *_ = setup(c, auth_db)
    if has_metadata:
        metadata(c, root, inst, ["credits"])
    owner = authorization(register(c))
    result, _ = audit(c, owner, ctx)
    assert result["eligible_as_of"] is False and result["catalog_complete"] is False
    assert result["status"] == ("needs_review" if has_metadata else "not_applicable")
    if has_metadata:
        assert any(i["reason"] == "execution_program_required" for i in result["issues"])
