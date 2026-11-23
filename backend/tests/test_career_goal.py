"""The target job each student saves; synthetic accounts only."""

import pytest
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register

from app.rag.career.goal import CareerGoalUpdate

PATH = "/api/v1/me/career-goal"


def test_goal_requires_login(client):
    assert client.get(PATH).status_code == 401
    assert client.put(PATH, json={"expected_version": 0}).status_code == 401


def test_goal_values_are_checked_before_saving():
    goal = CareerGoalUpdate(
        category_codes=["024"], keyword="  프론트엔드,  백엔드 ", expected_version=0
    )
    assert goal.keyword == "프론트엔드, 백엔드"
    for bad in (
        {"category_codes": ["999"]},
        {"category_codes": ["024", "024"]},
        {"keyword": "a,b,c,d,e,f"},
        {"keyword": "x" * 81},
    ):
        with pytest.raises(ValueError):
            CareerGoalUpdate(expected_version=0, **bad)


@pytest.mark.integration
def test_student_saves_and_updates_only_their_own_goal(auth_client):
    owner = authorization(register(auth_client))
    other = authorization(register(auth_client, "other@example.test"))

    empty = auth_client.get(PATH, headers=owner).json()
    assert empty["version"] == 0 and empty["category_codes"] == [] and empty["keyword"] == ""

    saved = auth_client.put(
        PATH,
        headers=owner,
        json={"category_codes": ["024"], "keyword": "프론트엔드", "expected_version": 0},
    )
    assert saved.status_code == 200
    assert saved.json()["version"] == 1
    assert saved.json()["category_label"] == "소프트웨어"

    stale = auth_client.put(
        PATH, headers=owner, json={"category_codes": ["02"], "expected_version": 0}
    )
    assert stale.status_code == 409
    updated = auth_client.put(
        PATH, headers=owner, json={"category_codes": ["02"], "keyword": "", "expected_version": 1}
    ).json()
    assert updated["version"] == 2 and updated["category_codes"] == ["02"]

    assert auth_client.get(PATH, headers=other).json()["version"] == 0
    bad = auth_client.put(
        PATH, headers=owner, json={"category_codes": ["999"], "expected_version": 2}
    )
    assert bad.status_code == 422
