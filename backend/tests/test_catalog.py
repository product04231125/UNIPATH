import pytest
from test_academic import department, operator, post, school
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register

pytestmark = pytest.mark.integration


def apply(client, headers, path, record):
    current = client.get("/api/v1/admin/" + path + "/" + record["id"], headers=headers).json()
    response = client.post(
        "/api/v1/admin/" + path + "/" + record["id"] + "/apply",
        headers=headers,
        json={"expected_version": current["version"]},
    )
    assert response.status_code == 200, response.text
    return response.json()


def test_catalog_hides_drafts_and_actors_and_filters_curriculum(auth_client, auth_db):
    c = auth_client
    h = operator(c, auth_db)
    student = authorization(register(c))
    inst = school(c, h)
    dep = department(c, h, inst)
    cur = post(
        c,
        h,
        "curricula",
        {
            "name": "합성 과정",
            "institution_id": inst["id"],
            "department_id": dep["id"],
            "year": 2026,
        },
    )
    course = post(
        c,
        h,
        "courses",
        {"name": "합성 과목", "institution_id": inst["id"], "code": "C1", "credits": "3"},
    )
    post(
        c,
        h,
        "curriculum-courses",
        {
            "name": "합성 연결",
            "institution_id": inst["id"],
            "curriculum_id": cur["id"],
            "course_id": course["id"],
            "category": "major",
            "required": True,
        },
    )
    unrelated = post(
        c,
        h,
        "courses",
        {"name": "다른 과목", "institution_id": inst["id"], "code": "C2", "credits": "3"},
    )
    group = post(c, h, "rule-sets", {"name": "합성 기준", "institution_id": inst["id"]})
    rule = post(
        c,
        h,
        "rules",
        {
            "name": "합성 요건",
            "institution_id": inst["id"],
            "rule_set_id": group["id"],
            "rule_type": "credits",
            "definition": "검토한 설명",
        },
    )
    doc = post(
        c,
        h,
        "documents",
        {
            "name": "합성 문서",
            "institution_id": inst["id"],
            "source_url": "https://example.test/rules",
            "document_type": "academic",
            "rule_id": rule["id"],
        },
    )
    for path, item in (("rule-sets", group), ("rules", rule), ("documents", doc)):
        assert c.get("/api/v1/catalog/" + path, headers=student).json()["items"] == []
        assert (
            c.get("/api/v1/catalog/" + path + "/" + item["id"], headers=student).status_code == 404
        )
    apply(c, h, "rule-sets", group)
    apply(c, h, "documents", doc)
    for path, item in (("rule-sets", group), ("rules", rule), ("documents", doc)):
        response = c.get("/api/v1/catalog/" + path + "/" + item["id"], headers=student)
        assert response.status_code == 200, response.text
        assert response.headers["Cache-Control"] == "no-store"
        assert response.json()["status"] == "applied"
        assert not {"created_by", "updated_by", "applied_by", "owner_id"} & response.json().keys()
    items = c.get(
        "/api/v1/catalog/courses", headers=student, params={"curriculum_id": cur["id"]}
    ).json()["items"]
    assert [x["id"] for x in items] == [course["id"]]
    assert unrelated["id"] not in {x["id"] for x in items}
    assert c.get("/api/v1/catalog/institutions").status_code == 401
    assert c.post("/api/v1/catalog/courses", headers=student, json={}).status_code == 405
    assert (
        c.get("/api/v1/catalog/rules", headers=student, params={"rule_set_id": group["id"]}).json()[
            "items"
        ][0]["id"]
        == rule["id"]
    )


def test_latest_applied_revision_is_selected_per_date_and_parent(auth_client, auth_db):
    c = auth_client
    h = operator(c, auth_db)
    student = authorization(register(c))
    inst = school(c, h)
    group = post(
        c,
        h,
        "rule-sets",
        {"name": "합성 기준", "institution_id": inst["id"], "effective_from": "2026-01-01"},
    )
    rule = post(
        c,
        h,
        "rules",
        {
            "name": "합성 요건",
            "institution_id": inst["id"],
            "rule_set_id": group["id"],
            "effective_from": "2026-01-01",
            "rule_type": "credits",
            "definition": "합성 설명",
        },
    )
    group = apply(c, h, "rule-sets", group)
    response = c.post(
        "/api/v1/admin/rule-sets/" + group["id"] + "/drafts",
        headers=h,
        json={"expected_version": group["version"]},
    )
    assert response.status_code == 201
    draft = response.json()
    changed = c.patch(
        "/api/v1/admin/rule-sets/" + draft["id"],
        headers=h,
        json={
            "name": "새 기준",
            "institution_id": inst["id"],
            "effective_from": "2027-01-01",
            "expected_version": draft["version"],
        },
    )
    assert changed.status_code == 200, changed.text
    draft = apply(c, h, "rule-sets", changed.json())
    for day, expected in [
        ("2025-12-31", []),
        ("2026-06-01", [group["id"]]),
        ("2028-01-01", [draft["id"]]),
    ]:
        result = c.get("/api/v1/catalog/rule-sets", headers=student, params={"as_of": day}).json()
        assert [row["id"] for row in result["items"]] == expected
    past = c.get("/api/v1/catalog/rules", headers=student, params={"as_of": "2026-06-01"}).json()[
        "items"
    ]
    future = c.get("/api/v1/catalog/rules", headers=student, params={"as_of": "2028-01-01"}).json()[
        "items"
    ]
    assert [r["id"] for r in past] == [rule["id"]]
    assert (
        len(future) == 1
        and future[0]["id"] != rule["id"]
        and future[0]["rule_set_id"] == draft["id"]
    )
    assert (
        c.get(
            "/api/v1/catalog/rule-sets/" + group["id"],
            headers=student,
            params={"as_of": "2028-01-01"},
        ).status_code
        == 404
    )


def test_catalog_scope_consistency_and_cursor_do_not_expose_archived_schools(auth_client, auth_db):
    c = auth_client
    h = operator(c, auth_db)
    student = authorization(register(c))
    first, second = school(c, h), school(c, h, "다른 합성대")
    dep = department(c, h, second)
    response = c.get(
        "/api/v1/catalog/departments",
        headers=student,
        params={
            "institution_id": first["id"],
            "department_id": dep["id"],
        },
    )
    assert response.status_code == 404
    page = c.get("/api/v1/catalog/institutions", headers=student, params={"limit": 1}).json()
    rest = c.get(
        "/api/v1/catalog/institutions", headers=student, params={"cursor": page["next_cursor"]}
    ).json()
    assert len(page["items"]) == 1 and len(rest["items"]) == 1
    assert page["items"][0]["id"] != rest["items"][0]["id"]
    assert (
        c.delete(
            "/api/v1/admin/institutions/" + first["id"] + "?expected_version=1", headers=h
        ).status_code
        == 204
    )

    assert c.get("/api/v1/catalog/institutions/" + first["id"], headers=student).status_code == 404


def test_profile_catalog_reference_blocks_delete_without_student_identity(auth_client, auth_db):
    c = auth_client
    h = operator(c, auth_db)
    account = register(c).json()
    student = {"Authorization": "Bearer " + account["access_token"]}
    inst = school(c, h)
    dep = department(c, h, inst)
    cur = post(
        c,
        h,
        "curricula",
        {
            "name": "합성 선택 과정",
            "institution_id": inst["id"],
            "department_id": dep["id"],
            "year": 2026,
        },
    )
    response = c.patch(
        "/api/v1/me/planning-profile",
        headers=student,
        json={
            "expected_version": 0,
            "institution_id": inst["id"],
            "department_id": dep["id"],
            "curriculum_id": cur["id"],
        },
    )
    assert response.status_code == 200, response.text
    refs = c.get("/api/v1/admin/curricula/" + cur["id"] + "/references", headers=h)
    assert refs.json()["total"] == 1 and refs.json()["items"][0]["kind"] == "protected_reference"
    assert account["user"]["id"] not in refs.text and account["user"]["email"] not in refs.text
    assert (
        c.delete(
            "/api/v1/admin/curricula/" + cur["id"] + "?expected_version=1", headers=h
        ).status_code
        == 409
    )
    assert (
        c.patch(
            "/api/v1/me/planning-profile",
            headers=student,
            json={
                "expected_version": 1,
                "institution_id": None,
                "department_id": None,
                "curriculum_id": None,
            },
        ).status_code
        == 200
    )
    assert (
        c.delete(
            "/api/v1/admin/curricula/" + cur["id"] + "?expected_version=1", headers=h
        ).status_code
        == 204
    )
