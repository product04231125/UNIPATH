"""Gap analysis API with a synthetic posting source and model; no network, no real data."""

from datetime import UTC, datetime

import pytest
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register
from test_personal import post

from app.rag.career import api as career_api
from app.rag.career.contracts import Posting

TEXT = "자격요건: React 실무 경험\n우대: 정보처리기사"


class Source:
    name = "work24"
    collection_method = "crawl"
    supports_occupation = True

    def __init__(self):
        self.queries = []

    def search(self, query):
        self.queries.append(query)
        return [
            Posting(
                "work24",
                f"K00000000000{index}",
                f"합성 프론트엔드 개발자 {index}",
                "합성 회사",
                "서울",
                f"https://www.work24.go.kr/synthetic/{index}",
                TEXT,
                datetime.now(UTC).isoformat(),
                text_scope="full_text",
            )
            for index in (1, 2)
        ]


class Model:
    def __init__(self):
        self.payloads = []

    def generate(self, instruction, payload, **options):
        self.payloads.append(payload)
        record = payload["records"][0]
        return {
            "requirements": [
                {
                    "requirement": "React 실무 경험",
                    "category": "skill",
                    "postings": [
                        {"posting": 1, "quote": "React 실무 경험"},
                        {"posting": 2, "quote": "React 실무 경험"},
                    ],
                    "status": "supported",
                    "personal_evidence": [
                        {
                            "kind": record["kind"],
                            "record_id": record["record_id"],
                            "version": record["version"],
                            "excerpt": "React로 화면",
                        }
                    ],
                    "explanation": "두 공고 모두 React 화면 개발을 요구합니다.",
                    "actions": [],
                }
            ],
            "summary": "React 경험은 강점입니다.",
        }


@pytest.mark.integration
def test_gap_analysis_uses_the_saved_goal_and_all_selected_records(auth_client, monkeypatch):
    c = auth_client
    owner = authorization(register(c))
    record = post(
        c,
        owner,
        "experience-records",
        {"title": "합성 웹 프로젝트", "experience_type": "프로젝트", "result": "React로 화면 구현"},
    )
    selection = {"kind": "experience", "record_id": record["id"], "expected_version": 1}
    path = "/api/v1/me/career-gap-analyses"
    body = {"records": [selection], "external_processing_consent": True}

    assert c.post(path, headers=owner, json={**body, "external_processing_consent": False}).json()[
        "missing_fields"
    ] == ["external_processing_consent"]
    assert c.post(path, headers=owner, json=body).json()["missing_fields"] == ["career_goal"]
    goal = {"category_codes": ["024"], "keyword": "", "expected_version": 0}
    assert c.put("/api/v1/me/career-goal", headers=owner, json=goal).status_code == 200
    assert c.post(path, headers=owner, json={**body, "records": []}).json()["missing_fields"] == [
        "records"
    ]
    c.app.state.gap_model = None
    assert c.post(path, headers=owner, json=body).json()["status"] == "not_configured"

    source, model = Source(), Model()
    monkeypatch.setattr(career_api, "configured_sources", lambda: [source])
    c.app.state.gap_model = model
    response = c.post(path, headers=owner, json=body)
    assert response.status_code == 200
    value = response.json()
    assert value["status"] == "completed"
    assert value["goal"] == {"category_codes": ["024"], "keyword": "", "label": "소프트웨어"}
    assert source.queries[0].occupation_codes == ("024",)
    assert [p["posting"] for p in value["postings"]] == [1, 2]
    assert "text" not in value["postings"][0]
    requirement = value["requirements"][0]
    assert requirement["frequency"] == 2 and requirement["status"] == "supported"
    assert requirement["personal_evidence"][0]["excerpt"] == "React로 화면"
    assert value["summary"] == "React 경험은 강점입니다."
    assert "공고가 2건만" in value["warnings"][0]
    # The model saw the record text (redacted context), never the owner's account data.
    assert model.payloads[0]["records"][0]["record_id"] == record["id"]
