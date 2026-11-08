"""Course department, atomic course placement, and student course record provenance."""

from uuid import uuid4

import pytest
from sqlalchemy import select
from test_academic import department, operator, post, school
from test_academic_guidance import enroll
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register
from test_classifications import catalog, course

from app.models.academic import Course, CoursePlacementReceipt, CurriculumCourse
from app.models.identity import IdentityAudit

pytestmark = pytest.mark.integration
ADMIN = "/api/v1/admin/"
RECORDS = "/api/v1/me/course-records"


def rows(factory, statement):
    with factory() as session:
        return session.scalars(statement).all()


def patch(c, h, path, body, expected=200):
    response = c.patch(ADMIN + path, headers=h, json=body)
    assert response.status_code == expected, response.text
    return response.json()


def test_course_department_is_validated_kept_and_filtered(auth_client, auth_db):
    c = auth_client
    root = operator(c, auth_db)
    a, b = school(c, root), school(c, root, "다른 합성대")
    _, _, _, curriculum = catalog(c, root, a)
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
    category, _, track, curriculum = catalog(c, root, a)
    _, _, other_track, other_curriculum = catalog(c, root, b)
    client_id = str(uuid4())
    assert c.get(ADMIN + "course-placements/" + client_id, headers=root).status_code == 404
    created = placement(c, root, a, curriculum, client_id, classification_id=category["id"])
    assert created["replayed"] is False
    assert created["course"]["code"] == "OS201"
    link = created["curriculum_course"]
    assert (link["course_id"], link["name"]) == (created["course"]["id"], "합성 운영체제")
    assert (link["effective_classification_id"], link["classification_source"]) == (
        category["id"],
        "course",
    )
    # A retry of the same submission returns the committed result, never a second course.
    again = placement(c, root, a, curriculum, client_id, 200, classification_id=category["id"])
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
    # A failing link leaves no course behind: wrong-school curriculum, wrong-kind track.
    for bad in (
        {"curriculum": other_curriculum},
        {"curriculum": curriculum, "link_track": other_track["id"]},
        {"curriculum": curriculum, "link_track": category["id"]},
    ):
        body = {
            "client_id": str(uuid4()),
            "course": {
                "name": "합성 실패",
                "institution_id": a["id"],
                "code": "FAIL1",
                "credits": "3",
            },
            "link": {
                "curriculum_id": bad["curriculum"]["id"],
                "category": "major",
                "required": False,
                "track_id": bad.get("link_track"),
            },
        }
        response = c.post(ADMIN + "course-placements", headers=root, json=body)
        assert response.status_code == 409, response.text
        assert (
            c.get(ADMIN + "course-placements/" + body["client_id"], headers=root).status_code == 404
        )
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


def record(c, h, expected=201, **source):
    body = {"title": "합성 수강", "term": "2026-1", "category": "전공", "credits": "3", **source}
    response = c.post(RECORDS, headers=h, json=body)
    assert response.status_code == expected, response.text
    return response.json()


def test_course_records_keep_catalog_provenance(auth_client, auth_db):
    c = auth_client
    root = operator(c, auth_db)
    a, b = school(c, root), school(c, root, "다른 합성대")
    _, _, _, curriculum = catalog(c, root, a)
    _, _, _, other_curriculum = catalog(c, root, b)
    picked = placement(c, root, a, curriculum, str(uuid4()))
    elsewhere = placement(c, root, b, other_curriculum, str(uuid4()))
    unlinked = course(c, root, a, "SOLO")
    source = {
        "catalog_course_id": picked["course"]["id"],
        "catalog_course_version": 1,
        "curriculum_course_id": picked["curriculum_course"]["id"],
        "curriculum_course_version": 1,
    }
    owner = authorization(register(c, "provenance@example.test"))
    # Without a registered school nothing from the catalog can be attached.
    record(c, owner, 409, **source)
    enroll(c, owner, a["id"])
    saved = record(c, owner, **source)
    assert {key: saved[key] for key in source} == source
    assert saved["official"] is False and saved["credits"] == "3"
    plain = record(c, owner)
    assert plain["catalog_course_id"] is None
    # Pairs and link ownership are checked.
    record(c, owner, 422, catalog_course_id=picked["course"]["id"])
    record(
        c,
        owner,
        422,
        curriculum_course_id=source["curriculum_course_id"],
        curriculum_course_version=1,
    )
    record(
        c,
        owner,
        409,
        catalog_course_id=unlinked["id"],
        catalog_course_version=1,
        curriculum_course_id=source["curriculum_course_id"],
        curriculum_course_version=1,
    )
    record(c, owner, 409, catalog_course_id=elsewhere["course"]["id"], catalog_course_version=1)
    # A stale pick is refused; the catalog moved to version 2.
    patch(
        c,
        root,
        "courses/" + picked["course"]["id"],
        {
            "name": "합성 운영체제 개정",
            "institution_id": a["id"],
            "code": "OS201",
            "credits": "3",
            "expected_version": 1,
        },
    )
    stale = record(c, owner, 409, **source)
    assert "다시 조회" in stale["error"]["message"]
    # An existing pick survives unrelated edits after the catalog changed.
    edited = c.patch(
        RECORDS + "/" + saved["id"], headers=owner, json={"grade": "A", "expected_version": 1}
    )
    assert edited.status_code == 200, edited.text
    assert edited.json()["catalog_course_version"] == 1
    # Repointing to the current version works; clearing the provenance works.
    current = c.patch(
        RECORDS + "/" + saved["id"],
        headers=owner,
        json={"catalog_course_version": 2, "expected_version": 2},
    )
    assert current.status_code == 200, current.text
    cleared = c.patch(
        RECORDS + "/" + saved["id"],
        headers=owner,
        json={
            "catalog_course_id": None,
            "catalog_course_version": None,
            "curriculum_course_id": None,
            "curriculum_course_version": None,
            "expected_version": 3,
        },
    )
    assert cleared.status_code == 200 and cleared.json()["catalog_course_id"] is None
    # A record naming a catalog entry protects it without revealing whose record it is.
    kept = record(
        c,
        owner,
        catalog_course_id=picked["course"]["id"],
        catalog_course_version=2,
        curriculum_course_id=source["curriculum_course_id"],
        curriculum_course_version=1,
    )
    for path in (
        "courses/" + picked["course"]["id"],
        "curriculum-courses/" + source["curriculum_course_id"],
    ):
        refs = c.get(ADMIN + path + "/references", headers=root).json()["items"]
        assert {"kind": "protected_reference", "name": "보호된 연결 참조"}.items() <= refs[
            -1
        ].items()
        assert kept["owner_id"] not in str(refs)
    blocked = c.delete(
        ADMIN + "curriculum-courses/" + source["curriculum_course_id"],
        headers=root,
        params={"expected_version": 1},
    )
    assert blocked.status_code == 409
    assert rows(
        auth_db,
        select(CurriculumCourse).where(CurriculumCourse.id == source["curriculum_course_id"]),
    )
