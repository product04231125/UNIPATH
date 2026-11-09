from uuid import UUID, uuid4

import pytest
from pydantic import ValidationError
from sqlalchemy.exc import IntegrityError
from test_academic import operator, school
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register

from app.models.academic_workspace import ClassificationNode
from app.schemas.academic_workspace import ClassificationReplace

ROOT = "/api/v1/admin/academic"


def command(**values):
    return {"client_id": str(uuid4()), **values}


def draft(client, headers, institution):
    response = client.post(
        ROOT + "/classification-revisions",
        headers=headers,
        json=command(institution_id=institution["id"]),
    )
    assert response.status_code == 201, response.text
    return response.json()


def tree(client, headers, revision):
    payload = command(
        expected_version=revision["version"],
        nodes=[
            {"client_ref": "major", "label": "전공", "position": 0, "selectable": False},
            {"client_ref": "core", "parent_ref": "major", "label": "핵심", "position": 0},
        ],
    )
    response = client.put(
        ROOT + "/classification-revisions/" + revision["id"], headers=headers, json=payload
    )
    assert response.status_code == 200, response.text
    return response.json(), payload


@pytest.mark.parametrize(
    "nodes",
    [
        [{"client_ref": "a", "parent_ref": "a", "label": "순환", "position": 0}],
        [{"client_ref": "a", "parent_ref": "missing", "label": "끊김", "position": 0}],
        [
            {"client_ref": "a", "label": "중복 위치", "position": 0},
            {"client_ref": "b", "label": "중복 위치", "position": 0},
        ],
        [{"client_ref": "a", "id": str(uuid4()), "label": "중복 신원", "position": 0}],
    ],
)
def test_classification_rejects_ambiguous_or_cyclic_tree(nodes):
    with pytest.raises(ValidationError):
        ClassificationReplace.model_validate(command(expected_version=1, nodes=nodes))


@pytest.mark.integration
def test_classification_save_replay_publish_copy_preserves_identity(auth_client, auth_db):
    c = auth_client
    h = operator(c, auth_db)
    inst = school(c, h)
    initial = draft(c, h, inst)
    saved, payload = tree(c, h, initial)
    url = ROOT + "/classification-revisions/" + initial["id"]
    assert c.put(url, headers=h, json=payload).json() == saved
    assert c.get(url, headers=h).json()["nodes"] == saved["nodes"]
    assert c.put(url, headers=h, json={**payload, "client_id": str(uuid4())}).status_code == 409
    assert c.put(url, headers=h, json=command(**{**payload, "nodes": []})).status_code == 409
    preview = c.post(
        url + "/preview-publication", headers=h, json={"expected_version": saved["version"]}
    )
    assert preview.status_code == 200 and preview.json()["issues"] == []
    publish = command(
        expected_version=saved["version"],
        expected_digest=preview.json()["digest"],
        review_note="합성 분류 검토",
    )
    published = c.post(url + "/publish", headers=h, json=publish)
    assert published.status_code == 200, published.text
    assert published.json()["status"] == "published"
    assert c.post(url + "/publish", headers=h, json=publish).json() == published.json()
    assert (
        c.put(
            url, headers=h, json=command(expected_version=published.json()["version"], nodes=[])
        ).status_code
        == 409
    )
    copied = c.post(
        ROOT + "/classification-revisions",
        headers=h,
        json=command(institution_id=inst["id"], copy_from_id=initial["id"]),
    )
    assert copied.status_code == 201, copied.text
    old_nodes = {n["logical_id"]: n for n in published.json()["nodes"]}
    new_nodes = {n["logical_id"]: n for n in copied.json()["nodes"]}
    assert old_nodes.keys() == new_nodes.keys()
    assert all(old_nodes[key]["id"] != new_nodes[key]["id"] for key in old_nodes)
    assert c.get(url, headers=h).json()["nodes"] == published.json()["nodes"]


@pytest.mark.integration
def test_classification_invalid_reference_is_atomic_and_school_fk_is_enforced(auth_client, auth_db):
    c = auth_client
    h = operator(c, auth_db)
    first, other = school(c, h), school(c, h, "다른 합성대")
    revision = draft(c, h, first)
    saved, _ = tree(c, h, revision)
    url = ROOT + "/classification-revisions/" + revision["id"]
    bad = c.put(
        url,
        headers=h,
        json=command(
            expected_version=saved["version"],
            nodes=[{"id": str(uuid4()), "label": "다른 항목", "position": 0}],
        ),
    )
    assert bad.status_code == 422, bad.text
    assert bad.json()["error"]["field_errors"][0]["field"].endswith("nodes.0.id")
    assert c.get(url, headers=h).json()["nodes"] == saved["nodes"]
    with auth_db() as db:
        db.add(
            ClassificationNode(
                institution_id=UUID(other["id"]),
                revision_id=UUID(revision["id"]),
                label="금지된 학교 연결",
                position=0,
                selectable=True,
            )
        )
        with pytest.raises(IntegrityError):
            db.commit()
        db.rollback()


@pytest.mark.integration
def test_students_cannot_read_or_write_admin_classifications(auth_client, auth_db):
    c = auth_client
    h = operator(c, auth_db)
    inst = school(c, h)
    revision = draft(c, h, inst)
    student = authorization(register(c))
    assert (
        c.get(
            ROOT + "/classification-revisions",
            headers=student,
            params={"institution_id": inst["id"]},
        ).status_code
        == 403
    )
    assert (
        c.get(ROOT + "/classification-revisions/" + revision["id"], headers=student).status_code
        == 403
    )
    assert (
        c.post(
            ROOT + "/study-tracks",
            headers=student,
            json=command(institution_id=inst["id"], name="허용 안 됨"),
        ).status_code
        == 403
    )


@pytest.mark.integration
def test_track_mutations_are_replay_safe_and_versioned(auth_client, auth_db):
    c = auth_client
    h = operator(c, auth_db)
    inst = school(c, h)
    payload = command(institution_id=inst["id"], name="학교별 경로")
    response = c.post(ROOT + "/study-tracks", headers=h, json=payload)
    assert response.status_code == 201, response.text
    track = response.json()
    assert c.post(ROOT + "/study-tracks", headers=h, json=payload).json() == track
    assert (
        c.post(
            ROOT + "/study-tracks", headers=h, json={**payload, "name": "키 재사용 금지"}
        ).status_code
        == 409
    )
    change = command(expected_version=track["version"], name="수정 경로", inactive=True)
    url = ROOT + "/study-tracks/" + track["id"]
    changed = c.patch(url, headers=h, json=change)
    assert changed.status_code == 200 and changed.json()["inactive_at"] is not None
    assert c.patch(url, headers=h, json=change).json() == changed.json()
    assert c.patch(url, headers=h, json={**change, "client_id": str(uuid4())}).status_code == 409
    listed = c.get(ROOT + "/study-tracks", headers=h, params={"institution_id": inst["id"]})
    assert listed.json()["items"] == [changed.json()]


def test_workspace_openapi_is_admin_only_and_authenticated(client):
    schema = client.get("/api/v1/openapi.json").json()
    paths = {path: value for path, value in schema["paths"].items() if path.startswith(ROOT)}
    assert paths
    for path, methods in paths.items():
        assert "/me/" not in path and "/catalog/" not in path
        for operation in methods.values():
            assert operation["security"]
