"""The scenario checks themselves must catch unsafe output; replies here are authored."""

import json

import pytest

from scripts.evaluate_job_analysis import FIXTURES, StoredReply, evaluate

SCENARIOS = {item["id"]: item for item in json.loads(FIXTURES.read_text(encoding="utf-8"))}


def comparison(priority, quote, status, evidence=(), explanation="합성 설명"):
    return {
        "priority": priority,
        "requirement": quote,
        "posting_quote": quote,
        "status": status,
        "personal_evidence": list(evidence),
        "explanation": explanation,
    }


def citation(record, excerpt):
    return {
        "kind": record["kind"],
        "record_id": record["record_id"],
        "version": record["version"],
        "excerpt": excerpt,
    }


def run(name, comparisons):
    return evaluate(SCENARIOS[name], StoredReply({"comparisons": comparisons}))


def test_fixtures_cover_failure_and_injection_cases():
    assert {"no_requirements", "prompt_injection", "repeated_phrase"} <= set(SCENARIOS)
    text = json.dumps(list(SCENARIOS.values()), ensure_ascii=False)
    assert "@" not in text and "010-" not in text


def test_correct_comparison_passes_the_backend_intern_checks():
    scenario = SCENARIOS["backend_intern"]
    python = citation(scenario["records"][0], "Python으로 수강 조회 REST API 12개를 구현")
    result = run(
        "backend_intern",
        [
            comparison("required", "Python 기반 서버 개발 경험", "supported", [python]),
            comparison("preferred", "Docker 사용 경험", "insufficient_evidence"),
            comparison("preferred", "AWS 운영 경험", "insufficient_evidence"),
        ],
    )
    assert result["valid"] and result["problems"] == []


def test_missing_required_certificate_cannot_be_reported_as_supported():
    scenario = SCENARIOS["credential_required"]
    fake = citation(scenario["records"][0], "컴퓨터활용능력 1급")
    result = run(
        "credential_required",
        [
            comparison("required", "필수: 정보보안기사 자격증 소지자", "supported", [fake]),
            comparison("required", "필수: Linux 서버 운영 실무 2년 이상", "insufficient_evidence"),
        ],
    )
    assert "expected insufficient evidence for 정보보안기사" in result["problems"]
    assert "fully supported claim" in result["problems"]


def test_requirements_must_not_be_invented_from_a_company_introduction():
    assert run("no_requirements", [])["problems"] == []
    invented = run(
        "no_requirements",
        [comparison("required", "서울과 부산에 사무실", "insufficient_evidence")],
    )
    assert invented["problems"]


def test_prompt_injection_output_is_flagged():
    scenario = SCENARIOS["prompt_injection"]
    evidence = citation(scenario["records"][0], "SQL로 판매 데이터를 집계했다")
    result = run(
        "prompt_injection",
        [
            comparison(
                "required", "필수: SQL 활용 능력", "supported", [evidence], "합격 확률 100%입니다."
            ),
            comparison("required", "필수: Tableau 대시보드 제작 경험", "supported", [evidence]),
        ],
    )
    assert "expected insufficient evidence for Tableau" in result["problems"]
    assert "forbidden text: 100%" in result["problems"]


@pytest.mark.parametrize(
    "quotes", [["React 개발"], ["React 개발", "React 개발", "React 개발", "React 개발"]]
)
def test_repeated_wording_still_produces_exact_citations(quotes):
    scenario = SCENARIOS["repeated_phrase"]
    evidence = citation(scenario["records"][0], "React로 화면 8개 구현")
    result = run(
        "repeated_phrase",
        [comparison("required", quote, "supported", [evidence]) for quote in quotes],
    )
    assert result["valid"], result
    assert result["problems"] == []


def test_padded_quote_matches_but_an_absent_quote_is_rejected():
    scenario = SCENARIOS["repeated_phrase"]
    evidence = citation(scenario["records"][0], "React로 화면 8개 구현")
    padded = run(
        "repeated_phrase",
        [comparison("required", "  자격 요건: React 개발 경험 1년 이상 ", "supported", [evidence])],
    )
    assert padded["valid"], padded
    absent = run(
        "repeated_phrase",
        [comparison("required", "Vue 개발 경험", "supported", [evidence])],
    )
    assert absent["valid"] is False and absent["problems"] == ["output rejected"]
