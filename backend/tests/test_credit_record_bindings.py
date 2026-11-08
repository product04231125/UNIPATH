from decimal import Decimal
from uuid import uuid4

import pytest
from test_admin_academic_workspace import ROOT, command
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_student_academic import ME, activation, requirement
from test_student_academic import academic_student as academic_student
from test_student_course_records import create

pytestmark = pytest.mark.integration


def table(e):
    a, b, total, unknown, row = [str(uuid4()) for _ in range(5)]
    doc = requirement(
        e,
        {
            "kind": "credit_table",
            "headers": [
                {"id": a, "label": "필수", "position": 0},
                {"id": b, "label": "선택", "position": 1},
                {
                    "id": total,
                    "label": "총계",
                    "position": 2,
                    "role": "total",
                    "aggregate_members": [a, b],
                },
                {"id": unknown, "label": "세부분류", "position": 3},
            ],
            "rows": [{"id": row, "label": "주전공"}],
            "cells": [
                {"row_id": row, "header_id": key, "state": "number", "value": "6"}
                for key in [a, b, total, unknown]
            ],
        },
    )
    return doc, a, b, total, unknown


def test_transcript_categories_count_without_pdf_course_links_and_preserve_snapshots(
    academic_student,
):
    e = academic_student
    doc, a, b, total, unknown = table(e)
    active = activation(e)
    url = ROOT + "/requirement-revisions/" + doc["id"] + "/record-bindings"
    body = command(expected_version=0, bindings={a: ["전공필수"], b: ["전공필수", "전공선택"]})
    response = e["c"].put(url, headers=e["admin"], json=body)
    assert response.status_code == 200, response.text
    assert e["c"].put(url, headers=e["admin"], json=body).json() == response.json()
    assert e["c"].get(ME + "academic-requirements", headers=e["student"]).json() == active
    completed = create(e, course_code="INTRANET-ONLY", category="전공필수", credits="3.125")
    create(e, course_code="K-OTHER", category="전공선택", credits="2.5")
    create(e, course_code="K-FAIL", category="전공필수", credits="4.5", completion="not_completed")
    create(e, course_code="K-PLAN", category="전공필수", credits="1.5", completion="planned")
    create(
        e, course_code="K-ONGOING", category="전공필수", credits="2.25", completion="in_progress"
    )

    def cells():
        r = e["c"].get(ME + "academic-credit-progress", headers=e["student"])
        assert r.status_code == 200, r.text
        assert r.json()["links"] == []
        return {x["header_id"]: x for x in r.json()["tables"][0]["cells"]}

    results = cells()
    assert Decimal(results[a]["earned"]) == Decimal("3.125")
    assert Decimal(results[total]["earned"]) == Decimal("5.625")
    assert Decimal(results[total]["planned"]) == Decimal("1.5")
    assert Decimal(results[total]["projected"]) == Decimal("7.125")
    assert Decimal(results[total]["in_progress"]) == Decimal("2.25")
    assert Decimal(results[total]["earned_with_in_progress"]) == Decimal("7.875")
    assert Decimal(results[total]["remaining"]) == Decimal("0.375")
    assert results[total]["status"] == "not_satisfied"
    assert results[unknown]["earned"] is None and results[unknown]["remaining"] is None
    assert results[unknown]["issues"] == ["transcript_subcategory_required"]
    changed = e["c"].patch(
        ME + "course-records/" + completed["id"],
        headers=e["student"],
        json={"expected_version": completed["version"], "completion": "not_completed"},
    )
    assert changed.status_code == 200, changed.text
    assert Decimal(cells()[total]["earned"]) == Decimal("2.5")
    # A genuine pair of completed attempts is not silently added twice.
    create(e, course_code="DUPLICATE", category="전공선택", credits="3")
    create(e, course_code="DUPLICATE", category="전공선택", credits="3")
    assert Decimal(cells()[total]["earned"]) == Decimal("2.5")
    assert cells()[total]["status"] == "needs_review"
    create(
        e,
        course_code="PF-UNKNOWN",
        category="전공필수",
        credits=None,
        grading_basis="pass_fail",
        completion="planned",
    )
    assert cells()[a]["planned"] is None
    assert cells()[total]["projected"] is None
    assert Decimal(cells()[total]["in_progress"]) == Decimal("2.25")
    create(
        e,
        course_code="PF-ONGOING",
        category="전공필수",
        credits=None,
        grading_basis="pass_fail",
        completion="in_progress",
    )
    assert cells()[total]["in_progress"] is None
    assert cells()[total]["earned_with_in_progress"] is None


def test_binding_scope_conflicts_unknown_headers_and_copy(academic_student):
    e = academic_student
    doc, a, b, total, unknown = table(e)
    url = ROOT + "/requirement-revisions/" + doc["id"] + "/record-bindings"
    assert e["c"].get(url, headers=e["student"]).status_code == 403
    assert (
        e["c"]
        .put(
            url, headers=e["student"], json=command(expected_version=0, bindings={a: ["전공필수"]})
        )
        .status_code
        == 403
    )
    invalid = e["c"].put(
        url,
        headers=e["admin"],
        json=command(expected_version=0, bindings={str(uuid4()): ["전공필수"]}),
    )
    assert invalid.status_code == 422, invalid.text
    saved = e["c"].put(
        url, headers=e["admin"], json=command(expected_version=0, bindings={a: ["전공필수"]})
    )
    assert saved.status_code == 200, saved.text
    assert (
        e["c"]
        .put(url, headers=e["admin"], json=command(expected_version=0, bindings={b: ["전공선택"]}))
        .status_code
        == 409
    )
    copied = e["c"].post(
        ROOT + "/requirement-revisions/" + doc["id"] + "/drafts",
        headers=e["admin"],
        json=command(expected_version=doc["version"]),
    )
    assert copied.status_code == 201, copied.text
    target = e["c"].get(
        ROOT + "/requirement-revisions/" + copied.json()["id"] + "/record-bindings",
        headers=e["admin"],
    )
    assert target.status_code == 200 and target.json()["bindings"] == {a: ["전공필수"]}
