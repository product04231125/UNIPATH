from uuid import uuid4

import pytest
from test_academic import operator, post, school
from test_admin_academic_curricula import curriculum, published_classification
from test_admin_academic_workspace import ROOT, command
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_student_academic import ME, activation, requirement
from test_student_academic import academic_student as academic_student

from app.models.academic import Course
from app.models.academic_workspace import AcademicCurriculumCourse

pytestmark = pytest.mark.integration


def test_pass_fail_unknown_zero_and_known_credits_round_trip(auth_client, auth_db):
    c = auth_client
    h = operator(c, auth_db)
    inst = school(c, h)
    classification, leaf = published_classification(c, h, inst)
    cur = curriculum(c, h, inst, classification)
    for credits in (None, 0, 3):
        response = c.post(
            ROOT + f"/curriculum-revisions/{cur['id']}/course-entries",
            headers=h,
            json=command(
                expected_version=cur["version"],
                new_course={
                    "name": f"P/F 실습 {credits}",
                    "grading_basis": "pass_fail",
                    "credits": credits,
                },
                classification_node_id=leaf["id"],
                requirement="elective",
                recognized_credits=credits,
            ),
        )
        assert response.status_code == 200, response.text
        cur = response.json()
        entry = cur["courses"][-1]
        assert entry["grading_basis"] == "pass_fail"
        assert entry["recognized_credits"] == (None if credits is None else f"{credits}.000")
        course = c.get("/api/v1/admin/courses/" + entry["course_id"], headers=h).json()
        assert course["grading_basis"] == "pass_fail"
        assert course["credits"] == entry["recognized_credits"]
        public = c.get("/api/v1/catalog/courses/" + entry["course_id"], headers=h)
        assert public.status_code == 200, public.text
        assert public.json()["credits"] == course["credits"]
        assert public.json()["grading_basis"] == "pass_fail"
    assert len({entry["id"] for entry in cur["courses"]}) == 3
    invalid = c.post(
        "/api/v1/admin/courses",
        headers=h,
        json={"institution_id": inst["id"], "name": "일반 학점 누락", "grading_basis": "graded"},
    )
    assert invalid.status_code == 422
    known = post(c, h, "courses", {"institution_id": inst["id"], "name": "일반 과목", "credits": 3})
    invalid_link = c.post(
        ROOT + f"/curriculum-revisions/{cur['id']}/course-entries",
        headers=h,
        json=command(
            expected_version=cur["version"],
            course_id=known["id"],
            expected_course_version=known["version"],
            classification_node_id=leaf["id"],
            requirement="required",
            recognized_credits=None,
        ),
    )
    assert invalid_link.status_code == 422


def test_unconfirmed_pass_fail_credits_are_not_counted_even_when_marked_completed(
    academic_student, auth_db
):
    e = academic_student
    with auth_db() as db:
        entry = db.get(AcademicCurriculumCourse, e["cur"]["courses"][0]["id"])
        entry.grading_basis, entry.recognized_credits = "pass_fail", None
        course = db.get(Course, entry.course_id)
        course.grading_basis, course.credits = "pass_fail", None
        db.commit()
    col, row = str(uuid4()), str(uuid4())
    requirement(
        e,
        {
            "kind": "credit_table",
            "headers": [
                {
                    "id": col,
                    "label": "전공",
                    "position": 0,
                    "classification_node_id": e["leaf"]["id"],
                }
            ],
            "rows": [{"id": row, "label": "기준"}],
            "cells": [{"row_id": row, "header_id": col, "state": "number", "value": "3"}],
        },
    )
    activation(e)
    record = (
        e["c"]
        .post(
            ME + "course-records",
            headers=e["student"],
            json={
                "title": "P/F 이수 기록",
                "term": "2026-1",
                "category": "전공",
                "credits": "3",
                "completion": "recorded",
                "grade": "P",
            },
        )
        .json()
    )
    linked = e["c"].put(
        ME + f"course-records/{record['id']}/academic-link",
        headers=e["student"],
        json=command(
            expected_version=0,
            expected_record_version=record["version"],
            context_id=e["context"]["id"],
            entry_id=e["cur"]["courses"][0]["id"],
            result="completed",
            earned_credits="3",
        ),
    )
    assert linked.status_code == 200, linked.text
    progress = e["c"].get(ME + "academic-credit-progress", headers=e["student"])
    assert progress.status_code == 200, progress.text
    cell = progress.json()["tables"][0]["cells"][0]
    assert cell["earned"] == "0" and cell["status"] == "needs_review"
    assert cell["evidence"][0]["reason"] == "recognized_credits_required"
    assert cell["evidence"][0]["credits"] is None
