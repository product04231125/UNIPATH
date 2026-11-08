"""School classifications: IDs are identity, names are free text, schools never mix."""

import pytest
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from test_academic import department, operator, post, school
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register

from app.models.academic import Course
from app.models.identity import User

pytestmark = pytest.mark.integration
ADMIN = "/api/v1/admin/"


def classification(c, h, institution, kind, name, expected=201, **extra):
    body = {"name": name, "institution_id": institution["id"], "kind": kind, **extra}
    return post(c, h, "classifications", body, expected)


def catalog(c, h, institution):
    """A school's category, subcategory and track, plus one curriculum."""
    category = classification(c, h, institution, "category", "합성 전공")
    subcategory = classification(
        c, h, institution, "subcategory", "합성 전공심화", parent_id=category["id"]
    )
    track = classification(c, h, institution, "track", "합성 복수전공")
    dep = department(c, h, institution)
    curriculum = post(
        c,
        h,
        "curricula",
        {
            "name": "합성 교육과정",
            "institution_id": institution["id"],
            "department_id": dep["id"],
            "year": 2026,
        },
    )
    return category, subcategory, track, curriculum


def course(c, h, institution, code="CS101", expected=201, **extra):
    body = {
        "name": "합성 자료구조",
        "institution_id": institution["id"],
        "code": code,
        "credits": "3",
        **extra,
    }
    return post(c, h, "courses", body, expected)


def link(c, h, institution, curriculum, item, expected=201, **extra):
    body = {
        "name": "합성 연결",
        "institution_id": institution["id"],
        "curriculum_id": curriculum["id"],
        "course_id": item["id"],
        "category": "major",
        "required": True,
        **extra,
    }
    return post(c, h, "curriculum-courses", body, expected)


def patch(c, h, path, record, expected=200, **changes):
    ignored = IGNORED if path == "classifications" else IGNORED | {"status"}
    body = {k: v for k, v in record.items() if k not in ignored} | changes
    body["expected_version"] = record["version"]
    response = c.patch(ADMIN + path + "/" + record["id"], headers=h, json=body)
    assert response.status_code == expected, response.text
    return response.json()


IGNORED = {
    "id",
    "version",
    "created_by",
    "updated_by",
    "created_at",
    "updated_at",
    "effective_classification_id",
    "classification_source",
    "effective_track_id",
    "track_source",
}


@pytest.fixture
def setup(auth_client, auth_db):
    c = auth_client
    h = operator(c, auth_db)
    a, b = school(c, h), school(c, h, "다른 합성대")
    return c, h, a, b


def test_classification_ids_are_per_school_and_follow_the_hierarchy(setup):
    c, h, a, b = setup
    category, subcategory, track, _ = catalog(c, h, a)
    same_name = classification(c, h, b, "category", "합성 전공")
    assert same_name["id"] != category["id"]
    assert subcategory["parent_id"] == category["id"] and subcategory["status"] == "active"
    # A subcategory needs a parent, and only a subcategory may have one.
    classification(c, h, a, "subcategory", "부모 없음", 422)
    classification(c, h, a, "category", "부모 있음", 422, parent_id=category["id"])
    # The parent must be a category of the same school.
    classification(c, h, a, "subcategory", "경로 아래", 409, parent_id=track["id"])
    classification(c, h, a, "subcategory", "다른 학교", 409, parent_id=same_name["id"])
    # Renaming keeps the ID; the kind cannot change.
    renamed = patch(c, h, "classifications", category, name="합성 전공 개명")
    assert (renamed["id"], renamed["version"]) == (category["id"], 2)
    patch(c, h, "classifications", renamed, 409, kind="track")
    patch(c, h, "classifications", category, 409, name="오래된 버전")
    rows = c.get(ADMIN + "classifications", headers=h, params={"institution_id": a["id"]})
    assert {r["id"] for r in rows.json()["items"]} == {
        category["id"],
        subcategory["id"],
        track["id"],
    }


def test_link_overrides_course_defaults_and_students_see_the_effective_value(setup):
    c, h, a, _ = setup
    category, subcategory, track, curriculum = catalog(c, h, a)
    item = course(c, h, a, classification_id=subcategory["id"], track_id=track["id"])
    inherited = link(c, h, a, curriculum, item)
    assert (inherited["classification_id"], inherited["track_id"]) == (None, None)
    assert inherited["effective_classification_id"] == subcategory["id"]
    assert inherited["classification_source"] == "course"
    assert (inherited["effective_track_id"], inherited["track_source"]) == (track["id"], "course")
    overridden = patch(c, h, "curriculum-courses", inherited, classification_id=category["id"])
    assert overridden["effective_classification_id"] == category["id"]
    assert overridden["classification_source"] == "curriculum_course"
    assert overridden["track_source"] == "course"
    # An older client that omits the fields keeps the course defaults; null clears them.
    body = {
        "name": "합성 자료구조 개정",
        "institution_id": a["id"],
        "code": "CS101",
        "credits": "3",
    }
    response = c.patch(
        ADMIN + "courses/" + item["id"], headers=h, json={**body, "expected_version": 1}
    )
    assert response.status_code == 200, response.text
    assert response.json()["classification_id"] == subcategory["id"]
    cleared = c.patch(
        ADMIN + "courses/" + item["id"],
        headers=h,
        json={**body, "expected_version": 2, "track_id": None},
    ).json()
    assert (cleared["classification_id"], cleared["track_id"]) == (subcategory["id"], None)
    plain = course(c, h, a, code="CS102")
    empty = link(c, h, a, curriculum, plain)
    assert empty["effective_classification_id"] is None and empty["classification_source"] is None

    student = authorization(register(c, "classification-student@example.test"))
    rows = c.get(
        "/api/v1/catalog/curriculum-courses",
        headers=student,
        params={"curriculum_id": curriculum["id"]},
    ).json()["items"]
    shown = {row["id"]: row for row in rows}
    assert shown[overridden["id"]]["effective_classification_id"] == category["id"]
    # The course track was cleared above, so the inherited value follows it.
    assert shown[overridden["id"]]["effective_track_id"] is None
    assert "created_by" not in shown[overridden["id"]]
    listed = c.get(
        "/api/v1/catalog/classifications", headers=student, params={"institution_id": a["id"]}
    ).json()["items"]
    assert {(r["kind"], r["name"]) for r in listed} == {
        ("category", "합성 전공"),
        ("subcategory", "합성 전공심화"),
        ("track", "합성 복수전공"),
    }
    assert c.get(ADMIN + "classifications", headers=student).status_code == 403


def test_references_check_kind_school_and_active_state(setup):
    c, h, a, b = setup
    category, subcategory, track, curriculum = catalog(c, h, a)
    foreign = classification(c, h, b, "category", "다른 학교 전공")
    course(c, h, a, code="BAD1", expected=409, classification_id=track["id"])
    course(c, h, a, code="BAD2", expected=409, track_id=category["id"])
    course(c, h, a, code="BAD3", expected=409, classification_id=foreign["id"])
    item = course(c, h, a, classification_id=subcategory["id"])
    joined = link(c, h, a, curriculum, item, classification_id=subcategory["id"])

    paused = patch(c, h, "classifications", subcategory, status="inactive")
    # Existing links keep the paused value and can still be edited.
    kept = patch(c, h, "curriculum-courses", joined, name="합성 연결 수정")
    assert kept["classification_id"] == subcategory["id"]
    # New references to it, or to a child of a paused category, are refused.
    course(c, h, a, code="NEW1", expected=409, classification_id=subcategory["id"])
    patch(c, h, "classifications", paused, status="active")
    patch(c, h, "classifications", category, status="inactive")
    course(c, h, a, code="NEW2", expected=409, classification_id=subcategory["id"])

    student = authorization(register(c, "inactive-student@example.test"))
    listed = c.get(
        "/api/v1/catalog/classifications", headers=student, params={"institution_id": a["id"]}
    ).json()["items"]
    assert category["id"] not in {r["id"] for r in listed}
    hidden = c.get("/api/v1/catalog/classifications/" + category["id"], headers=student)
    assert hidden.status_code == 404
    inactive = c.get(
        ADMIN + "classifications",
        headers=h,
        params={"institution_id": a["id"], "status": "inactive"},
    ).json()["items"]
    assert [r["id"] for r in inactive] == [category["id"]]


def test_referenced_classifications_cannot_be_deleted(setup):
    c, h, a, _ = setup
    category, subcategory, track, curriculum = catalog(c, h, a)
    item = course(c, h, a, track_id=track["id"])
    refs = c.get(ADMIN + "classifications/" + track["id"] + "/references", headers=h).json()
    assert refs["items"] == [{"id": item["id"], "kind": "course", "name": item["name"]}]
    for target in (track, category):
        response = c.delete(
            ADMIN + "classifications/" + target["id"],
            headers=h,
            params={"expected_version": target["version"]},
        )
        assert response.status_code == 409
    removed = c.delete(
        ADMIN + "classifications/" + subcategory["id"],
        headers=h,
        params={"expected_version": subcategory["version"]},
    )
    assert removed.status_code == 204
    logs = c.get(ADMIN + "audit-logs", headers=h, params={"institution_id": a["id"]}).json()
    actions = [row["action"] for row in logs["items"] if row["kind"] == "classification"]
    assert actions.count("academic:classification:create") == 3
    assert "academic:classification:delete" in actions


def test_school_admins_stay_in_their_school_and_the_database_blocks_mixing(setup, auth_db):
    c, h, a, b = setup
    category, *_ = catalog(c, h, a)
    other = classification(c, h, b, "category", "다른 학교 전공")
    account = register(c, "classification-admin@example.test").json()
    scoped = {"Authorization": "Bearer " + account["access_token"]}
    post(
        c,
        h,
        "scopes",
        {"user_id": account["user"]["id"], "institution_id": a["id"], "reason": "합성 범위"},
    )
    rows = c.get(ADMIN + "classifications", headers=scoped).json()["items"]
    assert other["id"] not in {r["id"] for r in rows} and category["id"] in {r["id"] for r in rows}
    classification(c, scoped, b, "category", "범위 밖", 403)
    assert c.get(ADMIN + "classifications/" + other["id"], headers=scoped).status_code == 403
    with auth_db() as session:
        actor = session.scalar(select(User.id).where(User.email == "operator@example.test"))
        session.add(
            Course(
                name="직접 잘못된 분류",
                institution_id=a["id"],
                code="RAW1",
                credits=3,
                classification_id=other["id"],
                created_by=actor,
                updated_by=actor,
            )
        )
        with pytest.raises(IntegrityError):
            session.commit()
