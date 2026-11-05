"""Execution publication uses synthetic catalogues, evidence and records only."""

from datetime import UTC, datetime
from uuid import UUID, uuid4

import pytest
from sqlalchemy import func, select
from test_academic import department, operator, post, school
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register
from test_knowledge import applied_document
from test_knowledge import approve as approve_knowledge
from test_knowledge import create as create_knowledge
from test_knowledge import replace as replace_page

from app.models.rule_programs import ProgramEvidence, ProgramRule, RuleProgram
from app.rules.contracts import AcademicContext, Snapshot
from app.rules.engine import evaluate_official
from app.services.rule_programs import as_core

pytestmark = pytest.mark.integration
ROOT = "/api/v1/admin/rule-programs"
PUBLIC = "/api/v1/catalog/rule-programs"


def setup(c, db):
    h = operator(c, db)
    institution = school(c, h)
    dep = department(c, h, institution)
    curriculum = post(
        c,
        h,
        "curricula",
        {
            "name": "합성 2026 과정",
            "institution_id": institution["id"],
            "department_id": dep["id"],
            "year": 2026,
        },
    )
    context = {
        "institution_id": institution["id"],
        "department_id": dep["id"],
        "curriculum_id": curriculum["id"],
        "admission_year": 2026,
        "track": "single_major",
    }
    source = applied_document(c, h, institution)
    knowledge = create_knowledge(c, h, source)
    page = replace_page(
        c,
        h,
        knowledge,
        parts=[
            {
                "content": "합성 검증용 기준. 학점 3, 봉사 10시간, 필수 과목·자격·논문 기준.",
                "admission_years": [2025, 2026],
                "tracks": ["single_major", "double_major"],
            }
        ],
    )
    approve_knowledge(c, h, knowledge)
    return h, institution, context, knowledge, page["parts"][0]["id"]


def metadata(c, h, institution, kinds, **scope):
    group = post(
        c,
        h,
        "rule-sets",
        {
            "name": "합성 졸업 기준",
            "institution_id": institution["id"],
            **scope,
        },
    )
    rules = [
        post(
            c,
            h,
            "rules",
            {
                "name": f"합성 {kind} 기준",
                "institution_id": institution["id"],
                **scope,
                "rule_set_id": group["id"],
                "rule_type": kind,
                "definition": "이 설명과 current_value는 실행식으로 사용하지 않습니다.",
            },
        )
        for kind in kinds
    ]
    group = c.get("/api/v1/admin/rule-sets/" + group["id"], headers=h).json()
    group = post(
        c,
        h,
        "rule-sets/" + group["id"] + "/apply",
        {
            "expected_version": group["version"],
        },
        200,
    )
    rules = [c.get("/api/v1/admin/rules/" + r["id"], headers=h).json() for r in rules]
    return group, rules


def payload(group, rules, conditions, chunk, **extra):
    return {
        "rule_set_id": group["id"],
        "expected_source_version": group["version"],
        "admission_year_from": 2026,
        "admission_year_to": 2026,
        "tracks": ["single_major"],
        "rules": [
            {
                "rule_id": rule["id"],
                "expected_version": rule["version"],
                "condition": condition,
                "evidence_chunk_ids": [chunk],
            }
            for rule, condition in zip(rules, conditions, strict=True)
        ],
        **extra,
    }


def approve(c, h, program, expected=200, **extra):
    result = c.post(
        ROOT + "/" + program["id"] + "/approve",
        headers=h,
        json={
            "expected_version": program["version"],
            "conditions_verified": True,
            "sources_verified": True,
            "applicability_verified": True,
            "complete_source_context_verified": True,
            "review_note": "합성 규칙 검토",
            **extra,
        },
    )
    assert result.status_code == expected, result.text
    return result.json()


def select_programs(c, h, context):
    result = c.get(PUBLIC, headers=h, params=context)
    assert result.status_code == 200, result.text
    return result.json()


def registry(c, h):
    provider = post(
        c,
        h,
        "certificate-providers",
        {
            "code": "SYNTHETIC",
            "name": "합성 발급기관",
            "official_url": "https://certificate.example.invalid/",
        },
    )
    certificate = post(
        c,
        h,
        "certificates",
        {
            "provider_id": provider["id"],
            "code": "SYN-CERT",
            "name": "합성 자격",
            "official_url": "https://certificate.example.invalid/cert",
        },
    )
    return provider, certificate


def test_all_five_criteria_publish_and_bridge_without_claiming_official_completion(
    auth_client, auth_db
):
    c = auth_client
    h, institution, context, _, chunk = setup(c, auth_db)
    course = post(
        c,
        h,
        "courses",
        {
            "name": "합성 설계",
            "institution_id": institution["id"],
            "code": "SYN1",
            "credits": "3",
        },
    )
    _, certificate = registry(c, h)
    group, rules = metadata(
        c, h, institution, ["credits", "required_course", "volunteer", "certificate", "thesis"]
    )
    conditions = [
        {"kind": "minimum_credits", "minimum": "3"},
        {
            "kind": "required_courses",
            "courses": [
                {
                    "course_id": course["id"],
                    "expected_version": course["version"],
                    "minimum_credits": "3",
                    "minimum_grade_points": "2",
                    "comparison_grade_scale": "4.5",
                }
            ],
        },
        {"kind": "minimum_volunteer_hours", "minimum": "10"},
        {
            "kind": "any_certificate",
            "certificates": [
                {"certificate_id": certificate["id"], "expected_version": certificate["version"]}
            ],
        },
        {"kind": "thesis", "thesis_type": "graduation", "accepted_grades": ["PASS"]},
    ]
    draft = post(c, h, "rule-programs", payload(group, rules, conditions, chunk))
    assert not draft["usable"] and not draft["missing_rule_ids"]
    student = authorization(register(c))
    assert c.get(PUBLIC + "/" + draft["id"], headers=student).status_code == 404
    assert (
        select_programs(c, student, context)["issues"][0]["reason"] == "execution_program_required"
    )
    approved = approve(c, h, draft)
    assert approved["usable"]
    selected = select_programs(c, student, context)
    assert selected["status"] == "available" and selected["catalog_complete"] is False
    assert len(selected["programs"][0]["rules"]) == 5
    assert "review_note" not in selected["programs"][0]
    assert selected["programs"][0]["rules"][1]["evidence"]
    with auth_db() as db:
        internal = as_core(
            db, db.get(RuleProgram, UUID(approved["id"])), "single_major", datetime.now(UTC).date()
        )
    core_context = AcademicContext.model_validate(context)
    unknown = evaluate_official(
        (internal,), Snapshot(), core_context, as_of=datetime.now(UTC).date()
    )
    assert unknown.status.value == "needs_review"
    assert len(unknown.results) == 5
    # Only this isolated unit fixture asserts trusted provenance and complete
    # coverage. The HTTP selection contract always keeps catalog_complete false.
    synthetic = {
        "academics": [
            {
                "id": str(uuid4()),
                "course_id": course["id"],
                "completion_status": "completed",
                "earned_credits": "3",
                "grade_points": "2",
                "grade_scale": "4.5",
            }
        ],
        "volunteers": [{"id": str(uuid4()), "approval_status": "approved", "approved_hours": "10"}],
        "certificates": [
            {
                "id": str(uuid4()),
                "certificate_id": certificate["id"],
                "approval_status": "approved",
                "validity_known": True,
            }
        ],
        "theses": [
            {
                "id": str(uuid4()),
                "thesis_type": "graduation",
                "approval_status": "approved",
                "is_completed": True,
                "grade": "PASS",
            }
        ],
    }
    for hours, expected in [("10", "satisfied"), ("9.99", "not_satisfied")]:
        synthetic["volunteers"][0]["approved_hours"] = hours
        result = evaluate_official(
            (internal,),
            Snapshot.model_validate(synthetic),
            core_context,
            as_of=datetime.now(UTC).date(),
            catalog_complete=True,
        )
        assert result.status.value == expected
    approve(c, student, approved, 403)
    post(
        c,
        student,
        "rule-programs/" + approved["id"] + "/revoke",
        {"expected_version": approved["version"], "reason": "불가"},
        403,
    )
    assert (
        c.delete(
            ROOT + "/" + approved["id"], headers=h, params={"expected_version": approved["version"]}
        ).status_code
        == 409
    )
    refs = c.get("/api/v1/admin/courses/" + course["id"] + "/references", headers=h)
    assert refs.status_code == 200 and approved["id"] in refs.text


def test_missing_rules_draft_replacement_overlap_and_terminal_revocation(auth_client, auth_db):
    c = auth_client
    h, institution, context, _, chunk = setup(c, auth_db)
    group, rules = metadata(c, h, institution, ["credits", "volunteer"])
    conditions = [
        {"kind": "minimum_credits", "minimum": "3"},
        {"kind": "minimum_volunteer_hours", "minimum": "10"},
    ]
    body = payload(group, rules, conditions, chunk)
    draft = post(c, h, "rule-programs", {**body, "rules": body["rules"][:1]})
    assert draft["missing_rule_ids"] == [rules[1]["id"]]
    approve(c, h, draft, 422)
    approve(c, h, draft, 422, conditions_verified=False)
    replacement = {
        key: value
        for key, value in body.items()
        if key not in ("rule_set_id", "expected_source_version")
    }
    result = c.put(
        ROOT + "/" + draft["id"],
        headers=h,
        json={**replacement, "expected_version": draft["version"]},
    )
    assert result.status_code == 200, result.text
    draft = result.json()
    assert draft["version"] == 2 and not draft["missing_rule_ids"]
    assert (
        c.put(
            ROOT + "/" + draft["id"], headers=h, json={**replacement, "expected_version": 1}
        ).status_code
        == 409
    )
    approved = approve(c, h, draft)
    assert (
        c.put(
            ROOT + "/" + draft["id"],
            headers=h,
            json={**replacement, "expected_version": approved["version"]},
        ).status_code
        == 409
    )
    overlapping = post(c, h, "rule-programs", body)
    approve(c, h, overlapping, 409)
    other_track = post(c, h, "rule-programs", {**body, "tracks": ["double_major"]})
    approve(c, h, other_track)
    assert (
        c.delete(
            ROOT + "/" + overlapping["id"],
            headers=h,
            params={"expected_version": overlapping["version"]},
        ).status_code
        == 204
    )
    with auth_db() as db:
        assert (
            db.scalar(
                select(func.count())
                .select_from(ProgramRule)
                .where(ProgramRule.program_id == UUID(overlapping["id"]))
            )
            == 0
        )
    revoked = post(
        c,
        h,
        "rule-programs/" + approved["id"] + "/revoke",
        {"expected_version": approved["version"], "reason": "합성 회수"},
        200,
    )
    assert revoked["status"] == "revoked" and not revoked["usable"]
    assert select_programs(c, h, context)["status"] == "needs_review"
    approve(c, h, revoked, 409)


def test_source_scope_versions_and_revocation_fail_closed(auth_client, auth_db):
    c = auth_client
    h, institution, context, knowledge, chunk = setup(c, auth_db)
    group, rules = metadata(c, h, institution, ["volunteer"])
    body = payload(group, rules, [{"kind": "minimum_volunteer_hours", "minimum": "10"}], chunk)
    post(c, h, "rule-programs", {**body, "admission_year_from": 2024}, 422)
    post(c, h, "rule-programs", {**body, "tracks": ["minor"]}, 422)
    post(c, h, "rule-programs", {**body, "expected_source_version": 1}, 409)
    post(
        c,
        h,
        "rule-programs",
        {**body, "rules": [{**body["rules"][0], "evidence_chunk_ids": [str(uuid4())]}]},
        404,
    )
    post(
        c,
        h,
        "rule-programs",
        {
            **body,
            "rules": [
                {**body["rules"][0], "condition": {"kind": "minimum_credits", "minimum": "10"}}
            ],
        },
        422,
    )
    approved = approve(c, h, post(c, h, "rule-programs", body))
    post(
        c,
        h,
        "knowledge-revisions/" + knowledge["id"] + "/revoke",
        {"expected_version": knowledge["version"], "reason": "합성 출처 회수"},
        200,
    )
    result = select_programs(c, h, context)
    assert result["status"] == "needs_review" and result["programs"] == []
    assert result["issues"][0]["reason"] == "program_dependency_unavailable"
    assert c.get(PUBLIC + "/" + approved["id"], headers=h).status_code == 404
    with auth_db() as db:
        assert db.scalar(select(func.count()).select_from(ProgramEvidence)) == 1


def test_certificate_registry_roles_snapshots_and_reference_protection(auth_client, auth_db):
    c = auth_client
    h, institution, context, _, chunk = setup(c, auth_db)
    student = authorization(register(c))
    provider, certificate = registry(c, h)
    post(
        c,
        student,
        "certificate-providers",
        {"code": "NO", "name": "불가", "official_url": "https://example.invalid"},
        403,
    )
    post(
        c,
        h,
        "scopes",
        {
            "user_id": c.get("/api/v1/auth/me", headers=student).json()["user"]["id"],
            "institution_id": institution["id"],
            "reason": "합성 범위",
        },
    )
    assert c.get("/api/v1/admin/certificates", headers=student).status_code == 200
    post(
        c,
        student,
        "certificates",
        {
            "code": "NO",
            "name": "불가",
            "official_url": "https://example.invalid",
            "provider_id": provider["id"],
        },
        403,
    )
    group, rules = metadata(c, h, institution, ["certificate"])
    body = payload(
        group,
        rules,
        [
            {
                "kind": "any_certificate",
                "certificates": [
                    {
                        "certificate_id": certificate["id"],
                        "expected_version": certificate["version"],
                    }
                ],
            }
        ],
        chunk,
    )
    approved = approve(c, student, post(c, student, "rule-programs", body))
    for resource, record in [("certificates", certificate), ("certificate-providers", provider)]:
        post(
            c,
            h,
            resource + "/" + record["id"] + "/deactivate",
            {"expected_version": record["version"]},
            409,
        )
        refs = c.get("/api/v1/admin/" + resource + "/" + record["id"] + "/references", headers=h)
        assert refs.status_code == 200 and approved["id"] in refs.text
    changed = c.patch(
        "/api/v1/admin/certificates/" + certificate["id"],
        headers=h,
        json={
            "expected_version": certificate["version"],
            "name": "변경된 합성 이름",
            "official_url": certificate["official_url"],
        },
    )
    assert changed.status_code == 200, changed.text
    result = select_programs(c, student, context)
    assert result["status"] == "available"
    assert result["programs"][0]["rules"][0]["references"][0]["name"] == certificate["name"]
    post(
        c,
        h,
        "rule-programs/" + approved["id"] + "/revoke",
        {"expected_version": approved["version"], "reason": "합성 회수"},
        200,
    )
    post(
        c,
        h,
        "certificates/" + certificate["id"] + "/deactivate",
        {"expected_version": changed.json()["version"]},
        200,
    )
    assert (
        c.get("/api/v1/catalog/certificates/" + certificate["id"], headers=student).status_code
        == 404
    )


def test_hierarchical_selection_keeps_manual_and_unmapped_requirements(auth_client, auth_db):
    c = auth_client
    h, institution, context, _, chunk = setup(c, auth_db)
    for scope, kind, condition in [
        ({}, "credits", {"kind": "minimum_credits", "minimum": "3"}),
        (
            {"department_id": context["department_id"]},
            "volunteer",
            {"kind": "minimum_volunteer_hours", "minimum": "10"},
        ),
        (
            {"department_id": context["department_id"], "curriculum_id": context["curriculum_id"]},
            "custom",
            {"kind": "manual_review", "instruction": "합성 외부 확인 필요"},
        ),
    ]:
        group, rules = metadata(c, h, institution, [kind], **scope)
        approve(c, h, post(c, h, "rule-programs", payload(group, rules, [condition], chunk)))
    result = select_programs(c, h, context)
    assert result["status"] == "needs_review" and len(result["programs"]) == 3
    assert [issue["reason"] for issue in result["issues"]] == ["manual_requirement"]
    standalone = post(
        c,
        h,
        "rules",
        {
            "name": "실행 조건 미등록 봉사",
            "institution_id": institution["id"],
            "rule_type": "volunteer",
            "definition": "설명만으로 실행하지 않음",
        },
    )
    post(
        c,
        h,
        "rules/" + standalone["id"] + "/apply",
        {"expected_version": standalone["version"]},
        200,
    )
    result = select_programs(c, h, context)
    assert len(result["programs"]) == 3
    assert {issue["reason"] for issue in result["issues"]} == {
        "manual_requirement",
        "execution_program_required",
    }
    assert select_programs(c, h, {**context, "admission_year": 2025})["programs"] == []
    for changed in [{"track": " "}, {"admission_year": 99999}, {"curriculum_id": str(uuid4())}]:
        result = c.get(PUBLIC, headers=h, params={**context, **changed})
        assert result.status_code == (404 if "curriculum_id" in changed else 422), result.text


def test_new_metadata_does_not_reuse_an_old_execution_approval(auth_client, auth_db):
    c = auth_client
    h, institution, context, _, chunk = setup(c, auth_db)
    group, rules = metadata(c, h, institution, ["volunteer"])
    approved = approve(
        c,
        h,
        post(
            c,
            h,
            "rule-programs",
            payload(
                group,
                rules,
                [{"kind": "minimum_volunteer_hours", "minimum": "10"}],
                chunk,
            ),
        ),
    )
    clone = post(
        c, h, "rule-sets/" + group["id"] + "/drafts", {"expected_version": group["version"]}
    )
    assert select_programs(c, h, context)["status"] == "available"
    post(c, h, "rule-sets/" + clone["id"] + "/apply", {"expected_version": clone["version"]}, 200)
    result = select_programs(c, h, context)
    assert result["programs"] == [] and result["status"] == "needs_review"
    assert result["issues"] == [
        {"kind": "rule_set", "record_id": clone["id"], "reason": "execution_program_required"}
    ]
    assert c.get(PUBLIC + "/" + approved["id"], headers=h).status_code == 404


def test_cross_school_access_and_revoked_administrators_cannot_publish(auth_client, auth_db):
    c = auth_client
    h, institution, _, _, chunk = setup(c, auth_db)
    other = school(c, h, "다른 합성대")
    group, rules = metadata(c, h, institution, ["volunteer"])
    body = payload(group, rules, [{"kind": "minimum_volunteer_hours", "minimum": "10"}], chunk)
    registered = register(c)
    school_admin = authorization(registered)
    post(c, school_admin, "rule-programs", body, 403)
    scope = post(
        c,
        h,
        "scopes",
        {
            "user_id": registered.json()["user"]["id"],
            "institution_id": other["id"],
            "reason": "합성 범위",
        },
    )
    post(c, school_admin, "rule-programs", body, 403)
    other_group, other_rules = metadata(c, h, other, ["volunteer"])
    post(
        c,
        school_admin,
        "rule-programs",
        payload(
            other_group, other_rules, [{"kind": "minimum_volunteer_hours", "minimum": "10"}], chunk
        ),
        422,
    )
    own = post(
        c,
        h,
        "scopes",
        {
            "user_id": registered.json()["user"]["id"],
            "institution_id": institution["id"],
            "reason": "합성 범위",
        },
    )
    draft = post(c, school_admin, "rule-programs", body)
    post(
        c,
        h,
        "scopes/" + own["id"] + "/revoke",
        {"expected_version": own["version"], "reason": "합성 범위 회수"},
        200,
    )
    assert c.get(ROOT + "/" + draft["id"], headers=school_admin).status_code == 403
    approve(c, school_admin, draft, 403)
    assert scope["institution_id"] == other["id"]


def test_stale_master_versions_inactive_certificates_and_foreign_courses_rejected(
    auth_client, auth_db
):
    c = auth_client
    h, institution, _, _, chunk = setup(c, auth_db)
    other = school(c, h, "다른 합성대")
    foreign_course = post(
        c,
        h,
        "courses",
        {"name": "다른 학교 과목", "institution_id": other["id"], "code": "OTHER", "credits": "3"},
    )
    group, rules = metadata(c, h, institution, ["required_course"])
    body = payload(
        group,
        rules,
        [
            {
                "kind": "required_courses",
                "courses": [{"course_id": foreign_course["id"], "expected_version": 1}],
            }
        ],
        chunk,
    )
    post(c, h, "rule-programs", body, 404)
    provider, certificate = registry(c, h)
    group, rules = metadata(c, h, institution, ["certificate"])
    body = payload(
        group,
        rules,
        [
            {
                "kind": "any_certificate",
                "certificates": [{"certificate_id": certificate["id"], "expected_version": 2}],
            }
        ],
        chunk,
    )
    post(c, h, "rule-programs", body, 409)
    body["rules"][0]["condition"]["certificates"][0]["expected_version"] = 1
    draft = post(c, h, "rule-programs", body)
    post(
        c,
        h,
        "certificate-providers/" + provider["id"] + "/deactivate",
        {"expected_version": provider["version"]},
        200,
    )
    approve(c, h, draft, 404)
    post(c, h, "rule-programs", body, 404)
    assert c.get("/api/v1/catalog/certificates/" + certificate["id"], headers=h).status_code == 404
