"""Gap analysis over several synthetic postings: only verified citations reach the student."""

import pytest

from app.rag.career.contracts import AnalysisRejected
from app.rag.career.gap import UNVERIFIED, analyze_gap

RECORD = {
    "kind": "experience",
    "record_id": "00000000-0000-4000-8000-000000000051",
    "version": 2,
    "text": "합성 팀 프로젝트에서 React로 화면을 만들고 REST API를 연동했다.",
    "truncated": False,
}
POSTINGS = [
    {"title": "합성 프론트엔드 개발자", "text": "자격요건: React 실무 경험\n우대: 정보처리기사"},
    {"title": "합성 웹 개발자", "text": "필수: React  실무 경험 2년\nTypeScript 사용 경험"},
]


class Model:
    def __init__(self, output):
        self.output, self.calls = output, []

    def generate(self, instruction, payload, **options):
        self.calls.append(payload)
        return self.output


def requirement(name, postings, status="insufficient_evidence", evidence=(), actions=()):
    return {
        "requirement": name,
        "category": "skill",
        "postings": list(postings),
        "status": status,
        "personal_evidence": list(evidence),
        "explanation": f"{name} 설명",
        "actions": list(actions),
    }


def test_requirements_keep_verified_postings_and_sort_by_frequency():
    react = requirement(
        "React 실무 경험",
        # The second posting has two spaces: matched ignoring spacing, excerpt stays verbatim.
        [{"posting": 1, "quote": "React 실무 경험"}, {"posting": 2, "quote": "React 실무 경험"}],
        "supported",
        [{**{k: RECORD[k] for k in ("kind", "record_id", "version")}, "excerpt": "React로 화면"}],
        [{"type": "project", "title": "무시됨", "detail": "supported는 행동 없음", "weeks": 2}],
    )
    certificate = requirement(
        "정보처리기사",
        [{"posting": 1, "quote": "정보처리기사"}, {"posting": 9, "quote": "정보처리기사"}],
        actions=[
            {"type": "certificate", "title": "정보처리기사", "detail": "필기 준비", "weeks": 8},
            {"type": "lottery", "title": "x", "detail": "y", "weeks": 1},
            {"type": "study", "title": "기출", "detail": "주 2회", "weeks": 99},
        ],
    )
    invented = requirement("Kubernetes", [{"posting": 2, "quote": "Kubernetes 운영"}])
    model = Model({"requirements": [certificate, invented, react], "summary": " 요약 "})
    result, summary, notes = analyze_gap(model, POSTINGS, [RECORD])

    assert [r["requirement"] for r in result] == ["React 실무 경험", "정보처리기사"]
    react_out, cert_out = result
    assert react_out["frequency"] == 2
    assert [p["excerpt"] for p in react_out["postings"]] == ["React 실무 경험", "React  실무 경험"]
    assert react_out["personal_evidence"][0]["excerpt"] == "React로 화면"
    assert react_out["actions"] == []
    assert cert_out["frequency"] == 1
    assert cert_out["actions"] == [
        {"type": "certificate", "title": "정보처리기사", "detail": "필기 준비", "weeks": 8},
        {"type": "study", "title": "기출", "detail": "주 2회", "weeks": None},
    ]
    assert summary == "요약"
    assert notes == ["공고 원문에서 위치를 확인하지 못한 요건 1개는 결과에서 뺐습니다."]
    sent = model.calls[0]
    assert [p["posting"] for p in sent["postings"]] == [1, 2]
    assert sent["records"][0]["record_id"] == RECORD["record_id"]


def test_unverified_record_citation_becomes_guidance_not_a_claim():
    claimed = requirement(
        "TypeScript 사용 경험",
        [{"posting": 2, "quote": "TypeScript 사용 경험"}],
        "supported",
        [{**{k: RECORD[k] for k in ("kind", "record_id", "version")}, "excerpt": "TypeScript"}],
        [{"type": "project", "title": "TS 전환", "detail": "기존 화면 TS 전환", "weeks": 3}],
    )
    result, _, notes = analyze_gap(Model({"requirements": [claimed]}), POSTINGS, [RECORD])
    assert result[0]["status"] == "insufficient_evidence"
    assert result[0]["personal_evidence"] == []
    assert result[0]["explanation"] == UNVERIFIED
    assert result[0]["actions"][0]["title"] == "TS 전환"
    assert "준비 방법 위주로" in notes[-1]


def test_nothing_verifiable_fails_and_no_postings_is_rejected():
    with pytest.raises(AnalysisRejected):
        analyze_gap(
            Model({"requirements": [requirement("없음", [{"posting": 1, "quote": "없는 문장"}])]}),
            POSTINGS,
            [RECORD],
        )
    with pytest.raises(AnalysisRejected):
        analyze_gap(Model({"requirements": []}), [], [RECORD])
    result, summary, _ = analyze_gap(Model({"requirements": []}), POSTINGS, [RECORD])
    assert result == [] and summary is None
