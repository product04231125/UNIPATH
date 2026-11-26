"""Course department ownership and the removed duplicate classification and placement APIs."""

from uuid import uuid4

import pytest
from sqlalchemy import select
from test_academic import department, operator, post, school
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register

from app.models.academic import Course

pytestmark = pytest.mark.integration
ADMIN = "/api/v1/admin/"


def rows(factory, statement):
    with factory() as session:
        return session.scalars(statement).all()


def patch(c, h, path, body, expected=200):
    response = c.patch(ADMIN + path, headers=h, json=body)
    assert response.status_code == expected, response.text
    return response.json()


def curriculum_of(c, h, institution):
    dep = department(c, h, institution)
    body = {
        "name": "합성 교육과정",
        "institution_id": institution["id"],
        "department_id": dep["id"],
        "year": 2026,
    }
    return post(c, h, "curricula", body)


def course(c, h, institution, code="CS101", expected=201, **extra):
    body = {
        "name": "합성 자료구조",
        "institution_id": institution["id"],
        "code": code,
        "credits": "3",
        **extra,
    }
    return post(c, h, "courses", body, expected)


def test_course_department_is_validated_kept_and_filtered(auth_client, auth_db):
    c = auth_client
    root = operator(c, auth_db)
    a, b = school(c, root), school(c, root, "다른 합성대")
    curriculum = curriculum_of(c, root, a)
    own = department(c, root, a, "OWN")
    other = department(c, root, b, "OTHER")
    shared = course(c, root, a, "SHARED")
    assert shared["department_id"] is None
    owned = course(c, root, a, "OWNED", department_id=own["id"])
    assert owned["department_id"] == own["id"]
    course(c, root, a, "CROSS", 409, department_id=other["id"])
    # Omitting the field keeps the department; null clears it; a new one is allowed.
    body = {"name": "합성 이름 변경", "institution_id": a["id"], "code": "OWNED", "credits": "3"}
    kept = patch(c, root, "courses/" + owned["id"], {**body, "expected_version": 1})
    assert kept["department_id"] == own["id"]
    cleared = patch(
        c, root, "courses/" + owned["id"], {**body, "department_id": None, "expected_version": 2}
    )
    assert cleared["department_id"] is None
    moved = patch(
        c,
        root,
        "courses/" + owned["id"],
        {**body, "department_id": curriculum["department_id"], "expected_version": 3},
    )
    assert moved["department_id"] == curriculum["department_id"]
    # A department lists its own courses and those its curricula use, never shared ones.
    linked = course(c, root, a, "LINKED")
    post(
        c,
        root,
        "curriculum-courses",
        {
            "name": "합성 연결",
            "institution_id": a["id"],
            "curriculum_id": curriculum["id"],
            "course_id": linked["id"],
            "category": "major",
            "required": True,
        },
    )
    student = authorization(register(c, "dept-reader@example.test"))

    def codes(**params):
        response = c.get("/api/v1/catalog/courses", headers=student, params=params)
        assert response.status_code == 200, response.text
        return sorted(item["code"] for item in response.json()["items"])

    assert codes(institution_id=a["id"], department_id=curriculum["department_id"]) == [
        "LINKED",
        "OWNED",
    ]
    assert codes(institution_id=a["id"], curriculum_id=curriculum["id"]) == ["LINKED"]
    # A course still owned by a department blocks deleting that department.
    refs = c.get(ADMIN + "departments/" + curriculum["department_id"] + "/references", headers=root)
    assert {"id": owned["id"], "kind": "course", "name": "합성 이름 변경"} in refs.json()["items"]


def test_removed_duplicate_academic_apis_are_refused(auth_client, auth_db):
    """The academic workspace owns classification, course record links (0027) and
    curriculum placement (0028)."""
    c = auth_client
    root = operator(c, auth_db)
    a = school(c, root)
    curriculum = curriculum_of(c, root, a)
    assert c.get(ADMIN + "classifications", headers=root).status_code == 404
    course(c, root, a, "OLD1", 422, classification_id=str(uuid4()))
    course(c, root, a, "OLD2", 422, track_id=str(uuid4()))
    link = {
        "name": "합성 연결",
        "institution_id": a["id"],
        "curriculum_id": curriculum["id"],
        "course_id": course(c, root, a, "LINK1")["id"],
        "category": "major",
        "required": True,
    }
    post(c, root, "curriculum-courses", {**link, "track_id": str(uuid4())}, 422)
    for path in ("course-placements", "course-placements/" + str(uuid4())):
        assert c.get(ADMIN + path, headers=root).status_code in (404, 405)
    assert c.post(ADMIN + "course-placements", headers=root, json={}).status_code in (404, 405)
    student = authorization(register(c, "removed-fields@example.test"))
    response = c.post(
        "/api/v1/me/course-records",
        headers=student,
        json={
            "title": "합성 수강",
            "term": "2026-1",
            "category": "전공",
            "credits": "3",
            "catalog_course_id": str(uuid4()),
            "catalog_course_version": 1,
        },
    )
    assert response.status_code == 422, response.text
    assert rows(auth_db, select(Course).where(Course.code.in_(["OLD1", "OLD2"]))) == []
