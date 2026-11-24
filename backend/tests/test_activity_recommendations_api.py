"""Activity recommendations with a synthetic model; no network, no real data."""

import pytest
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register
from test_personal import post

from app.rag.career import activities
from app.rag.career import api as career_api
from app.rag.career.contracts import AnalysisRejected


class Model:
    def __init__(self, output=None):
        self.payloads = []
        self.output = output

    def generate(self, instruction, payload, **options):
        self.payloads.append(payload)
        return self.output or {
            "recommendations": [
                {
                    "kind": "hackathon",
                    "title": "웹 서비스 해커톤 참가",
                    "reason": "배포 경험이 부족해 짧은 기간에 서비스를 완성해 봅니다.",
                    "requirements": ["Docker 배포 경험", "지어낸 요건"],
                    "keywords": ["웹 해커톤", "웹 해커톤", "프론트엔드 공모전"],
                    "sites": ["devpost", "1365", "없는곳"],
                    "deliverable": "배포한 서비스 주소와 맡은 역할",
                    "weeks": 2,
                },
                {"kind": "unknown", "title": "버림", "reason": "버림", "deliverable": "x"},
                {
                    "kind": "volunteer",
                    "title": "IT 교육 봉사",
                    "reason": "협업과 설명 능력을 보여 줍니다.",
                    "requirements": [],
                    "keywords": [],
                    "sites": [],
                    "weeks": 99,
                },
            ],
            "summary": "배포와 협업 경험을 채우는 활동입니다.",
        }


def test_model_output_is_checked_against_gaps_kinds_and_sites():
    gaps = [{"requirement": "Docker 배포 경험", "status": "insufficient_evidence"}]
    goal = {"label": "소프트웨어", "keyword": "프론트엔드"}
    values, summary = activities.recommend_activities(Model(), goal, gaps, [])
    assert [v["kind"] for v in values] == ["hackathon", "volunteer"]
    first, second = values
    # Only the given gap survives; sites must exist and fit the kind.
    assert first["requirements"] == ["Docker 배포 경험"]
    assert first["sites"] == ["devpost"]
    assert first["keywords"] == ["웹 해커톤", "프론트엔드 공모전"]
    assert first["kind_label"] == "해커톤"
    # No usable site: the catalog default for the kind; out-of-range weeks are dropped.
    assert second["sites"] == ["1365", "vms"]
    assert second["weeks"] is None and second["deliverable"] is None
    assert summary == "배포와 협업 경험을 채우는 활동입니다."
    with pytest.raises(AnalysisRejected):
        activities.recommend_activities(Model({"recommendations": []}), goal, gaps, [])
    table = activities.site_table(values)
    assert table == {
        "devpost": {"name": "Devpost", "url": "https://devpost.com"},
        "1365": {"name": "1365 자원봉사포털", "url": "https://www.1365.go.kr"},
        "vms": {"name": "VMS 사회복지자원봉사", "url": "https://www.vms.or.kr"},
    }


def test_gaps_come_from_unmet_requirements():
    report = {
        "requirements": [
            {"requirement": "React", "status": "supported"},
            {"requirement": "Docker  배포", "status": "partially_supported", "frequency": 3},
            {"requirement": "", "status": "insufficient_evidence"},
        ]
    }
    assert activities.gaps_from(report) == [
        {
            "requirement": "Docker 배포",
            "status": "partially_supported",
            "category": "other",
            "frequency": 3,
        }
    ]
    assert activities.gaps_from(None) == []


@pytest.mark.integration
def test_activity_recommendations_use_goal_gaps_and_records(auth_client, monkeypatch):
    c = auth_client
    owner = authorization(register(c))
    record = post(
        c,
        owner,
        "experience-records",
        {"title": "합성 웹 프로젝트", "experience_type": "프로젝트", "result": "React로 화면 구현"},
    )
    selection = {"kind": "experience", "record_id": record["id"], "expected_version": 1}
    path = "/api/v1/me/activity-recommendations"
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

    # The latest saved 목표 직무 분석 gives the gaps.
    saved = {
        "kind": "gap",
        "title": "소프트웨어",
        "result": {
            "requirements": [
                {"requirement": "React", "status": "supported"},
                {"requirement": "Docker 배포 경험", "status": "insufficient_evidence"},
            ]
        },
    }
    assert c.post("/api/v1/me/analysis-results", headers=owner, json=saved).status_code == 201
    model = Model()

    def no_collection():
        raise AssertionError("activity recommendations must not collect postings")

    monkeypatch.setattr(career_api, "configured_sources", no_collection)
    c.app.state.gap_model = model
    response = c.post(path, headers=owner, json={**body, "academic_stage": "graduating"})
    assert response.status_code == 200, response.text
    value = response.json()
    assert value["status"] == "completed"
    assert value["gap_basis"]["gaps"] == 1
    assert model.payloads[0]["gaps"][0]["requirement"] == "Docker 배포 경험"
    assert model.payloads[0]["records"][0]["record_id"] == record["id"]
    assert model.payloads[0]["academic_stage"] == "graduating"
    assert "internships" not in value and "region_label" not in value
    assert value["recommendations"][0]["requirements"] == ["Docker 배포 경험"]
    assert value["sites"]["devpost"]["name"] == "Devpost"
    # Regions are no longer an input (internships are found by 공고 찾기).
    assert c.post(path, headers=owner, json={**body, "regions": ["서울"]}).status_code == 422
