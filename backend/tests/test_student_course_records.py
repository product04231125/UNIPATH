from decimal import Decimal
from uuid import uuid4

import pytest
from sqlalchemy import select
from test_admin_academic_workspace import command
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register
from test_student_academic import ME, activation, requirement
from test_student_academic import academic_student as academic_student

from app.models.personal import CourseRecord
from app.models.student_academic import StudentAcademicCourseLink

pytestmark = pytest.mark.integration


def ids(factory, model):
    with factory() as db:
        return list(db.scalars(select(model.id)))


def create(e, **values):
    body = {
        "title": "수강 설계",
        "term": "2026-1",
        "category": "기존 분류",
        "credits": "3.5",
        "completion": "recorded",
        **values,
    }
    r = e["c"].post(ME + "course-records", headers=e["student"], json=body)
    assert r.status_code == 201, r.text
    return r.json()


def test_course_selection_and_edits_update_earned_credits_atomically(academic_student):
    e = academic_student
    col, row = str(uuid4()), str(uuid4())
    requirement(
        e,
        {
            "kind": "credit_table",
            "headers": [
                {
                    "id": col,
                    "label": "학점",
                    "classification_node_id": e["leaf"]["id"],
                    "position": 0,
                }
            ],
            "rows": [{"id": row, "label": "주전공"}],
            "cells": [{"header_id": col, "row_id": row, "state": "number", "value": "4"}],
        },
    )
    activation(e)
    r = create(
        e, academic_context_id=e["context"]["id"], academic_entry_id=e["cur"]["courses"][0]["id"]
    )

    def progress():
        return e["c"].get(ME + "academic-credit-progress", headers=e["student"]).json()

    result = progress()
    assert Decimal(result["tables"][0]["cells"][0]["earned"]) == Decimal("3.125")
    assert result["links"][0]["earned_credits"] == "3.500"
    for completion, amount in [("not_completed", "0"), ("in_progress", "0"), ("recorded", "3.125")]:
        saved = e["c"].patch(
            ME + "course-records/" + r["id"],
            headers=e["student"],
            json={"expected_version": r["version"], "completion": completion},
        )
        assert saved.status_code == 200, saved.text
        r = saved.json()
        result = progress()
        assert Decimal(result["tables"][0]["cells"][0]["earned"]) == Decimal(amount)
        assert result["links"][0]["record_version"] == r["version"]
    stale = e["c"].patch(
        ME + "course-records/" + r["id"],
        headers=e["student"],
        json={"expected_version": 1, "completion": "not_completed"},
    )
    assert stale.status_code == 409
    # Ordinary metadata edits preserve completion and the school link.
    changed = e["c"].patch(
        ME + "course-records/" + r["id"],
        headers=e["student"],
        json={"expected_version": r["version"], "term": "2026-2"},
    )
    assert changed.status_code == 200, changed.text
    assert Decimal(progress()["tables"][0]["cells"][0]["earned"]) == Decimal("3.125")


def test_bad_or_foreign_selection_rolls_back_record_and_link(academic_student, auth_db):
    e = academic_student
    before = ids(auth_db, CourseRecord)
    response = e["c"].post(
        ME + "course-records",
        headers=e["student"],
        json={
            "title": "잘못된 연결",
            "term": "2026",
            "category": "전공",
            "credits": "3",
            "academic_context_id": e["context"]["id"],
            "academic_entry_id": str(uuid4()),
        },
    )
    assert response.status_code == 422, response.text
    assert ids(auth_db, CourseRecord) == before
    other = authorization(register(e["c"], "other@example.test"))
    response = e["c"].post(
        ME + "course-records",
        headers=other,
        json={
            "title": "타인 연결",
            "term": "2026",
            "category": "전공",
            "credits": "3",
            "academic_context_id": e["context"]["id"],
            "academic_entry_id": e["cur"]["courses"][0]["id"],
        },
    )
    assert response.status_code == 404, response.text


def test_bulk_resolves_only_unique_codes_preserves_notes_and_replays(academic_student, auth_db):
    e = academic_student
    known = create(e, course_code="SHARED", detail="원본 메모")
    unknown = create(e, title="합성 설계", course_code="NO-MATCH")
    missing = create(e, title="합성 설계", course_code="")
    state = e["c"].get(ME + "academic-contexts", headers=e["student"]).json()
    body = command(expected_version=state["version"])
    result = e["c"].post(
        ME + "course-records/resolve-academic-links", headers=e["student"], json=body
    )
    assert result.status_code == 200, result.text
    assert result.json()["linked_count"] == 1
    assert {x["record_id"] for x in result.json()["unresolved"]} == {unknown["id"], missing["id"]}
    assert (
        e["c"]
        .post(ME + "course-records/resolve-academic-links", headers=e["student"], json=body)
        .json()
        == result.json()
    )
    reread = e["c"].get(ME + "course-records/" + known["id"], headers=e["student"]).json()
    assert reread["detail"] == "원본 메모" and reread["completion"] == "recorded"
    assert reread["version"] == known["version"] + 1
    assert reread["academic_entry_id"] == e["cur"]["courses"][0]["id"]
    assert len(ids(auth_db, StudentAcademicCourseLink)) == 1
    assert len(ids(auth_db, CourseRecord)) == 3


def test_same_code_in_multiple_contexts_requires_selection(academic_student):
    e = academic_student
    from test_academic import department

    extra = department(e["c"], e["admin"], e["inst"], code="EXTRA")
    current = e["c"].get(ME + "academic-contexts", headers=e["student"]).json()
    base = {
        key: current["contexts"][0][key]
        for key in (
            "id",
            "department_id",
            "track_id",
            "curriculum_revision_id",
            "admission_year",
            "primary",
        )
    }
    updated = e["c"].put(
        ME + "academic-contexts",
        headers=e["student"],
        json=command(
            expected_version=current["version"],
            contexts=[
                base,
                {
                    **{key: value for key, value in base.items() if key != "id"},
                    "department_id": extra["id"],
                    "primary": False,
                },
            ],
        ),
    )
    assert updated.status_code == 200, updated.text
    record = create(e, course_code="SHARED")
    response = e["c"].post(
        ME + "course-records/resolve-academic-links",
        headers=e["student"],
        json=command(expected_version=updated.json()["version"]),
    )
    assert response.status_code == 200, response.text
    assert response.json()["linked_count"] == 0
    assert response.json()["unresolved"] == [{"record_id": record["id"], "reason": "ambiguous"}]
