"""Writing draft and Word export APIs with a synthetic model; no network, no real data."""

from io import BytesIO

import docx
import pytest
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register
from test_personal import post


class Model:
    def __init__(self):
        self.payloads = []

    def generate(self, instruction, payload, **options):
        self.payloads.append(payload)
        record = payload["records"][0]
        cite = {
            "kind": record["kind"],
            "record_id": record["record_id"],
            "version": record["version"],
        }
        return {
            "sections": [
                {
                    "heading": "지원 직무와 관련된 경험",
                    "paragraphs": [
                        {
                            "text": "합성 웹 프로젝트에서 React로 화면을 구현했습니다.",
                            "citations": [{**cite, "excerpt": "React로 화면 구현"}],
                        },
                        {
                            "text": "사용자 수를 두 배로 늘렸습니다.",
                            "citations": [{**cite, "excerpt": "사용자 두 배"}],
                        },
                    ],
                }
            ],
            "questions_for_user": ["지원 동기를 알려 주세요."],
            "revisions": [],
        }


@pytest.mark.integration
def test_writing_draft_uses_owned_records_and_drops_unverified_paragraphs(auth_client):
    c = auth_client
    owner = authorization(register(c))
    record = post(
        c,
        owner,
        "experience-records",
        {"title": "합성 웹 프로젝트", "experience_type": "프로젝트", "result": "React로 화면 구현"},
    )
    selection = {"kind": "experience", "record_id": record["id"], "expected_version": 1}
    path = "/api/v1/me/writing-drafts"
    body = {
        "document_type": "cover_letter",
        "target_role": "프론트엔드 개발",
        "target_company": "합성 회사",
        "posting_text": "담당업무: React 화면 개발",
        "questions": ["지원 직무와 관련된 경험을 적어 주세요."],
        "char_limit": 800,
        "records": [selection],
        "external_processing_consent": True,
    }

    refused = c.post(path, headers=owner, json={**body, "external_processing_consent": False})
    assert refused.json()["missing_fields"] == ["external_processing_consent"]
    empty = c.post(path, headers=owner, json={**body, "records": []})
    assert empty.json()["missing_fields"] == ["records"]
    c.app.state.writing_model = None
    assert c.post(path, headers=owner, json=body).json()["status"] == "not_configured"

    model = Model()
    c.app.state.writing_model = model
    response = c.post(path, headers=owner, json=body)
    assert response.status_code == 200
    value = response.json()
    assert value["status"] == "draft_ready" and value["document_type"] == "cover_letter"
    paragraphs = value["draft"]["sections"][0]["paragraphs"]
    assert [p["text"] for p in paragraphs] == ["합성 웹 프로젝트에서 React로 화면을 구현했습니다."]
    assert paragraphs[0]["citations"][0]["record_id"] == record["id"]
    assert "1개는 초안에서 뺐습니다" in value["warnings"][-1]
    assert value["document_sources"] == [] and value["generated_at"]
    payload = model.payloads[0]
    assert payload["records"][0]["record_id"] == record["id"]
    assert payload["posting_text"] == "담당업무: React 화면 개발"
    # Another student's record is never assembled into the request.
    other = authorization(register(c, "other@example.test"))
    assert c.post(path, headers=other, json=body).status_code in (403, 404)


@pytest.mark.integration
def test_writing_export_returns_an_editable_word_file(auth_client):
    c = auth_client
    owner = authorization(register(c))
    body = {
        "document_type": "portfolio",
        "draft": {
            "sections": [
                {
                    "heading": "합성 프로젝트",
                    "facts": [{"label": "역할", "text": "화면 구현", "citations": []}],
                    "paragraphs": [{"text": "직접 고친 문단입니다."}],
                }
            ]
        },
        "profile": {"name": "가상 지원자", "email": "synthetic@example.test"},
        "reviewed": True,
    }
    path = "/api/v1/me/writing-exports"
    assert c.post(path, json=body).status_code == 401
    assert c.post(path, headers=owner, json={**body, "reviewed": False}).status_code == 422
    response = c.post(path, headers=owner, json=body)
    assert response.status_code == 200
    assert response.headers["content-type"].startswith(
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    )
    assert response.headers["cache-control"] == "no-store"
    assert 'filename="portfolio.docx"' in response.headers["content-disposition"]
    texts = [p.text for p in docx.Document(BytesIO(response.content)).paragraphs]
    assert "가상 지원자 포트폴리오" in texts and "직접 고친 문단입니다." in texts


def saved_body(title="합성 회사 자기소개서"):
    return {
        "title": title,
        "input": {
            "document_type": "cover_letter",
            "mode": "create",
            "target_role": "프론트엔드 개발",
            "target_company": "합성 회사",
            "posting_text": "담당업무: React 화면 개발",
            "questions": ["지원 직무와 관련된 경험을 적어 주세요."],
            "char_limit": 800,
            "original_text": "",
        },
        "draft": {
            "sections": [
                {
                    "heading": "지원 직무와 관련된 경험을 적어 주세요.",
                    "paragraphs": [
                        {
                            "text": "직접 고친 문단입니다.",
                            "citations": [
                                {
                                    "kind": "experience",
                                    "record_id": "00000000-0000-4000-8000-000000000101",
                                    "version": 1,
                                    "excerpt": "React로 화면 구현",
                                }
                            ],
                        },
                        {"text": "새로 쓴 문단입니다."},
                    ],
                    "facts": [],
                }
            ],
            "questions_for_user": ["지원 동기를 알려 주세요."],
            "revisions": [],
        },
        "labels": {"00000000-0000-4000-8000-000000000101": "경험 · 합성 웹 프로젝트"},
    }


@pytest.mark.integration
def test_saved_writing_documents_are_owner_only_and_versioned(auth_client):
    c = auth_client
    owner = authorization(register(c))
    other = authorization(register(c, "other@example.test"))
    path = "/api/v1/me/writing-documents"
    assert c.get(path).status_code == 401
    assert c.get(path, headers=owner).json() == {"items": []}

    created = c.post(path, headers=owner, json=saved_body())
    assert created.status_code == 201, created.text
    value = created.json()
    assert value["version"] == 1 and value["document_type"] == "cover_letter"
    assert value["input"]["posting_text"] == "담당업무: React 화면 개발"
    assert "external_processing_consent" not in value["input"]
    paragraphs = value["draft"]["sections"][0]["paragraphs"]
    assert paragraphs[0]["citations"][0]["excerpt"] == "React로 화면 구현"
    assert paragraphs[1]["citations"] == []
    item = f"{path}/{value['id']}"

    # Another student can neither list, read, change nor delete it.
    assert c.get(path, headers=other).json() == {"items": []}
    assert c.get(item, headers=other).status_code == 404
    update = {**saved_body("바뀐 제목"), "expected_version": 1}
    assert c.put(item, headers=other, json=update).status_code == 404
    assert c.delete(item + "?expected_version=1", headers=other).status_code == 404

    changed = c.put(item, headers=owner, json=update)
    assert changed.status_code == 200 and changed.json()["version"] == 2
    assert changed.json()["title"] == "바뀐 제목"
    assert c.put(item, headers=owner, json=update).status_code == 409
    listed = c.get(path, headers=owner).json()["items"]
    assert [(i["title"], i["version"]) for i in listed] == [("바뀐 제목", 2)]
    assert "draft" not in listed[0]

    empty = saved_body()
    empty["draft"]["sections"][0]["paragraphs"] = []
    assert c.post(path, headers=owner, json=empty).status_code == 422
    assert c.delete(item + "?expected_version=1", headers=owner).status_code == 409
    assert c.delete(item + "?expected_version=2", headers=owner).status_code == 204
    assert c.get(item, headers=owner).status_code == 404


@pytest.mark.integration
def test_writing_export_returns_an_a4_pdf(auth_client):
    pdfplumber = pytest.importorskip("pdfplumber")
    c = auth_client
    owner = authorization(register(c))
    response = c.post(
        "/api/v1/me/writing-exports",
        headers=owner,
        json={
            "document_type": "cover_letter",
            "format": "pdf",
            "draft": {"sections": [{"heading": "경험", "paragraphs": [{"text": "고친 문단"}]}]},
            "profile": {"name": "가상 지원자"},
            "reviewed": True,
        },
    )
    assert response.status_code == 200, response.text
    assert response.headers["content-type"] == "application/pdf"
    assert 'filename="cover-letter.pdf"' in response.headers["content-disposition"]
    with pdfplumber.open(BytesIO(response.content)) as pdf:
        assert round(pdf.pages[0].width) == 595
        assert "고친 문단" in pdf.pages[0].extract_text()
