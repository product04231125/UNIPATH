from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from test_auth import PASSWORD, authorization, register
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db

from app.models.academic import Curriculum
from app.models.identity import IdentityAudit, Institution, User
from app.operations.users import bootstrap
from app.schemas.auth import RegisterRequest

pytestmark = pytest.mark.integration


def operator(client, db):
    with db() as session:
        bootstrap(
            session,
            RegisterRequest(
                email="operator@example.test", password=PASSWORD, display_name="합성 운영자"
            ),
        )
    result = client.post(
        "/api/v1/auth/login",
        json={"email": "operator@example.test", "password": PASSWORD, "session_mode": "bearer"},
    )
    assert result.status_code == 200
    return authorization(result)


def post(client, headers, path, value, expected=201):
    response = client.post("/api/v1/admin/" + path, headers=headers, json=value)
    assert response.status_code == expected, response.text
    return response.json()


def school(client, headers, name="합성대"):
    return post(client, headers, "institutions", {"name": name})


def department(client, headers, institution, code="CS"):
    return post(
        client,
        headers,
        "departments",
        {"name": "합성학과", "institution_id": institution["id"], "code": code},
    )


def test_catalog_crud_versions_and_references(auth_client, auth_db):
    c = auth_client
    h = operator(c, auth_db)
    inst = school(c, h)
    dep = department(c, h, inst)
    cur = post(
        c,
        h,
        "curricula",
        {
            "name": "2026 과정",
            "institution_id": inst["id"],
            "department_id": dep["id"],
            "year": 2026,
        },
    )
    course = post(
        c,
        h,
        "courses",
        {"name": "설계", "institution_id": inst["id"], "code": "A1", "credits": "3.5"},
    )
    link = post(
        c,
        h,
        "curriculum-courses",
        {
            "name": "필수 설계",
            "institution_id": inst["id"],
            "curriculum_id": cur["id"],
            "course_id": course["id"],
            "category": "major",
            "required": True,
        },
    )
    changed = c.patch(
        "/api/v1/admin/courses/" + course["id"],
        headers=h,
        json={
            "name": "새 설계",
            "institution_id": inst["id"],
            "code": "A1",
            "credits": "3.25",
            "expected_version": course["version"],
        },
    )
    assert changed.status_code == 200 and changed.json()["version"] == 2
    assert changed.json()["credits"] == "3.25"
    assert (
        c.patch(
            "/api/v1/admin/courses/" + course["id"],
            headers=h,
            json={
                "name": "오래된 수정",
                "institution_id": inst["id"],
                "code": "A1",
                "credits": "3",
                "expected_version": 1,
            },
        ).status_code
        == 409
    )
    refs = c.get("/api/v1/admin/courses/" + course["id"] + "/references", headers=h).json()
    assert refs["total"] == 1 and refs["items"][0]["id"] == link["id"]
    assert (
        c.delete(
            "/api/v1/admin/courses/" + course["id"] + "?expected_version=2", headers=h
        ).status_code
        == 409
    )
    assert (
        c.delete(
            "/api/v1/admin/curriculum-courses/" + link["id"] + "?expected_version=1", headers=h
        ).status_code
        == 204
    )
    assert (
        c.delete(
            "/api/v1/admin/courses/" + course["id"] + "?expected_version=2", headers=h
        ).status_code
        == 204
    )
    assert c.get("/api/v1/admin/courses/" + course["id"], headers=h).status_code == 404
    history = c.get("/api/v1/admin/audit-logs?institution_id=" + inst["id"], headers=h).json()[
        "items"
    ]
    assert any(
        e["target_id"] == course["id"] and e["action"] == "academic:course:delete" for e in history
    )


def test_school_scope_and_relational_boundaries(auth_client, auth_db):
    c = auth_client
    h = operator(c, auth_db)
    a, b = school(c, h), school(c, h, "다른 합성대")
    da, db = department(c, h, a), department(c, h, b)
    user = register(c).json()
    uh = {"Authorization": "Bearer " + user["access_token"]}
    post(
        c,
        h,
        "scopes",
        {"user_id": user["user"]["id"], "institution_id": a["id"], "reason": "합성 범위"},
    )
    rows = c.get("/api/v1/admin/departments", headers=uh).json()["items"]
    assert [r["id"] for r in rows] == [da["id"]]
    assert c.get("/api/v1/admin/departments/" + db["id"], headers=uh).status_code == 403
    assert (
        c.get("/api/v1/admin/audit-logs?institution_id=" + b["id"], headers=uh).status_code == 403
    )
    post(c, uh, "departments", {"name": "불가", "institution_id": b["id"], "code": "X"}, 403)
    post(
        c,
        h,
        "curricula",
        {"name": "잘못된 소속", "institution_id": a["id"], "department_id": db["id"], "year": 2026},
        409,
    )
    with auth_db() as session:
        actor = session.scalar(select(User.id).where(User.email == "operator@example.test"))
        session.add(
            Curriculum(
                name="직접 잘못된 소속",
                institution_id=a["id"],
                department_id=db["id"],
                year=2026,
                created_by=actor,
                updated_by=actor,
            )
        )
        with pytest.raises(IntegrityError):
            session.commit()
    assert (
        c.patch(
            "/api/v1/admin/departments/" + da["id"],
            headers=uh,
            json={
                "name": "이동 불가",
                "code": "CS",
                "institution_id": b["id"],
                "expected_version": 1,
            },
        ).status_code
        == 403
    )


def test_reviewed_group_is_atomic_immutable_and_clones_children(auth_client, auth_db):
    c = auth_client
    h = operator(c, auth_db)
    inst = school(c, h)
    scope = {"institution_id": inst["id"]}
    group = post(c, h, "rule-sets", {"name": "졸업 기준", **scope})
    definition = {
        "name": "학점 설명",
        **scope,
        "rule_set_id": group["id"],
        "rule_type": "credits",
        "definition": "검토할 기준 설명. 실행식이 아닙니다.",
    }
    rule = post(c, h, "rules", definition)
    post(c, h, "rule-sets/" + group["id"] + "/apply", {"expected_version": 1}, 409)
    latest = c.get("/api/v1/admin/rule-sets/" + group["id"], headers=h).json()
    applied = post(
        c, h, "rule-sets/" + group["id"] + "/apply", {"expected_version": latest["version"]}, 200
    )
    locked = c.get("/api/v1/admin/rules/" + rule["id"], headers=h).json()
    assert locked["status"] == "applied" and applied["applied_by"] == locked["applied_by"]
    assert (
        c.patch(
            "/api/v1/admin/rules/" + rule["id"],
            headers=h,
            json={**definition, "expected_version": locked["version"]},
        ).status_code
        == 409
    )
    assert (
        c.delete(
            "/api/v1/admin/rule-sets/"
            + group["id"]
            + "?expected_version="
            + str(applied["version"]),
            headers=h,
        ).status_code
        == 409
    )
    draft = post(
        c, h, "rule-sets/" + group["id"] + "/drafts", {"expected_version": applied["version"]}
    )
    assert draft["id"] != group["id"] and draft["lineage_id"] == group["lineage_id"]
    assert draft["revision"] == 2 and draft["status"] == "draft"
    post(
        c, h, "rule-sets/" + group["id"] + "/drafts", {"expected_version": applied["version"]}, 409
    )
    all_rules = c.get("/api/v1/admin/rules", headers=h).json()["items"]
    clone = next(r for r in all_rules if r["rule_set_id"] == draft["id"])
    assert (
        clone["status"] == "draft"
        and clone["revision"] == 2
        and clone["lineage_id"] == rule["lineage_id"]
    )
    assert next(r for r in all_rules if r["id"] == rule["id"])["status"] == "applied"


def test_documents_do_not_become_rag_approval_or_executable_rules(auth_client, auth_db):
    c = auth_client
    h = operator(c, auth_db)
    inst = school(c, h)
    body = {
        "name": "공식 규정 메타데이터",
        "institution_id": inst["id"],
        "document_type": "academic",
        "source_url": "https://example.test/rules.pdf",
    }
    for invalid in (
        {"source_url": "javascript:alert(1)"},
        {"source_url": "https://u:p@example.test"},
        {"effective_from": "2027-01-01", "effective_to": "2026-01-01"},
        {"eligible_for_official_answers": True},
    ):
        post(c, h, "documents", {**body, **invalid}, 422)
    doc = post(c, h, "documents", body)
    applied = post(
        c, h, "documents/" + doc["id"] + "/apply", {"expected_version": doc["version"]}, 200
    )
    assert applied["status"] == "applied" and "eligible_for_official_answers" not in applied
    assert (
        c.patch(
            "/api/v1/admin/documents/" + doc["id"],
            headers=h,
            json={**body, "expected_version": applied["version"]},
        ).status_code
        == 409
    )


def test_institution_deletion_preserves_audit_and_hides_archived_school(auth_client, auth_db):
    c = auth_client
    h = operator(c, auth_db)
    inst = school(c, h)
    change = c.patch(
        "/api/v1/admin/institutions/" + inst["id"],
        headers=h,
        json={
            "name": "합성 새 학교",
            "country_code": "KR",
            "official_url": "https://example.test",
            "expected_version": inst["version"],
        },
    )
    assert change.status_code == 200
    assert (
        c.delete(
            "/api/v1/admin/institutions/" + inst["id"] + "?expected_version=1", headers=h
        ).status_code
        == 409
    )
    assert (
        c.delete(
            "/api/v1/admin/institutions/" + inst["id"] + "?expected_version=2", headers=h
        ).status_code
        == 204
    )
    assert not c.get("/api/v1/admin/institutions", headers=h).json()["items"]
    assert c.get("/api/v1/admin/institutions/" + inst["id"], headers=h).status_code == 404
    with auth_db() as db:
        assert db.get(Institution, inst["id"]).deleted_at is not None
        assert db.scalar(
            select(IdentityAudit.id).where(IdentityAudit.action == "academic:institution:delete")
        )


def test_combined_user_access_change_is_atomic_and_revokes_sessions(auth_client, auth_db):
    c = auth_client
    h = operator(c, auth_db)
    student = register(c).json()
    uid = student["user"]["id"]
    sh = {"Authorization": "Bearer " + student["access_token"]}
    response = c.patch(
        "/api/v1/admin/users/" + uid + "/access",
        headers=h,
        json={"role": "school_admin", "account_status": "suspended", "expected_version": 1},
    )
    assert response.status_code == 200 and response.json()["version"] == 2
    assert (
        response.json()["role"] == "school_admin"
        and response.json()["account_status"] == "suspended"
    )
    assert c.get("/api/v1/auth/me", headers=sh).status_code == 401
    stale = c.patch(
        "/api/v1/admin/users/" + uid + "/access",
        headers=h,
        json={"role": "super_admin", "account_status": "active", "expected_version": 1},
    )
    assert stale.status_code == 409


def test_plain_users_and_revoked_admin_cannot_access_catalog(auth_client, auth_db):
    c = auth_client
    h = operator(c, auth_db)
    inst = school(c, h)
    user = register(c).json()
    uh = {"Authorization": "Bearer " + user["access_token"]}
    for path in [
        "departments",
        "curricula",
        "courses",
        "curriculum-courses",
        "rule-sets",
        "rules",
        "documents",
        "audit-logs",
    ]:
        assert c.get("/api/v1/admin/" + path, headers=uh).status_code == 403
    scope = post(
        c,
        h,
        "scopes",
        {"user_id": user["user"]["id"], "institution_id": inst["id"], "reason": "합성"},
    )
    post(
        c,
        h,
        "scopes/" + scope["id"] + "/revoke",
        {"expected_version": 1, "reason": "합성 회수 사유"},
        200,
    )
    post(
        c,
        uh,
        "departments",
        {"name": "회수 후 등록", "institution_id": inst["id"], "code": "X"},
        403,
    )
    assert not c.get("/api/v1/admin/departments", headers=uh).json()["items"]


def test_catalog_pagination_search_and_duplicate_codes(auth_client, auth_db):
    c = auth_client
    h = operator(c, auth_db)
    inst = school(c, h)
    ids = {department(c, h, inst, str(i))["id"] for i in range(3)}
    post(c, h, "departments", {"name": "중복 코드", "institution_id": inst["id"], "code": "0"}, 409)
    seen = []
    cursor = None
    while True:
        result = c.get(
            "/api/v1/admin/departments",
            headers=h,
            params={"limit": 1, **({"cursor": cursor} if cursor else {})},
        ).json()
        seen.extend(r["id"] for r in result["items"])
        cursor = result["next_cursor"]
        if cursor is None:
            break
    assert set(seen) == ids and len(seen) == 3
    assert not c.get("/api/v1/admin/departments?query=%25", headers=h).json()["items"]
    assert c.get("/api/v1/admin/departments/" + str(uuid4()), headers=h).status_code == 404
