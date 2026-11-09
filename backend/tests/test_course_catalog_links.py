"""Course department ownership and atomic course placement."""

from uuid import uuid4

import pytest
from sqlalchemy import select
from test_academic import department, operator, post, school
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register

from app.models.academic import Course, CoursePlacementReceipt
from app.models.identity import IdentityAudit

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


def placement(c, h, institution, curriculum, client_id, expected=201, **course_changes):
    body = {
        "client_id": client_id,
        "course": {
            "name": "합성 운영체제",
            "institution_id": institution["id"],
            "code": "OS201",
            "credits": "3",
            **course_changes,
        },
        "link": {"curriculum_id": curriculum["id"], "category": "major", "required": True},
    }
    response = c.post(ADMIN + "course-placements", headers=h, json=body)
    assert response.status_code == expected, response.text
    return response.json()


def test_course_placement_is_atomic_and_replayable(auth_client, auth_db):
    c = auth_client
    root = operator(c, auth_db)
    a, b = school(c, root), school(c, root, "다른 합성대")
    curriculum, other_curriculum = curriculum_of(c, root, a), curriculum_of(c, root, b)
    client_id = str(uuid4())
    assert c.get(ADMIN + "course-placements/" + client_id, headers=root).status_code == 404
    created = placement(c, root, a, curriculum, client_id)
    assert created["replayed"] is False
    assert created["course"]["code"] == "OS201"
    link = created["curriculum_course"]
    assert (link["course_id"], link["name"]) == (created["course"]["id"], "합성 운영체제")
    # A retry of the same submission returns the committed result, never a second course.
    again = placement(c, root, a, curriculum, client_id, 200)
    assert again["replayed"] is True and again["course"]["id"] == created["course"]["id"]
    lost = c.get(ADMIN + "course-placements/" + client_id, headers=root).json()
    assert lost["curriculum_course"]["id"] == link["id"]
    placement(c, root, a, curriculum, client_id, 409, code="OS999")
    assert len(rows(auth_db, select(Course).where(Course.code == "OS201"))) == 1
    actions = rows(
        auth_db,
        select(IdentityAudit.action).where(
            IdentityAudit.target_id.in_([created["course"]["id"], link["id"]])
        ),
    )
    assert sorted(actions) == ["academic:course:create", "academic:curriculumCourse:create"]
    # A failing link leaves no course behind: a curriculum from another school.
    body = {
        "client_id": str(uuid4()),
        "course": {"name": "합성 실패", "institution_id": a["id"], "code": "FAIL1", "credits": "3"},
        "link": {"curriculum_id": other_curriculum["id"], "category": "major", "required": False},
    }
    response = c.post(ADMIN + "course-placements", headers=root, json=body)
    assert response.status_code == 409, response.text
    assert c.get(ADMIN + "course-placements/" + body["client_id"], headers=root).status_code == 404
    assert rows(auth_db, select(Course).where(Course.code == "FAIL1")) == []
    # A duplicate course code also saves nothing.
    duplicate = placement(c, root, a, curriculum, str(uuid4()), 409)
    assert duplicate["error"]["code"] == "CONFLICT"
    # Receipts belong to the submitting administrator.
    account = register(c, "placement-admin@example.test").json()
    scoped = {"Authorization": "Bearer " + account["access_token"]}
    post(
        c,
        root,
        "scopes",
        {"user_id": account["user"]["id"], "institution_id": a["id"], "reason": "합성 범위"},
    )
    assert c.get(ADMIN + "course-placements/" + client_id, headers=scoped).status_code == 404
    placement(c, scoped, b, other_curriculum, str(uuid4()), 403)
    # Deleting what the submission created keeps the receipt; a retry reports it gone.
    c.delete(
        ADMIN + "curriculum-courses/" + link["id"], headers=root, params={"expected_version": 1}
    ).raise_for_status()
    gone = c.get(ADMIN + "course-placements/" + client_id, headers=root).json()
    assert gone["curriculum_course"] is None and gone["course"]["id"] == created["course"]["id"]
    assert rows(
        auth_db,
        select(CoursePlacementReceipt).where(CoursePlacementReceipt.client_id == client_id),
    )


def test_removed_classification_and_catalog_source_fields_are_refused(auth_client, auth_db):
    """The academic workspace owns classification and course record links (0027)."""
    c = auth_client
    root = operator(c, auth_db)
    a = school(c, root)
    curriculum = curriculum_of(c, root, a)
    assert c.get(ADMIN + "classifications", headers=root).status_code == 404
    course(c, root, a, "OLD1", 422, classification_id=str(uuid4()))
    course(c, root, a, "OLD2", 422, track_id=str(uuid4()))
    stale = placement(c, root, a, curriculum, str(uuid4()), 422, classification_id=str(uuid4()))
    assert stale["error"]["code"] == "VALIDATION_ERROR"
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
