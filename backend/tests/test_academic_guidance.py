import json
from pathlib import Path
from uuid import uuid4

import pytest
from test_academic import operator, school
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register
from test_graduation import ME, audit, fixture, review

from app.rag.guidance import catalog, respond
from app.rag.guidance.assets import asset_index, resolve_asset
from app.rag.guidance.bundles import BUNDLE_ID, bundles
from app.schemas.academic_guidance import AcademicGuidance

ROOT = "/api/v1/me/academic-guidance"
integration = pytest.mark.integration


def bind(c, root, institution_id):
    response = c.put(
        "/api/v1/admin/institutions/" + institution_id + "/academic-guidance",
        headers=root,
        json={
            "bundle_id": BUNDLE_ID,
            "edition": bundles()[BUNDLE_ID]["edition"],
            "expected_version": 0,
        },
    )
    assert response.status_code == 200, response.text
    return response.json()


def enroll(c, owner, institution_id):
    version = c.get("/api/v1/me/planning-profile", headers=owner).json()["version"]
    response = c.patch(
        "/api/v1/me/planning-profile",
        headers=owner,
        json={"institution_id": institution_id, "expected_version": version},
    )
    assert response.status_code == 200, response.text


def bound_student(c, db, email):
    """A student whose registered school shows the collected bundle."""
    root = operator(c, db)
    institution = school(c, root)
    bind(c, root, institution["id"])
    owner = authorization(register(c, email))
    enroll(c, owner, institution["id"])
    return owner


def test_every_collected_node_matches_the_published_contract():
    nodes = catalog()["nodes"]
    assert len(nodes) > 2000
    for node in nodes:
        AcademicGuidance.model_validate(respond(node["id"]))
    assert AcademicGuidance.model_validate(respond("unknown")).reason == "unknown_node"


def test_collected_sources_keep_a_verifiable_origin():
    for node in catalog()["nodes"]:
        value = respond(node["id"])
        if node["mode"] != "content" or value["state"] != "ready":
            continue
        for card in value["cards"]:
            if card["type"] == "reference_text" and "sources" not in card:
                continue
            assert card["sources"], node["id"]
            for source in card["sources"]:
                assert len(source["sha256"]) == 64, node["id"]


def test_unreviewed_ocr_pages_prefer_the_original_image():
    for node in catalog()["nodes"]:
        for card in respond(node["id"])["cards"]:
            if card.get("extraction_status") == "ocr_unreviewed":
                assert card["preferred_view"] == "image" and card["image_asset_id"]


def test_asset_resolver_rejects_everything_outside_the_verified_index():
    for value in ("../../.env", "a" * 64, "", "A" * 64):
        with pytest.raises(ValueError):
            resolve_asset(value)
    identifier, relative = next(iter(asset_index().items()))
    assert resolve_asset(identifier).name == Path(relative).name


@integration
def test_guidance_requires_login_and_navigates_without_personal_data(auth_client, auth_db):
    c = auth_client
    assert c.get(ROOT + "/nodes/home").status_code == 401
    owner = bound_student(c, auth_db, "guidance@example.test")
    home = c.get(ROOT + "/nodes/home", headers=owner)
    assert home.status_code == 200, home.text
    assert home.headers["Cache-Control"] == "no-store"
    labels = {button["label"] for button in home.json()["buttons"]}
    assert {"졸업", "학사일정", "대학규정", "취업 분석"} <= labels
    assert "guidance@example.test" not in home.text
    month = c.get(ROOT + "/nodes/calendar:2026:11", headers=owner).json()
    assert month["state"] == "ready" and month["reason"] == "calendar_snapshot"
    assert all(card["type"] == "calendar_event" for card in month["cards"])
    # The card body never repeats the title and date shown in their own fields.
    for card in month["cards"]:
        assert card["title"] not in card["body"] and card["date_text"] not in card["body"]
    assert month["fetched_at"] and month["cards"][0]["sources"]
    assert c.get(ROOT + "/nodes/없는노드", headers=owner).status_code == 422
    assert c.get(ROOT + "/nodes/nope", headers=owner).json()["reason"] == "unknown_node"
    pending = c.get(ROOT + "/nodes/tuition", headers=owner).json()
    assert (pending["state"], pending["cards"]) == ("unavailable", [])


@integration
def test_assets_are_served_only_by_verified_hash_to_authenticated_users(auth_client, auth_db):
    c = auth_client
    owner = bound_student(c, auth_db, "asset@example.test")
    identifier, relative = next(iter(asset_index().items()))
    assert c.get(ROOT + "/assets/" + identifier).status_code == 401
    response = c.get(ROOT + "/assets/" + identifier, headers=owner)
    assert response.status_code == 200
    assert response.headers["content-type"] == (
        "application/pdf" if relative.endswith(".pdf") else "image/jpeg"
    )
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["content-disposition"] == "inline"
    assert response.headers["cache-control"] == "no-store"
    assert response.content.startswith(b"%PDF") or response.content[:3] == b"\xff\xd8\xff"
    assert c.get(ROOT + "/assets/" + "a" * 64, headers=owner).status_code == 404
    assert c.get(ROOT + "/assets/not-a-hash", headers=owner).status_code == 422


@integration
def test_workflow_state_reports_only_the_connected_analysis(auth_client, auth_db):
    c = auth_client
    owner = bound_student(c, auth_db, "workflow@example.test")
    assert (
        c.get(ROOT + "/nodes/career:posting", headers=owner).json()["integration_state"]
        == "adapter_not_connected"
    )
    c.app.state.job_analyzer = object()
    assert (
        c.get(ROOT + "/nodes/career:posting", headers=owner).json()["integration_state"]
        == "connected"
    )
    assert (
        c.get(ROOT + "/nodes/career:recommend", headers=owner).json()["integration_state"]
        == "adapter_not_connected"
    )


@integration
@pytest.mark.parametrize(
    "credits,status,card_status",
    [("3.5", "satisfied", "satisfied"), ("1", "not_satisfied", "not_satisfied")],
)
def test_guidance_presents_the_owner_audit_without_recomputing_it(
    auth_client, auth_db, credits, status, card_status
):
    c = auth_client
    root, inst, ctx, owner, *_ = fixture(c, auth_db, credits=credits)
    bind(c, root, inst["id"])
    enroll(c, owner, inst["id"])
    review(c, root, ctx)
    result, _ = audit(c, owner, ctx)
    assert result["status"] == status
    # Without an audit the item is general criteria, never a demand for personal results.
    general = c.get(ROOT + "/nodes/credits", headers=owner).json()
    assert (general["state"], general["reason"]) == ("ready", "general_criteria")
    assert general["criteria_kind"] == "minimum_credits" and general["cards"] == []
    assert general["buttons"][0] == {
        "id": "summary",
        "label": "내 충족 여부 보기",
        "action": "select_node",
        "node_id": "summary",
        "availability": "available",
    }
    summary = c.get(ROOT + "/nodes/summary", headers=owner).json()
    assert (summary["state"], summary["reason"]) == ("needs_input", "verified_audit_required")
    response = c.get(ROOT + "/nodes/credits", headers=owner, params={"audit_id": result["id"]})
    assert response.status_code == 200, response.text
    value = response.json()
    assert (value["state"], value["reason"]) == ("ready", "audit_rendered")
    assert value["audit"]["id"] == result["id"] and value["audit"]["status"] == status
    assert [card["type"] for card in value["cards"]] == ["audit_requirement"]
    assert value["cards"][0]["status"] == card_status
    guidance = c.get(ME + "/" + result["id"] + "/guidance", headers=owner).json()
    assert value["cards"][0]["status"] == guidance["requirements"][0]["status"]
    # A number passed by the client has no way into this response.
    assert "official" not in value["audit"]
    other = authorization(register(c, "guidance-other@example.test"))
    enroll(c, other, inst["id"])
    denied = c.get(ROOT + "/nodes/credits", headers=other, params={"audit_id": result["id"]})
    assert denied.status_code == 404
    missing = c.get(ROOT + "/nodes/credits", headers=owner, params={"audit_id": str(uuid4())})
    assert missing.status_code == 404
    assert "synthetic" not in json.dumps(value["warnings"])
