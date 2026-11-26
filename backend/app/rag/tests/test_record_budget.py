"""Job analysis and recommendations accept every saved record; the model input stays bounded."""

from unittest.mock import Mock
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.rag.career.analyzer import EvidenceAnalyzer
from app.rag.career.api import RecommendationRequest
from app.rag.career.contracts import RECORD_TEXT_BUDGET, SearchQuery, fit_records
from app.rag.career.service import CareerService
from app.rag.tests.test_career import POSTING
from app.schemas.job_analysis import JobAnalysisRequest
from app.schemas.personalization import MAX_ANALYSIS_RECORDS, PersonalizationRequest


def selections(count):
    return [
        {"kind": "experience", "record_id": str(uuid4()), "expected_version": 1}
        for _ in range(count)
    ]


def record(text):
    return {"kind": "experience", "record_id": str(uuid4()), "version": 1, "text": text}


def test_job_analysis_and_recommendations_take_every_saved_record():
    JobAnalysisRequest.model_validate({"posting_text": "Python", "records": selections(200)})
    RecommendationRequest.model_validate(
        {"keyword": "Python", "region": "전국", "records": selections(MAX_ANALYSIS_RECORDS)}
    )
    with pytest.raises(ValidationError):
        JobAnalysisRequest.model_validate({"posting_text": "Python", "records": selections(201)})
    with pytest.raises(ValidationError):
        RecommendationRequest.model_validate(
            {"keyword": "Python", "region": "전국", "records": selections(201)}
        )
    # Features that still send only records the student picked keep their limit.
    with pytest.raises(ValidationError):
        PersonalizationRequest.model_validate({"records": selections(21)})


def test_records_within_the_budget_are_all_kept_in_order():
    values = [record(f"기록 {i} Python") for i in range(150)]
    assert fit_records(values, "Python 개발") is values


def test_past_the_budget_the_records_sharing_posting_terms_are_kept():
    filler = "가" * 7000
    unrelated = [record(filler) for _ in range(12)]
    relevant = [record(filler[:6000] + " Python FastAPI PostgreSQL") for _ in range(3)]
    values = unrelated[:5] + relevant + unrelated[5:]
    kept = fit_records(values, "필수: Python, FastAPI, PostgreSQL 경험")
    assert sum(len(item["text"]) for item in kept) <= RECORD_TEXT_BUDGET
    assert all(item in kept for item in relevant)
    # Original order is preserved among the kept records.
    assert kept == [item for item in values if item in kept]


def comparison(quote):
    return {
        "priority": "required",
        "requirement": "Python",
        "posting_quote": quote,
        "status": "insufficient_evidence",
        "personal_evidence": [],
        "explanation": "근거 부족",
    }


def test_the_model_receives_only_the_records_that_fit():
    model = Mock()
    model.generate.return_value = {"comparisons": [comparison(POSTING.text[:10])]}
    values = [record("나" * 7000) for _ in range(30)]
    EvidenceAnalyzer(model).analyze(POSTING.text, {"records": values})
    sent = model.generate.call_args.args[1]["records"]
    assert 0 < len(sent) < 30
    assert sum(len(item["text"]) for item in sent) <= RECORD_TEXT_BUDGET


def test_recommendations_say_when_only_part_of_the_records_were_compared():
    source = Mock()
    source.name = "saramin"
    source.search.return_value = [POSTING]
    model = Mock()
    model.generate.return_value = {"comparisons": [comparison(POSTING.text[:10])]}
    service = CareerService([source], EvidenceAnalyzer(model))
    context = {"records": [record("다" * 7000) for _ in range(30)]}
    result = service.recommend(
        SearchQuery("개발", "전국", nationwide=True), context, allow_personal_analysis=True
    )
    [item] = result["items"]
    assert any("전체 30개" in warning for warning in item["warnings"])
    small = {"records": [record("Python 프로젝트") for _ in range(30)]}
    result = service.recommend(
        SearchQuery("개발", "전국", nationwide=True), small, allow_personal_analysis=True
    )
    assert not any("전체" in warning for warning in result["items"][0]["warnings"])


def test_recommendation_request_with_25_saved_records_and_a_document_is_not_rejected():
    import base64
    from types import SimpleNamespace
    from unittest.mock import patch

    from app.rag.career.api import recommendations
    from app.rag.career.contracts import Posting
    from app.schemas.personalization import PersonalEvidence, PersonalizationContext

    saved = [
        PersonalEvidence(
            kind="experience",
            record_id=uuid4(),
            version=1,
            title=f"기록 {i}",
            text=f"합성 프로젝트 {i}",
            truncated=False,
        )
        for i in range(25)
    ]
    identity = SimpleNamespace(user=SimpleNamespace(id="owner", display_name="합성사용자"))
    model = Mock()
    model.generate.return_value = {"comparisons": [comparison("Python")]}
    request = SimpleNamespace(
        app=SimpleNamespace(
            state=SimpleNamespace(
                portfolio_analyzer=EvidenceAnalyzer(model),
                settings=SimpleNamespace(vertex_model="gemini-3.8-flash"),
            )
        )
    )
    payload = RecommendationRequest(
        keyword="engineer",
        region="서울",
        records=[
            {"kind": "experience", "record_id": str(r.record_id), "expected_version": 1}
            for r in saved
        ],
        documents=[
            {"filename": "note.txt", "content_base64": base64.b64encode(b"Python").decode()}
        ],
        external_processing_consent=True,
    )
    posting = Posting(
        "greenhouse",
        "example/1",
        "Engineer",
        "Test",
        "서울",
        "https://job-boards.greenhouse.io/example/jobs/1",
        "Python required",
        "2026-01-01T00:00:00+00:00",
        text_scope="full_text",
    )
    with (
        patch.dict(
            "os.environ",
            {
                "CAREER_SOURCE_MODE": "api",
                "CAREER_GREENHOUSE_BOARD": "example",
                "SARAMIN_ACCESS_KEY": "",
                "WORK24_AUTH_KEY": "",
            },
        ),
        patch("app.rag.career.api.assemble", return_value=PersonalizationContext(records=saved)),
        patch("app.services.auth.throttle"),
        patch("app.services.auth.current_identity", return_value=identity),
        patch("app.services.gemini.reserve_call"),
        patch("app.rag.career.api.Greenhouse.search", return_value=[posting]),
    ):
        result = recommendations(payload, request, Mock(), identity)
    assert result["items"][0]["analysis_status"] == "completed"
    # All 25 saved records and the document chunk reached the comparison.
    assert len(model.generate.call_args.args[1]["records"]) == 26
