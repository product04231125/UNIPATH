"""The graduation menu shows the published criteria the student applied, never a verdict."""

from uuid import uuid4

import pytest
from test_academic_guidance import bind
from test_admin_academic_workspace import ROOT, command
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_student_academic import academic_student as academic_student
from test_student_academic import activation, requirement

pytestmark = pytest.mark.integration
NODES = "/api/v1/me/academic-guidance/nodes/"


def node(env, node_id, headers=None, **params):
    response = env["c"].get(NODES + node_id, headers=headers or env["student"], params=params)
    assert response.status_code == 200, response.text
    return response.json()


def track_scope(track_id):
    return {"clauses": [{"track_mode": "selected", "track_ids": [track_id]}]}


def test_graduation_criteria_use_the_applied_published_requirements(academic_student):
    e = academic_student
    c, admin = e["c"], e["admin"]
    bind(c, admin, e["inst"]["id"])
    other = c.post(
        ROOT + "/study-tracks",
        headers=admin,
        json=command(institution_id=e["inst"]["id"], name="복수 경로"),
    ).json()

    # Before the student applies any requirements, the menu says how to see them.
    before = node(e, "credits")
    assert before["reason"] == "general_criteria" and before["criteria_kind"] == "minimum_credits"
    assert before["cards"] == [] and before["missing_fields"] == ["academic_requirements"]
    # Required courses come from the curriculum revision the student chose.
    courses = node(e, "courses")
    assert [card["title"] for card in courses["cards"]] == [e["cur"]["name"] + " 필수 과목"]
    assert courses["cards"][0]["table"]["grid"][1][:3] == ["합성 설계", "SHARED", "3.125"]
    assert courses["cards"][0]["sources"][0]["document_id"] == e["cur"]["id"]

    group, column, major, total, mine, theirs = [str(uuid4()) for _ in range(6)]
    credits = requirement(
        e,
        {
            "kind": "credit_table",
            "headers": [
                {"id": group, "label": "교양", "role": "group", "position": 0},
                # Positions order siblings only: the child comes before the next root.
                {"id": column, "label": "기초", "parent_id": group, "position": 5},
                {"id": major, "label": "전공", "position": 1},
                {"id": total, "label": "최소졸업이수학점", "role": "total", "position": 2},
            ],
            "rows": [
                {"id": mine, "label": "주전공", "scope": track_scope(e["track"]["id"])},
                {"id": theirs, "label": "복수전공", "scope": track_scope(other["id"])},
            ],
            "cells": [
                {"row_id": mine, "header_id": column, "state": "number", "value": "12"},
                {"row_id": mine, "header_id": major, "state": "number", "value": "66"},
                {"row_id": mine, "header_id": total, "state": "number", "value": "120"},
                {"row_id": theirs, "header_id": column, "state": "not_applicable"},
                {"row_id": theirs, "header_id": total, "state": "number", "value": "36"},
            ],
        },
    )
    requirement(
        e,
        {
            "kind": "checklist",
            "lines": [
                {"text": "(1) 졸업학점 120학점 이상을 취득한다."},
                {"text": "(3) 졸업작품 발표 또는 졸업시험에 합격한다."},
            ],
        },
    )
    requirement(
        e,
        {
            "kind": "certification",
            "groups": [
                {
                    "label": "외국어 영역",
                    "choice": "pickOne",
                    "items": [{"label": "공인 영어 점수"}],
                },
                {
                    "label": "인성 영역",
                    "choice": "pickOne",
                    "items": [{"label": "사회봉사 36시간 이상"}, {"label": "인성 교과 이수"}],
                },
            ],
        },
    )
    activation(e)

    shown = node(e, "credits")
    assert shown["state"] == "ready" and shown["missing_fields"] == []
    [card] = shown["cards"]
    assert card["type"] == "reference_table" and card["title"] == credits["name"]
    # Only the student's own track row, with the hierarchy spelled out.
    assert card["table"]["grid"] == [
        ["구분", "주전공"],
        ["교양 · 기초", "12"],
        ["전공", "66"],
        ["최소졸업이수학점", "120"],
    ]
    assert "판정이 아닙니다" in card["body"] and "2026학년도 입학" in card["body"]
    assert card["sources"][0]["document_id"] == credits["id"]
    assert all(key not in card or card[key] is None for key in ("status", "reason", "rule_id"))

    review = node(e, "review")["cards"]
    assert [card["type"] for card in review] == ["reference_text"]
    assert "120학점" in review[0]["body"] and "졸업작품" in review[0]["body"]
    thesis = node(e, "thesis")["cards"]
    assert (
        len(thesis) == 1 and "졸업작품" in thesis[0]["body"] and "120학점" not in thesis[0]["body"]
    )
    # Volunteer hours are one certification option here, shown with the groups above them.
    [volunteer] = node(e, "volunteer")["cards"]
    assert "인성 영역 (1개 선택): 사회봉사 36시간 이상" in volunteer["body"]
    assert "인성 교과 이수" not in volunteer["body"] and "공인 영어" not in volunteer["body"]
    certificate = node(e, "certificate")["cards"]
    assert "■ 외국어 영역 (1개 선택)" in certificate[0]["body"]
    assert "· 공인 영어 점수" in certificate[0]["body"]

    assert "다시 적용" not in shown["message"]
    # Changing the admission year makes the applied requirements stale; the menu says so.
    profile = c.get("/api/v1/me/planning-profile", headers=e["student"]).json()
    changed = c.patch(
        "/api/v1/me/planning-profile",
        headers=e["student"],
        json={"expected_version": profile["version"], "admission_year": 2025},
    )
    assert changed.status_code == 200, changed.text
    assert "다시 적용" in node(e, "credits")["message"]

    # An administrator previewing the school never sees a student's requirements.
    preview = node(e, "credits", headers=admin, institution_id=e["inst"]["id"])
    assert preview["cards"] == []


def test_criteria_without_matching_lines_say_so():
    from app.services.guidance_criteria import certification_matches, credit_grid

    assert (
        certification_matches(
            [
                {
                    "label": "외국어",
                    "choice": "pickN",
                    "pick_count": None,
                    "items": [{"label": "토익"}],
                    "groups": [],
                }
            ],
            ("봉사",),
        )
        == []
    )
    content = {
        "headers": [
            {"id": "h", "parent_id": None, "label": "합계\n학점", "role": "total", "position": 0}
        ],
        "rows": [{"id": "r", "label": "단일전공"}, {"id": "s", "label": "외국인"}],
        "cells": [{"row_id": "r", "header_id": "h", "state": "not_applicable"}],
    }
    assert credit_grid(content) == [["구분", "단일전공", "외국인"], ["합계 학점", "해당 없음", "-"]]
