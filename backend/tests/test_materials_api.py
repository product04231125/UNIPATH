"""내 자료 and saved analysis results in the account; synthetic data only."""

import base64
from uuid import uuid4

import pytest
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register

PDF = b"%PDF-1.4\n% synthetic\n"


def material(title="합성 포트폴리오", *, pdf=PDF, description=""):
    body = {
        "id": str(uuid4()),
        "title": title,
        "material_type": "portfolio",
        "description": description,
    }
    if pdf is not None:
        body["file"] = {
            "filename": "portfolio.pdf",
            "content_base64": base64.b64encode(pdf).decode(),
        }
    return body


@pytest.mark.integration
def test_materials_are_owner_only_versioned_and_keep_their_pdf(auth_client):
    c = auth_client
    owner = authorization(register(c))
    other = authorization(register(c, "other@example.test"))
    path = "/api/v1/me/materials"
    assert c.get(path).status_code == 401
    assert c.get(path, headers=owner).json()["items"] == []

    body = material()
    created = c.post(path, headers=owner, json=body)
    assert created.status_code == 201, created.text
    value = created.json()
    assert value["id"] == body["id"] and value["version"] == 1
    assert value["filename"] == "portfolio.pdf" and value["byte_count"] == len(PDF)
    # Sending the same material again (a retried move from a device) changes nothing.
    again = c.post(path, headers=owner, json=body)
    assert again.status_code == 200 and again.json()["version"] == 1
    assert c.post(path, headers=other, json=body).status_code == 409

    item = f"{path}/{value['id']}"
    listed = c.get(path, headers=owner).json()
    assert listed["total_bytes"] == len(PDF) and "content_base64" not in str(listed)
    file = c.get(f"{item}/file", headers=owner)
    assert file.status_code == 200 and file.content == PDF
    assert file.headers["content-type"] == "application/pdf"

    # Another student can neither list, read, change nor delete it.
    assert c.get(path, headers=other).json()["items"] == []
    assert c.get(f"{item}/file", headers=other).status_code == 404
    update = {"title": "바뀐 이름", "material_type": "resume", "expected_version": 1}
    assert c.put(item, headers=other, json=update).status_code == 404
    assert c.delete(item + "?expected_version=1", headers=other).status_code == 404

    # Leaving the file out keeps the PDF; null removes it, which needs a description.
    changed = c.put(item, headers=owner, json=update)
    assert changed.status_code == 200, changed.text
    assert changed.json()["version"] == 2 and changed.json()["byte_count"] == len(PDF)
    assert c.put(item, headers=owner, json=update).status_code == 409
    removed = {**update, "expected_version": 2, "file": None}
    assert c.put(item, headers=owner, json=removed).status_code == 422
    removed["description"] = "React 쇼핑몰 과제 설명"
    without = c.put(item, headers=owner, json=removed)
    assert without.status_code == 200 and without.json()["filename"] is None
    assert c.get(f"{item}/file", headers=owner).status_code == 404

    assert c.delete(item + "?expected_version=1", headers=owner).status_code == 409
    assert c.delete(item + "?expected_version=3", headers=owner).status_code == 204
    assert c.get(path, headers=owner).json()["items"] == []


@pytest.mark.integration
def test_material_content_is_checked(auth_client):
    c = auth_client
    owner = authorization(register(c))
    path = "/api/v1/me/materials"
    assert c.post(path, headers=owner, json=material(pdf=None)).status_code == 422
    assert c.post(path, headers=owner, json=material(pdf=b"not a pdf")).status_code == 422
    text_only = c.post(path, headers=owner, json=material(pdf=None, description="활동 설명"))
    assert text_only.status_code == 201 and text_only.json()["byte_count"] == 0
    wrong_name = material()
    wrong_name["file"]["filename"] = "portfolio.txt"
    assert c.post(path, headers=owner, json=wrong_name).status_code == 422


def result(kind="posting", title="합성 IT 프론트엔드"):
    return {
        "kind": kind,
        "title": title,
        "summary": {"ready": 6, "total": 7},
        "input": {"posting_text": "자격 요건\n- React 개발 경험"},
        "result": {"status": "completed", "comparisons": [{"requirement": "React"}]},
    }


@pytest.mark.integration
def test_analysis_results_keep_the_newest_and_every_favorite(auth_client, monkeypatch):
    from app.api import analysis_results

    monkeypatch.setattr(analysis_results, "KEEP_RECENT", 2)
    c = auth_client
    owner = authorization(register(c))
    other = authorization(register(c, "other@example.test"))
    path = "/api/v1/me/analysis-results"
    assert c.get(path).status_code == 401

    first = c.post(path, headers=owner, json=result(title="첫 공고"))
    assert first.status_code == 201, first.text
    first_id = first.json()["id"]
    assert first.json()["summary"] == {"ready": 6, "total": 7}
    item = f"{path}/{first_id}"
    assert c.get(item, headers=other).status_code == 404
    assert c.patch(item, headers=other, json={"favorite": True}).status_code == 404
    starred = c.patch(item, headers=owner, json={"favorite": True})
    assert starred.status_code == 200 and starred.json()["favorite"] is True

    for title in ("둘째 공고", "셋째 공고", "넷째 공고"):
        assert c.post(path, headers=owner, json=result(title=title)).status_code == 201
    assert c.post(path, headers=owner, json=result("gap", "프론트엔드")).status_code == 201

    titles = [i["title"] for i in c.get(path + "?kind=posting", headers=owner).json()["items"]]
    # The star keeps the oldest; only the two newest unstarred ones stay.
    assert titles == ["첫 공고", "넷째 공고", "셋째 공고"]
    assert len(c.get(path, headers=owner).json()["items"]) == 4
    assert c.get(path, headers=other).json()["items"] == []

    full = c.get(item, headers=owner).json()
    assert full["result"]["comparisons"][0]["requirement"] == "React"
    assert full["input"]["posting_text"].startswith("자격 요건")
    assert c.delete(item, headers=other).status_code == 404
    assert c.delete(item, headers=owner).status_code == 204
    assert c.get(item, headers=owner).status_code == 404

    large = result()
    large["result"]["comparisons"] = [{"requirement": "가" * 1000}] * 250
    assert c.post(path, headers=owner, json=large).status_code == 422
    assert c.post(path, headers=owner, json={**result(), "kind": "other"}).status_code == 422
