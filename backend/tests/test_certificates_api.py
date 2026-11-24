"""Certificate catalog, Q-Net parsing, schedules and recommendations; synthetic data, no network."""

from datetime import date

import pytest
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register
from test_personal import post

from app.rag.career import certificates, qnet
from app.rag.career.contracts import AnalysisRejected, ProviderFailure

TECHNICAL = b"""<?xml version="1.0" encoding="UTF-8"?><response><header>
<resultCode>00</resultCode><resultMsg>NORMAL SERVICE.</resultMsg></header><body><items><item>
<implplannm>
2026\xeb\x85\x84 \xec\xa0\x95\xea\xb8\xb0 \xea\xb8\xb0\xec\x82\xac 3\xed\x9a\x8c
</implplannm>
<docregstartdt>20260720</docregstartdt><docregenddt>20260723</docregenddt>
<docexamstartdt>20260807</docexamstartdt><docexamenddt>20260901</docexamenddt>
<docpassdt>20260909</docpassdt><pracregstartdt>20260921</pracregstartdt>
<pracregenddt>20260928</pracregenddt><pracexamstartdt>20261024</pracexamstartdt>
<pracexamenddt>20261115</pracexamenddt><pracpassstartdt>20261218</pracpassstartdt>
<pracpassenddt>20270217</pracpassenddt></item></items></body></response>"""


class FakeQNet:
    def __init__(self, rounds=None, fail=False):
        self.rounds = rounds
        self.fail = fail
        self.calls = []

    def technical_schedule(self, jmcd):
        self.calls.append(("technical", jmcd))
        if self.fail:
            raise ProviderFailure("down", "network")
        return self.rounds

    def professional_schedule(self, series):
        self.calls.append(("professional", series))
        return self.rounds

    def fee(self, jmcd):
        return "1차 : 19400, 2차 : 22600"

    def info(self, jmcd):
        return {"취득방법": "시험과목\n- 필기 1. 소프트웨어설계", "출제경향": "SQL 응용"}


def round_(name, registration, exam):
    return {
        "name": name,
        "events": [
            {
                "kind": "registration",
                "label": "필기 접수",
                "start": registration,
                "end": registration,
            },
            {"kind": "exam", "label": "필기 시험", "start": exam, "end": exam},
        ],
    }


@pytest.fixture
def private(monkeypatch):
    data = {
        "checked_at": "2026-11-24",
        "items": [
            {
                "id": "sqld",
                "name": "SQL 개발자(SQLD)",
                "aliases": ["SQLD"],
                "issuer": "합성 진흥원",
                "kind": "national_certified_private",
                "official_url": "https://example.test/sqld",
                "mode": "scheduled",
                "rounds": [
                    {
                        "name": "제1회",
                        "registration_start": "2027-01-05",
                        "registration_end": "2027-01-09",
                        "exams": [{"label": "시험", "date": "2027-02-07"}],
                        "result_date": "2027-03-01",
                    }
                ],
                "subjects": ["데이터 모델링의 이해", "SQL 기본 및 활용"],
            },
            {
                "id": "opic",
                "name": "OPIc",
                "issuer": "합성 평가원",
                "kind": "language",
                "mode": "always",
            },
        ],
    }
    monkeypatch.setattr(certificates, "_private", data)
    return data


def test_qnet_technical_rounds_and_errors():
    items = qnet.parse_items(TECHNICAL)
    first = qnet.technical_round(items[0])
    assert first["name"] == "2026년 정기 기사 3회"
    labels = [(e["label"], e["start"], e["end"]) for e in first["events"]]
    assert labels[0] == ("필기 접수", "2026-07-20", "2026-07-23")
    assert labels[-1] == ("최종 합격 발표", "2026-12-18", "2027-02-17")
    with pytest.raises(ProviderFailure):
        qnet.parse_items(b"<response><header><resultCode>30</resultCode></header></response>")
    with pytest.raises(ProviderFailure):
        qnet.parse_items(b"not xml")


def test_qnet_professional_stages_group_by_round():
    rows = [
        {
            "description": "2027년도 25회 필기",
            "examregstartdt": "20261207",
            "examregenddt": "20261211",
            "examstartdt": "20270116",
            "passstartdt": "20270324",
        },
        {"description": "2027년도 25회 면접", "examstartdt": "20270410"},
    ]
    rounds = qnet.professional_rounds(rows)
    assert [r["name"] for r in rounds] == ["2027년도 25회"]
    assert [e["label"] for e in rounds[0]["events"]] == [
        "필기 접수",
        "필기 시험",
        "필기 합격 발표",
        "면접 시험",
    ]


def test_schedule_status_uses_the_next_registration(private):
    item = certificates.find("qnet-1320")
    today = date(2026, 11, 24)
    # Only a result announcement ahead: next year's registration is not published yet.
    rounds = qnet.technical_round(qnet.parse_items(TECHNICAL)[0])
    view = certificates.schedule(item, today, FakeQNet([rounds]))
    assert view["status"] == "unpublished" and view["next_registration"] is None
    assert view["reference_rounds"][0]["name"] == "2026년 정기 기사 3회"
    assert view["next_event"]["label"] == "최종 합격 발표"
    upcoming = [
        round_("1회", "2026-12-07", "2027-01-16"),
        round_("0회", "2026-01-05", "2026-02-01"),
    ]
    view = certificates.schedule(item, today, FakeQNet(upcoming))
    assert view["status"] == "upcoming"
    assert view["next_registration"]["start"] == "2026-12-07"
    assert [r["name"] for r in view["rounds"]] == ["1회"]
    view = certificates.schedule(item, today, FakeQNet(fail=True))
    assert view["status"] == "unavailable" and view["failure_reason"] == "network"
    # Checked-in schedules of other certificates; 상시 시험 has no rounds.
    sqld = certificates.schedule(certificates.find("private-sqld"), today)
    assert sqld["status"] == "upcoming" and sqld["checked_at"] == "2026-11-24"
    assert [e["label"] for e in sqld["rounds"][0]["events"]] == ["접수", "시험", "결과 발표"]
    assert certificates.schedule(certificates.find("private-opic"), today)["status"] == "always"


def test_search_resolve_and_detail(private):
    names = [i["name"] for i in certificates.search("정보처리")]
    assert names[0] == "정보처리기사" and all(n.startswith("정보처리") for n in names)
    assert certificates.search("sqld")[0]["id"] == "private-sqld"
    assert certificates.resolve("SQLD")["id"] == "private-sqld"
    assert certificates.resolve("정보처리") is None
    detail = certificates.detail(certificates.find("qnet-1320"), date(2026, 11, 24), FakeQNet([]))
    assert detail["fee"].startswith("1차")
    assert detail["method"].startswith("시험과목")
    assert detail["eligibility_note"]
    assert detail["official_url"].endswith("jmCd=1320")
    sqld = certificates.detail(certificates.find("private-sqld"), date(2026, 11, 24))
    assert sqld["subjects"] == ["데이터 모델링의 이해", "SQL 기본 및 활용"]


class Model:
    def __init__(self, output=None):
        self.payloads = []
        self.output = output

    def generate(self, instruction, payload, **options):
        self.payloads.append(payload)
        return self.output or {
            "recommendations": [
                {
                    "name": "SQLD",
                    "reason": "공고에서 SQL 역량을 자주 요구합니다.",
                    "requirements": ["SQL 활용 능력", "지어낸 요건"],
                    "related_records": ["합성 데이터베이스", "없는 기록"],
                    "timing": "겨울방학",
                    "weeks": 6,
                },
                {"name": "없는 자격증", "reason": "버림"},
                {"name": "정보처리기사", "reason": "보유 자격이라 빠져야 합니다."},
                {
                    "name": "웹디자인개발기능사",
                    "reason": "화면 구현 역량을 보여 줍니다.",
                    "weeks": 99,
                },
            ],
            "summary": "데이터 역량을 보완합니다.",
        }


def test_recommendations_keep_catalog_names_and_drop_held(private):
    records = [
        {"kind": "credential", "title": "정보처리기사", "text": "정보처리기사 취득"},
        {"kind": "course", "title": "합성 데이터베이스", "text": "SQL 실습"},
    ]
    gaps = [{"requirement": "SQL 활용 능력", "status": "insufficient_evidence", "frequency": 3}]
    model = Model()
    values, summary, held = certificates.recommend_certificates(
        model, {"label": "소프트웨어", "keyword": ""}, gaps, records
    )
    assert held == ["정보처리기사"]
    assert "정보처리기사" not in model.payloads[0]["catalog"]
    assert [v["certificate"]["id"] for v in values] == ["private-sqld", "qnet-7798"]
    assert values[0]["requirements"] == ["SQL 활용 능력"]
    assert values[0]["related_records"] == ["합성 데이터베이스"]
    assert values[1]["weeks"] is None and "aliases" not in values[0]["certificate"]
    assert summary == "데이터 역량을 보완합니다."
    with pytest.raises(AnalysisRejected):
        certificates.recommend_certificates(
            Model({"recommendations": [{"name": "없는 자격증", "reason": "x"}]}),
            {"label": "소프트웨어"},
            gaps,
            records,
        )


@pytest.mark.integration
def test_certificate_api(auth_client, monkeypatch, private):
    c = auth_client
    owner = authorization(register(c))
    monkeypatch.setattr(certificates.qnet, "QNet", lambda: FakeQNet([]))
    found = c.get("/api/v1/me/certificates", headers=owner, params={"query": "정보처리기사"})
    assert found.status_code == 200 and found.json()["items"][0]["id"] == "qnet-1320"
    assert c.get("/api/v1/me/certificates", params={"query": "x"}).status_code == 401
    detail = c.get("/api/v1/me/certificates/qnet-1320", headers=owner).json()
    assert detail["name"] == "정보처리기사" and detail["schedule"]["status"] == "unpublished"
    assert c.get("/api/v1/me/certificates/qnet-0000", headers=owner).status_code == 404
    assert c.get("/api/v1/me/certificates/bad id", headers=owner).status_code == 422

    record = post(
        c,
        owner,
        "experience-records",
        {"title": "합성 데이터베이스", "experience_type": "프로젝트", "result": "SQL 실습"},
    )
    selection = {"kind": "experience", "record_id": record["id"], "expected_version": 1}
    path = "/api/v1/me/certificate-recommendations"
    body = {"records": [selection], "external_processing_consent": True}
    assert c.post(path, headers=owner, json=body).json()["missing_fields"] == ["career_goal"]
    goal = {"category_codes": ["024"], "keyword": "", "expected_version": 0}
    assert c.put("/api/v1/me/career-goal", headers=owner, json=goal).status_code == 200
    saved = {
        "kind": "gap",
        "title": "소프트웨어",
        "result": {
            "postings": [{"posting": 1}, {"posting": 2}, {"posting": 3}],
            "requirements": [
                {"requirement": "SQL 활용 능력", "status": "insufficient_evidence", "frequency": 3}
            ],
        },
    }
    assert c.post("/api/v1/me/analysis-results", headers=owner, json=saved).status_code == 201
    model = Model()
    c.app.state.gap_model = model
    value = c.post(path, headers=owner, json={**body, "academic_stage": "year3"}).json()
    assert value["status"] == "completed", value
    assert value["gap_basis"] == {
        "analyzed_at": value["gap_basis"]["analyzed_at"],
        "gaps": 1,
        "postings": 3,
    }
    first = value["recommendations"][0]
    assert first["certificate"]["id"] == "private-sqld"
    assert first["evidence"] == [{"requirement": "SQL 활용 능력", "frequency": 3}]
    assert first["schedule"]["status"] == "upcoming"
    assert model.payloads[0]["academic_stage"] == "year3"
