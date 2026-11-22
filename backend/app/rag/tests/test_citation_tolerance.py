"""Synthetic only: extraction spacing differences and one bad item no longer fail a posting."""

import logging
from unittest.mock import Mock

import pytest

from app.rag.career.analyzer import EvidenceAnalyzer, locate_quote, spans
from app.rag.career.contracts import AnalysisRejected, SearchQuery, failure_reason
from app.rag.career.documents import prepare_documents
from app.rag.career.service import CareerService
from app.rag.tests.test_career import POSTING

RID = "00000000-0000-4000-8000-000000000011"
# PDF extraction often drops spaces and breaks lines mid-sentence.
RECORD_TEXT = (
    "캠퍼스스터디매칭서비스\nSpringBoot3와JPA로매칭API를\n설계하고 MySQL스키마를정규화했습니다."
)
CONTEXT = {"records": [{"kind": "experience", "record_id": RID, "version": 1, "text": RECORD_TEXT}]}
POSTING_TEXT = (
    "자격 면허: 정보처리기사 우대\n기타 우대사항: - 정보처리기사 보유 - 웹/앱 개발 경험 - Java 숙련"
)
SECRET = "합성-비공개-문장"


def cite(excerpt):
    return {"kind": "experience", "record_id": RID, "version": 1, "excerpt": excerpt}


def comparison(quote, status="supported", evidence=(), explanation="설명"):
    return {
        "priority": "preferred",
        "requirement": "요건",
        "posting_quote": quote,
        "status": status,
        "personal_evidence": list(evidence),
        "explanation": explanation,
    }


def analyzer(*values):
    return EvidenceAnalyzer(Mock(generate=Mock(return_value={"comparisons": list(values)})))


def test_spacing_differences_resolve_to_the_original_text():
    quote = "Spring Boot 3와 JPA로 매칭 API를 설계하고"
    [(start, end)] = spans(RECORD_TEXT, quote)
    assert RECORD_TEXT[start:end] == "SpringBoot3와JPA로매칭API를\n설계하고"
    # Exact occurrences win, repeated wording gives every occurrence, short fragments need exact.
    assert spans("ab ab", "ab") == [(0, 2), (3, 5)]
    assert spans("정보 처리", "정보처리") == [(0, 5)]
    assert spans("정보 처리", "정보처") == []
    assert spans(RECORD_TEXT, "Django로 API를 설계하고") == []


def test_a_section_heading_in_front_of_a_list_item_is_left_out():
    start, end = locate_quote(POSTING_TEXT, "기타 우대사항: - 웹/앱 개발 경험", set())
    assert POSTING_TEXT[start:end] == "웹/앱 개발 경험"
    with pytest.raises(AnalysisRejected):
        locate_quote(POSTING_TEXT, "기타 우대사항: - Python 경험", set())


def test_unverifiable_items_are_dropped_or_downgraded_one_by_one(caplog):
    model_output = [
        comparison("정보처리기사 우대", evidence=[cite("Spring Boot 3와 JPA로")]),
        comparison(SECRET),
        comparison(
            "웹/앱 개발 경험", evidence=[cite("MySQL 스키마를 정규화했습니다."), cite(SECRET)]
        ),
        comparison("Java 숙련", evidence=[cite(SECRET)], explanation=SECRET),
    ]
    with caplog.at_level(logging.WARNING):
        values, notes = analyzer(*model_output).analyze_detailed(POSTING_TEXT, CONTEXT)
    assert [v["status"] for v in values] == ["supported", "supported", "insufficient_evidence"]
    assert values[0]["personal_evidence"][0]["excerpt"] == "SpringBoot3와JPA로"
    assert [c["excerpt"] for c in values[1]["personal_evidence"]] == [
        "MySQL스키마를정규화했습니다."
    ]
    assert values[2]["personal_evidence"] == []
    for value in values:
        evidence = value["posting_evidence"]
        assert POSTING_TEXT[evidence["start"] : evidence["end"]] == evidence["excerpt"]
        for citation in value["personal_evidence"]:
            assert citation["excerpt"] in RECORD_TEXT
    assert notes == [
        "공고 원문에서 위치를 확인하지 못한 조건 1개는 결과에서 뺐습니다.",
        "근거 문장을 기록 원문에서 확인하지 못한 조건 1개는 근거 부족으로 표시했습니다.",
    ]
    assert "dropped=posting_quote:1 downgraded=1 citations_removed=2" in caplog.text
    assert SECRET not in caplog.text and SECRET not in str(values)


def test_nothing_verifiable_still_fails_with_the_main_reason():
    with pytest.raises(AnalysisRejected) as caught:
        analyzer(comparison(SECRET), comparison("없는 조건"), {"priority": "x"}).analyze(
            POSTING_TEXT, CONTEXT
        )
    assert failure_reason(caught.value) == "posting_quote"
    assert analyzer().analyze(POSTING_TEXT, CONTEXT) == []


def test_document_control_characters_become_spaces():
    raw = "Spring\x01Boot\x013와\x01JPA로\x00설계".encode()
    uploaded, _, _ = prepare_documents([("synthetic.txt", raw)])
    assert uploaded["records"][0]["text"] == "Spring Boot 3와 JPA로 설계"


def test_recommendation_item_shows_the_notes():
    source = Mock()
    source.name = "saramin"
    source.search.return_value = [POSTING]
    model = analyzer(
        comparison("정보처리기사 우대", evidence=[cite("SpringBoot3와JPA로")]), comparison(SECRET)
    )
    result = CareerService([source], model).recommend(
        SearchQuery("개발", "전국", nationwide=True), CONTEXT, allow_personal_analysis=True
    )
    item = result["items"][0]
    assert item["analysis_status"] == "completed" and len(item["comparisons"]) == 1
    assert "공고 원문에서 위치를 확인하지 못한 조건 1개는 결과에서 뺐습니다." in item["warnings"]
