"""Server-side audit history filters keep the school scope and the existing page shape."""

from datetime import UTC, datetime, timedelta, timezone
from uuid import uuid4

import pytest
from sqlalchemy import select
from test_academic import department, operator, post, school
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import register

from app.models.identity import IdentityAudit, User

pytestmark = pytest.mark.integration
LOGS = "/api/v1/admin/audit-logs"


def history(c, h, expected=200, **params):
    response = c.get(LOGS, headers=h, params=params)
    assert response.status_code == expected, response.text
    return response.json()


def actions(c, h, **params):
    return sorted(row["action"] for row in history(c, h, **params)["items"])


@pytest.fixture
def events(auth_client, auth_db):
    c = auth_client
    h = operator(c, auth_db)
    a, b = school(c, h), school(c, h, "다른 합성대")
    dep, other = department(c, h, a), department(c, h, b, code="OTHER")
    course = post(
        c,
        h,
        "courses",
        {"name": "합성 과목", "institution_id": a["id"], "code": "C1", "credits": "3"},
    )
    changed = c.patch(
        "/api/v1/admin/courses/" + course["id"],
        headers=h,
        json={
            "name": "합성 과목 개정",
            "institution_id": a["id"],
            "code": "C1",
            "credits": "3",
            "expected_version": 1,
        },
    )
    assert changed.status_code == 200
    account = register(c, "audit-admin@example.test").json()
    scoped = {"Authorization": "Bearer " + account["access_token"]}
    post(
        c,
        h,
        "scopes",
        {"user_id": account["user"]["id"], "institution_id": a["id"], "reason": "합성 범위"},
    )
    with auth_db() as session:
        actor = session.scalar(select(User.id).where(User.email == "operator@example.test"))
    return c, h, scoped, a, b, dep, other, course, str(actor)


def test_kind_target_actor_and_action_filters(events):
    c, h, _, a, _, dep, _, course, actor = events
    assert actions(c, h, institution_id=a["id"], kind="department") == [
        "academic:department:create"
    ]
    assert actions(c, h, institution_id=a["id"], kind="course") == [
        "academic:course:create",
        "academic:course:update",
    ]
    assert actions(c, h, target_id=course["id"]) == [
        "academic:course:create",
        "academic:course:update",
    ]
    assert actions(c, h, kind="course", action="academic:course:update") == [
        "academic:course:update"
    ]
    assert actions(c, h, institution_id=a["id"], kind="scope") == ["scope_granted"]
    assert actions(c, h, institution_id=a["id"], kind="institution") == ["institution_created"]
    assert "academic:department:create" in actions(c, h, actor_id=actor)
    assert actions(c, h, actor_id=str(uuid4())) == []
    for row in history(c, h, kind="course")["items"]:
        assert row["kind"] == "course" and row["target_id"] == course["id"]
    # Every result of a kind filter carries that kind label.
    kinds = {row["kind"] for row in history(c, h, institution_id=a["id"], kind="account")["items"]}
    assert kinds <= {"account"}
    assert dep["id"] in {row["target_id"] for row in history(c, h, kind="department")["items"]}


def test_period_bounds_and_validation(events):
    c, h, *_ = events
    now = datetime.now(UTC)
    everything = actions(c, h)
    window = {
        "occurred_from": (now - timedelta(hours=1)).isoformat(),
        "occurred_to": (now + timedelta(hours=1)).isoformat(),
    }
    assert actions(c, h, **window) == everything
    assert actions(c, h, occurred_from=(now + timedelta(hours=1)).isoformat()) == []
    assert actions(c, h, occurred_to=(now - timedelta(hours=1)).isoformat()) == []
    # Offsets are honoured: the same instant in another time zone gives the same answer.
    seoul = (now - timedelta(hours=1)).astimezone(timezone(timedelta(hours=9)))
    assert seoul.isoformat().endswith("+09:00")
    assert actions(c, h, occurred_from=seoul.isoformat()) == everything
    history(c, h, 422, occurred_from="2026-11-08T00:00:00")
    history(c, h, 422, occurred_from=now.isoformat(), occurred_to=now.isoformat())
    history(c, h, 422, kind="classification-unknown")
    history(c, h, 422, action="")


def test_filters_keep_school_scope_and_pagination(events):
    c, h, scoped, a, b, dep, other, *_ = events
    seen = {row["target_id"] for row in history(c, scoped, kind="department")["items"]}
    assert seen == {dep["id"]} and other["id"] not in seen
    history(c, scoped, 403, institution_id=b["id"], kind="department")
    first = history(c, h, kind="course", limit=1)
    assert len(first["items"]) == 1 and first["next_cursor"]
    second = history(c, h, kind="course", limit=1, cursor=first["next_cursor"])
    assert len(second["items"]) == 1 and second["next_cursor"] is None
    assert first["items"][0]["id"] != second["items"][0]["id"]


def test_kind_filter_matches_the_kind_label_for_every_action_shape(auth_client, auth_db):
    """Catalog, workspace ("academic:<entity>_<verb>") and import actions filter by their label."""
    c = auth_client
    h = operator(c, auth_db)
    a = school(c, h)
    shapes = [
        "academic:course:create",
        "academic:curriculumCourse:update",
        "academic:classification:create",
        "academic:classification_create",
        "academic:track_create",
        "academic:curriculum_create",
        "academic:curriculum:delete",
        "academic:requirement_create",
        "academic:rule:update",
        "academic:institution:guidance_bind",
        "local_pdf_import:track",
        "local_pdf_import:requirement",
        "local_pdf_import:notes",
        "scope_granted",
    ]
    with auth_db() as session:
        for action in shapes:
            session.add(IdentityAudit(action=action, target_id=uuid4(), institution_id=a["id"]))
        session.commit()
    rows = history(c, h, institution_id=a["id"], limit=100)["items"]
    labels = {row["action"]: row["kind"] for row in rows if row["action"] in shapes}
    assert labels["academic:classification_create"] == "classification"
    assert labels["academic:track_create"] == "studyTrack"
    assert labels["academic:requirement_create"] == "rule"
    assert labels["local_pdf_import:notes"] == "other"
    for kind in sorted(set(labels.values())):
        found = {
            row["action"]
            for row in history(c, h, institution_id=a["id"], kind=kind, limit=100)["items"]
        }
        expected = {action for action, label in labels.items() if label == kind}
        assert expected <= found, kind
        assert not {action for action in found & set(shapes) if labels[action] != kind}, kind
