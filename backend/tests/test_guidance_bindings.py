"""A school shows collected guidance only after an administrator links a bundle to it."""

import pytest
from test_academic import operator, post, school
from test_academic_guidance import bind, enroll
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register

from app.rag.guidance.assets import asset_index
from app.rag.guidance.bundles import BUNDLE_ID, bundles

pytestmark = pytest.mark.integration
ADMIN = "/api/v1/admin/institutions/"
ME = "/api/v1/me/academic-guidance"


def binding_path(institution):
    return ADMIN + institution["id"] + "/academic-guidance"


def save(c, h, institution, version, expected=200, **changes):
    body = {
        "bundle_id": BUNDLE_ID,
        "edition": bundles()[BUNDLE_ID]["edition"],
        "expected_version": version,
        **changes,
    }
    response = c.put(binding_path(institution), headers=h, json=body)
    assert response.status_code == expected, response.text
    return response.json()


def test_bundle_list_and_binding_lifecycle(auth_client, auth_db):
    c = auth_client
    root = operator(c, auth_db)
    a = school(c, root)
    listed = c.get("/api/v1/admin/academic-guidance-bundles", headers=root).json()["items"]
    assert [item["bundle_id"] for item in listed] == [BUNDLE_ID]
    assert listed[0]["source_school"] == "경동대학교" and len(listed[0]["edition"]) == 16
    empty = c.get(binding_path(a), headers=root).json()
    assert (empty["state"], empty["version"], empty["bundle"]) == ("unbound", 0, None)
    save(c, root, a, 0, 409, edition="0" * 16)
    save(c, root, a, 0, 404, bundle_id="missing-bundle")
    save(c, root, a, 0, 422, bundle_id="Not A Slug")
    bound = save(c, root, a, 0)
    assert (bound["state"], bound["version"], bound["edition_changed"]) == ("bound", 1, False)
    assert bound["bundle"]["bundle_id"] == BUNDLE_ID and bound["updated_by"]
    save(c, root, a, 0, 409)
    replaced = save(c, root, a, 1)
    assert replaced["version"] == 2
    stale = c.delete(binding_path(a), headers=root, params={"expected_version": 1})
    assert stale.status_code == 409
    removed = c.delete(binding_path(a), headers=root, params={"expected_version": 2})
    assert removed.status_code == 200 and removed.json()["state"] == "unbound"
    logs = c.get(
        "/api/v1/admin/audit-logs", headers=root, params={"institution_id": a["id"]}
    ).json()["items"]
    actions = [row["action"] for row in logs if row["kind"] == "institution"]
    assert actions.count("academic:institution:guidance_bind") == 2
    assert "academic:institution:guidance_unbind" in actions


def test_school_admins_and_students_cannot_manage_other_links(auth_client, auth_db):
    c = auth_client
    root = operator(c, auth_db)
    a, b = school(c, root), school(c, root, "다른 합성대")
    account = register(c, "binding-admin@example.test").json()
    scoped = {"Authorization": "Bearer " + account["access_token"]}
    post(
        c,
        root,
        "scopes",
        {"user_id": account["user"]["id"], "institution_id": a["id"], "reason": "합성 범위"},
    )
    save(c, scoped, a, 0)
    save(c, scoped, b, 0, 403)
    assert c.get(binding_path(b), headers=scoped).status_code == 403
    student = authorization(register(c, "binding-student@example.test"))
    assert c.get("/api/v1/admin/academic-guidance-bundles", headers=student).status_code == 403
    save(c, student, a, 1, 403)
    assert (
        c.delete(binding_path(a), headers=student, params={"expected_version": 1}).status_code
        == 403
    )


def test_students_only_see_their_registered_and_linked_school(auth_client, auth_db):
    c = auth_client
    root = operator(c, auth_db)
    a, b = school(c, root), school(c, root, "다른 합성대")
    identifier = next(iter(asset_index()))
    owner = authorization(register(c, "binding-reader@example.test"))

    def home(**params):
        response = c.get(ME + "/nodes/home", headers=owner, params=params)
        assert response.status_code == 200, response.text
        return response.json()

    def state():
        return c.get(ME + "/binding", headers=owner).json()

    # No registered school: nothing collected is shown.
    assert state()["state"] == "school_required"
    value = home()
    assert (value["state"], value["reason"]) == ("needs_input", "school_required")
    assert value["cards"] == [] and value["buttons"] == []
    assert c.get(ME + "/assets/" + identifier, headers=owner).status_code == 404
    # A registered school without a link shows nothing either.
    enroll(c, owner, a["id"])
    assert state()["state"] == "unbound"
    value = home()
    assert (value["state"], value["reason"]) == ("unavailable", "school_guidance_not_connected")
    assert c.get(ME + "/assets/" + identifier, headers=owner).status_code == 404
    # Linking another school does not leak into this one.
    bind(c, root, b["id"])
    assert home()["reason"] == "school_guidance_not_connected"
    assert (
        c.get(ME + "/nodes/home", headers=owner, params={"institution_id": b["id"]}).status_code
        == 404
    )
    # Once the registered school is linked, the bundle appears.
    link = bind(c, root, a["id"])
    linked = state()
    assert (linked["state"], linked["institution_id"]) == ("bound", a["id"])
    assert linked["bundle"]["edition"] == bundles()[BUNDLE_ID]["edition"]
    assert home()["state"] == "ready" and home()["buttons"]
    assert c.get(ME + "/assets/" + identifier, headers=owner).status_code == 200
    # Unlinking hides it again; a node ID remembered from before shows the unlinked state.
    c.delete(
        binding_path(a), headers=root, params={"expected_version": link["version"]}
    ).raise_for_status()
    gone = c.get(ME + "/nodes/calendar", headers=owner).json()
    assert (gone["node_id"], gone["reason"]) == ("calendar", "school_guidance_not_connected")


def test_administrators_preview_only_schools_in_scope(auth_client, auth_db):
    c = auth_client
    root = operator(c, auth_db)
    a, b = school(c, root), school(c, root, "다른 합성대")
    bind(c, root, a["id"])
    preview = c.get(ME + "/nodes/home", headers=root, params={"institution_id": a["id"]})
    assert preview.json()["state"] == "ready"
    unlinked = c.get(ME + "/nodes/home", headers=root, params={"institution_id": b["id"]}).json()
    assert unlinked["reason"] == "school_guidance_not_connected"
    account = register(c, "binding-preview@example.test").json()
    scoped = {"Authorization": "Bearer " + account["access_token"]}
    post(
        c,
        root,
        "scopes",
        {"user_id": account["user"]["id"], "institution_id": b["id"], "reason": "합성 범위"},
    )
    denied = c.get(ME + "/nodes/home", headers=scoped, params={"institution_id": a["id"]})
    assert denied.status_code == 403
