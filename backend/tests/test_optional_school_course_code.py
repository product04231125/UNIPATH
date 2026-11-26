import pytest
from test_academic import operator, post, school
from test_admin_academic_curricula import curriculum, published_classification
from test_admin_academic_workspace import ROOT, command
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db


@pytest.mark.integration
def test_missing_school_numbers_have_distinct_ids_and_known_numbers_remain_unique(
    auth_client, auth_db
):
    c = auth_client
    h = operator(c, auth_db)
    inst = school(c, h)
    first = post(
        c, h, "courses", {"institution_id": inst["id"], "name": "번호 없는 과목", "credits": 3}
    )
    second = post(
        c,
        h,
        "courses",
        {"institution_id": inst["id"], "name": "번호 없는 과목", "code": "  ", "credits": 2},
    )
    assert first["id"] != second["id"] and first["code"] == second["code"] == ""
    known = {
        "institution_id": inst["id"],
        "name": "번호 있는 과목",
        "code": "K000123",
        "credits": 3,
    }
    registered = post(c, h, "courses", known)
    duplicate = c.post("/api/v1/admin/courses", headers=h, json=known)
    assert duplicate.status_code == 409, duplicate.text
    assert c.get("/api/v1/admin/courses/" + registered["id"], headers=h).json()["code"] == "K000123"
    classification, leaf = published_classification(c, h, inst)
    revision = curriculum(c, h, inst, classification)
    response = c.post(
        ROOT + "/curriculum-revisions/" + revision["id"] + "/course-entries",
        headers=h,
        json=command(
            expected_version=revision["version"],
            new_course={"name": "교육과정 신규 과목", "credits": 3},
            classification_node_id=leaf["id"],
            requirement="elective",
            recognized_credits="3",
        ),
    )
    assert response.status_code == 200, response.text
    entry = response.json()["courses"][0]
    assert entry["course_code"] == "" and entry["course_id"] not in (first["id"], second["id"])
