from uuid import uuid4

import pytest
from test_academic import department, operator, post, school
from test_admin_academic_workspace import ROOT, command, draft, tree
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db

pytestmark = pytest.mark.integration


def published_classification(c, h, inst):
    revision = draft(c, h, inst)
    saved, _ = tree(c, h, revision)
    url = ROOT + "/classification-revisions/" + saved["id"]
    preview = c.post(
        url + "/preview-publication", headers=h, json={"expected_version": saved["version"]}
    ).json()
    response = c.post(
        url + "/publish",
        headers=h,
        json=command(
            expected_version=saved["version"],
            expected_digest=preview["digest"],
            review_note="합성 검토",
        ),
    )
    assert response.status_code == 200, response.text
    published = response.json()
    leaf = next(n for n in published["nodes"] if n["selectable"])
    return published, leaf


def curriculum(c, h, inst, classification, **values):
    response = c.post(
        ROOT + "/curriculum-revisions",
        headers=h,
        json=command(
            institution_id=inst["id"],
            classification_revision_id=classification["id"],
            name="합성 교육과정",
            curriculum_year=2026,
            **values,
        ),
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_same_course_has_independent_curriculum_classification_and_atomic_retry(
    auth_client, auth_db
):
    c = auth_client
    h = operator(c, auth_db)
    inst = school(c, h)
    classification, leaf = published_classification(c, h, inst)
    first = curriculum(c, h, inst, classification)
    second = curriculum(c, h, inst, classification)
    url = ROOT + "/curriculum-revisions/" + first["id"]
    body = command(
        expected_version=first["version"],
        new_course={"name": "공통 설계", "code": "SHARED", "credits": "3.250"},
        classification_node_id=leaf["id"],
        requirement="required",
        recognized_credits="3.250",
    )
    response = c.post(url + "/course-entries", headers=h, json=body)
    assert response.status_code == 200, response.text
    saved = response.json()
    assert c.post(url + "/course-entries", headers=h, json=body).json() == saved
    assignment = saved["courses"][0]
    other = c.post(
        ROOT + "/curriculum-revisions/" + second["id"] + "/course-entries",
        headers=h,
        json=command(
            expected_version=second["version"],
            course_id=assignment["course_id"],
            expected_course_version=assignment["course_version"],
            classification_node_id=leaf["id"],
            requirement="elective",
            recognized_credits="2.000",
        ),
    )
    assert other.status_code == 200, other.text
    assert other.json()["courses"][0]["course_id"] == assignment["course_id"]
    assert other.json()["courses"][0]["requirement"] == "elective"
    reread = c.get(url, headers=h).json()
    assert reread["courses"][0]["requirement"] == "required"
    assert reread["courses"][0]["recognized_credits"] == "3.250"
    legacy_courses = c.get(
        "/api/v1/admin/courses", headers=h, params={"institution_id": inst["id"]}
    ).json()["items"]
    assert len(legacy_courses) == 1
    replaced = c.put(
        url,
        headers=h,
        json=command(
            expected_version=saved["version"],
            name="수정 교육과정",
            curriculum_year=2026,
            classification_revision_id=classification["id"],
            scope={"clauses": [{}]},
            courses=[
                {
                    "id": assignment["id"],
                    "course_id": assignment["course_id"],
                    "expected_course_version": assignment["course_version"],
                    "classification_node_id": leaf["id"],
                    "requirement": "required",
                    "recognized_credits": "2.500",
                    "position": 0,
                }
            ],
        ),
    )
    assert replaced.status_code == 200, replaced.text
    assert replaced.json()["courses"][0]["id"] == assignment["id"]
    assert replaced.json()["courses"][0]["logical_id"] == assignment["logical_id"]
    assert replaced.json()["courses"][0]["recognized_credits"] == "2.500"
    assert (
        c.get(ROOT + "/curriculum-revisions/" + second["id"], headers=h).json()["courses"][0][
            "recognized_credits"
        ]
        == "2.000"
    )


def test_invalid_classification_cannot_leave_partially_created_course(auth_client, auth_db):
    c = auth_client
    h = operator(c, auth_db)
    inst = school(c, h)
    classification, leaf = published_classification(c, h, inst)
    revision = curriculum(c, h, inst, classification)
    url = ROOT + "/curriculum-revisions/" + revision["id"]
    body = command(
        expected_version=revision["version"],
        new_course={"name": "원자 저장", "code": "ATOMIC", "credits": "3.000"},
        classification_node_id=str(uuid4()),
        requirement="required",
        recognized_credits="3.000",
    )
    rejected = c.post(url + "/course-entries", headers=h, json=body)
    assert rejected.status_code == 422, rejected.text
    rows = c.get("/api/v1/admin/courses", headers=h, params={"institution_id": inst["id"]}).json()[
        "items"
    ]
    assert rows == []
    assert c.get(url, headers=h).json()["version"] == revision["version"]
    # Rejected transactions leave no success receipt and the same key can be corrected.
    corrected = {**body, "classification_node_id": leaf["id"]}
    accepted = c.post(url + "/course-entries", headers=h, json=corrected)
    assert accepted.status_code == 200, accepted.text


def test_legacy_curriculum_is_preserved_and_unmapped_courses_block_publication(
    auth_client, auth_db
):
    c = auth_client
    h = operator(c, auth_db)
    inst = school(c, h)
    dep = department(c, h, inst)
    legacy = post(
        c,
        h,
        "curricula",
        {
            "name": "기존 교육과정",
            "institution_id": inst["id"],
            "department_id": dep["id"],
            "year": 2026,
        },
    )
    course = post(
        c,
        h,
        "courses",
        {"name": "기존 과목", "institution_id": inst["id"], "code": "KEEP", "credits": "3.000"},
    )
    link = post(
        c,
        h,
        "curriculum-courses",
        {
            "name": "기존 연결",
            "institution_id": inst["id"],
            "curriculum_id": legacy["id"],
            "course_id": course["id"],
            "category": "major",
            "required": True,
        },
    )
    classification, leaf = published_classification(c, h, inst)
    revision = curriculum(c, h, inst, classification, legacy_curriculum_id=legacy["id"])
    assert revision["scope"]["clauses"][0]["department_id"] == dep["id"]
    assert revision["scope"]["clauses"][0]["admission_from"] is None
    assert revision["legacy_courses"][0]["course_id"] == course["id"]
    url = ROOT + "/curriculum-revisions/" + revision["id"]
    preview = c.post(
        url + "/preview-publication", headers=h, json={"expected_version": revision["version"]}
    ).json()
    assert len(preview["issues"]) >= 1
    saved = c.post(
        url + "/course-entries",
        headers=h,
        json=command(
            expected_version=revision["version"],
            course_id=course["id"],
            expected_course_version=course["version"],
            classification_node_id=leaf["id"],
            requirement="required",
            recognized_credits="3.000",
        ),
    ).json()
    preview = c.post(
        url + "/preview-publication", headers=h, json={"expected_version": saved["version"]}
    ).json()
    assert preview["issues"] == []
    published = c.post(
        url + "/publish",
        headers=h,
        json=command(
            expected_version=saved["version"],
            expected_digest=preview["digest"],
            review_note="원본 연결 확인",
        ),
    )
    assert published.status_code == 200, published.text
    assert c.get("/api/v1/admin/curricula/" + legacy["id"], headers=h).json() == legacy
    assert c.get("/api/v1/admin/curriculum-courses/" + link["id"], headers=h).json() == link
    copied = c.post(
        url + "/drafts", headers=h, json=command(expected_version=published.json()["version"])
    )
    assert copied.status_code == 201, copied.text
    assert copied.json()["courses"][0]["logical_id"] == published.json()["courses"][0]["logical_id"]
    assert copied.json()["courses"][0]["id"] != published.json()["courses"][0]["id"]
    assert copied.json()["scope"] == published.json()["scope"]
    assert c.get(url, headers=h).json() == published.json()


def test_scope_references_cannot_cross_schools(auth_client, auth_db):
    c = auth_client
    h = operator(c, auth_db)
    inst, other = school(c, h), school(c, h, "다른 합성대")
    foreign_department = department(c, h, other)
    classification, _ = published_classification(c, h, inst)
    revision = curriculum(c, h, inst, classification)
    url = ROOT + "/curriculum-revisions/" + revision["id"]
    response = c.put(
        url,
        headers=h,
        json=command(
            expected_version=revision["version"],
            name=revision["name"],
            curriculum_year=2026,
            classification_revision_id=classification["id"],
            scope={"clauses": [{"department_id": foreign_department["id"]}]},
            courses=[],
        ),
    )
    assert response.status_code == 422, response.text
    assert c.get(url, headers=h).json()["scope"] == {"clauses": []}
