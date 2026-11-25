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

    def technical_schedule(self, jmcd, second="실기"):
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
        if self.fail:
            raise ProviderFailure("down", "network")
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
                "id": "network",
                "name": "합성 네트워크관리사",
                "issuer": "합성 협회",
                "kind": "national_certified_private",
                "mode": "scheduled",
                "schedule_status": "source_unreadable",
                "rounds": [],
                "reference_rounds": [
                    {
                        "name": "지난 회차",
                        "registration_start": "2026-03-02",
                        "registration_end": "2026-03-06",
                        "exams": [
                            {"label": "시험", "date": "2026-04-05", "date_end": "2026-04-06"}
                        ],
                    }
                ],
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
    # Tests that need the ministry plan set their own.
    monkeypatch.setattr(certificates, "_plan", {})
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
    # The running round (final results ahead) is not a past round.
    assert view["rounds"][0]["name"] == "2026년 정기 기사 3회" and view["reference_rounds"] == []
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
    network = certificates.schedule(certificates.find("private-network"), today)
    assert network["status"] == "unconfirmed"
    assert network["reference_rounds"][0]["events"][1]["end"] == "2026-04-06"


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


def test_a_credential_still_in_preparation_is_not_held():
    today = date(2026, 11, 25)

    def credential(title, *lines):
        return {
            "kind": "credential",
            "title": title,
            "text": "\n".join([f"title: {title}", *lines]),
        }

    records = [
        credential("정보처리기사", "status_label: 필기 합격, 실기 준비 중"),
        credential("SQLD", "earned_on: 2026-03-02", "status_label: 취득"),
        credential("토익", "earned_on: 2026-12-20"),
        credential("컴퓨터활용능력 1급"),
        {"kind": "course", "title": "합성 데이터베이스", "text": "title: 합성 데이터베이스"},
    ]
    # Earned by today, or a bare name as before; a status without an earned date is left to
    # the model, which reads the record.
    assert certificates.held_names(records, today) == ["SQLD", "컴퓨터활용능력 1급"]


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


METHOD = (
    "시험과목\n- 필기 1. 소프트웨어설계 2. 데이터베이스구축\n- 실기 : 정보처리 실무\n"
    "\n검정방법\n- 필기 : 객관식"
)


def test_official_subjects_come_only_from_the_subject_section():
    assert certificates.official_subjects(METHOD, []) == [
        "소프트웨어설계",
        "데이터베이스구축",
        "정보처리 실무",
    ]
    assert certificates.official_subjects("", ["A", " ", 3]) == ["A"]


class StudyModel:
    def __init__(self, weeks):
        self.weeks = weeks
        self.payloads = []

    def generate(self, instruction, payload, **options):
        self.payloads.append(payload)
        return {"weeks": self.weeks, "advice": "매주 기출을 풉니다."}


def week(n, subjects=(), hours=5):
    return {
        "week": n,
        "focus": f"{n}주차 목표",
        "subjects": list(subjects),
        "tasks": ["개념 정리", "문제 풀이"],
        "hours": hours,
        "related_records": ["합성 데이터베이스", "없는 기록"],
    }


def test_study_plan_keeps_official_subjects_and_rejects_short_plans(private):
    item = certificates.find("qnet-1320")
    scope = {"subjects": ["소프트웨어설계", "데이터베이스구축"], "text": "공식 원문: 정보처리 실무"}
    records = [{"kind": "course", "title": "합성 데이터베이스", "text": "SQL"}]
    model = StudyModel(
        [week(1, ["소프트웨어설계", "지어낸 과목"]), week(2, ["정보처리 실무"], hours=99), week(3)]
    )
    plan, advice = certificates.plan_study(model, item, scope, 3, 6, records)
    assert [w["subjects"] for w in plan] == [["소프트웨어설계"], ["정보처리 실무"], []]
    assert plan[1]["hours"] == 6 and plan[0]["related_records"] == ["합성 데이터베이스"]
    assert advice == "매주 기출을 풉니다."
    assert model.payloads[0]["weeks"] == 3
    with pytest.raises(AnalysisRejected):
        certificates.plan_study(StudyModel([week(1)]), item, scope, 8, 6, records)
    # Scope from Q-Net texts; a failed call leaves an empty scope instead of failing.
    assert certificates.study_scope(item, FakeQNet([]))["subjects"] == ["소프트웨어설계"]
    assert certificates.study_scope(item, FakeQNet(fail=True)) == {
        "subjects": [],
        "text": "",
        "source": None,
    }
    sqld = certificates.study_scope(certificates.find("private-sqld"))
    assert sqld["subjects"] == ["데이터 모델링의 이해", "SQL 기본 및 활용"]


@pytest.mark.integration
def test_study_plan_api(auth_client, monkeypatch, private):
    from datetime import timedelta

    from app.rag.career import api as career_api

    c = auth_client
    owner = authorization(register(c))
    monkeypatch.setattr(certificates.qnet, "QNet", lambda: FakeQNet([]))
    today = date(2026, 11, 24)
    monkeypatch.setattr(career_api, "seoul_today", lambda: today)
    record = post(
        c,
        owner,
        "experience-records",
        {"title": "합성 데이터베이스", "experience_type": "프로젝트", "result": "SQL"},
    )
    selection = {"kind": "experience", "record_id": record["id"], "expected_version": 1}
    path = "/api/v1/me/certificate-study-plans"
    body = {
        "certificate_id": "qnet-1320",
        "exam_date": "2026-12-10",
        "hours_per_week": 6,
        "records": [selection],
        "external_processing_consent": True,
    }
    assert c.post(path, headers=owner, json={**body, "exam_date": "2026-11-24"}).status_code == 422
    assert (
        c.post(path, headers=owner, json={**body, "certificate_id": "qnet-0000"}).status_code == 404
    )
    assert c.post(path, headers=owner, json={**body, "external_processing_consent": False}).json()[
        "missing_fields"
    ] == ["external_processing_consent"]
    c.app.state.gap_model = StudyModel([week(1, ["소프트웨어설계"]), week(2), week(3)])
    value = c.post(path, headers=owner, json=body).json()
    assert value["status"] == "completed", value
    # 16 days: three weeks counted back from the exam, never before today or on the exam day.
    assert [(w["start"], w["end"]) for w in value["weeks"]] == [
        ("2026-11-24", "2026-11-30"),
        ("2026-12-01", "2026-12-07"),
        ("2026-12-08", "2026-12-09"),
    ]
    assert value["scope"]["subjects"] == ["소프트웨어설계"]
    assert value["weeks"][0]["related_records"] == ["합성 데이터베이스"]
    far = (today + timedelta(days=400)).isoformat()
    c.app.state.gap_model = StudyModel([week(n) for n in range(1, 27)])
    value = c.post(path, headers=owner, json={**body, "exam_date": far}).json()
    assert len(value["weeks"]) == 26
    assert value["weeks"][-1]["end"] == (today + timedelta(days=399)).isoformat()


def test_ministry_plan_fills_in_until_qnet_lists_next_year(private, monkeypatch):
    plan = {
        "notice": "합성 시행계획 공고",
        "source_url": "https://example.test/plan",
        "checked_at": "2026-11-24",
        "series": {
            "기사": [
                {
                    "name": "2027년 정기 기사 1회",
                    "doc_reg_start": "2027-01-12",
                    "doc_reg_end": "2027-01-15",
                    "doc_exam_start": "2027-02-07",
                    "doc_exam_end": "2027-03-04",
                    "prac_pass_start": None,
                }
            ]
        },
    }
    monkeypatch.setattr(certificates, "_plan", plan)
    item = certificates.find("qnet-1320")
    today = date(2026, 11, 24)
    rounds = [qnet.technical_round(qnet.parse_items(TECHNICAL)[0])]
    view = certificates.schedule(item, today, FakeQNet(rounds))
    assert view["status"] == "upcoming"
    assert view["source"] == "합성 시행계획 공고" and view["note"]
    assert [r["name"] for r in view["rounds"]] == ["2026년 정기 기사 3회", "2027년 정기 기사 1회"]
    assert view["next_registration"]["start"] == "2027-01-12"
    # Q-Net down: the plan still answers.
    assert certificates.schedule(item, today, FakeQNet(fail=True))["status"] == "upcoming"
    # Once Q-Net lists a registration ahead, its own rounds win.
    ahead = [round_("2027년 정기 기사 1회", "2027-01-13", "2027-02-08")]
    view = certificates.schedule(item, today, FakeQNet(ahead))
    assert view["source"].startswith("Q-Net") and view["note"] is None
    # 국가전문자격 have no plan.
    assert certificates.plan_rounds("사회복지사 1급") == []
