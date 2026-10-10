import json
from pathlib import Path
from types import SimpleNamespace
from uuid import UUID

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.api.dependencies import get_school_rag_service
from app.core.config import Settings
from app.main import create_app
from app.rag.school.contracts import GeneratedAnswer
from app.rag.school.retriever import SchoolRetriever
from app.rag.school.service import SchoolRagService
from app.rag.tests.test_school_rag import chunk
from app.services.assistant import create_school_rag_service

ENDPOINT = "/api/v1/assistant/queries"
CONTEXT = {
    "institution": "테스트대학교",
    "department": "테스트학과",
    "admission_year": 2026,
    "track": "single_major",
}


def install_service(client, chunks, generator=None):
    service = SchoolRagService(SchoolRetriever(chunks), generator)
    client.app.dependency_overrides[get_school_rag_service] = lambda: service
    return service


def ask(client, **overrides):
    payload = {"question": "사회봉사 인증 기준은?", "context": dict(CONTEXT)}
    payload.update(overrides)
    return client.post(ENDPOINT, json=payload)


def test_default_query_does_not_guess_and_includes_identifiers(client):
    response = ask(client)
    assert response.status_code == 200
    body = response.json()
    UUID(body["query_id"])
    UUID(response.headers["x-request-id"])
    assert body["status"] == "insufficient_evidence"
    assert body["reason"] == "no_approved_matching_evidence"
    assert body["answer"] is None and body["citations"] == []
    assert "candidates" not in body and "source_file" not in response.text


def test_missing_school_context_requests_only_required_fields(client):
    body = client.post(ENDPOINT, json={"question": "사회봉사 조건은?"}).json()
    assert body["status"] == "needs_user_input"
    assert body["reason"] == "school_context_required"
    assert body["missing_fields"] == ["institution", "department"]


def test_missing_academic_scope_is_not_inferred_from_question(client):
    context = {key: CONTEXT[key] for key in ("institution", "department")}
    body = ask(client, question="2026학년도 총 학점은?", context=context).json()
    assert body["status"] == "needs_user_input"
    assert body["missing_fields"] == ["admission_year", "track"]


def test_conflicting_admission_year_is_not_silently_overridden(client):
    body = ask(client, question="2025학번 봉사 조건은?").json()
    assert body["status"] == "needs_user_input"
    assert body["reason"] == "conflicting_admission_year"
    assert body["missing_fields"] == ["admission_year"]


def test_graduation_decision_requires_separate_rule_engine(client):
    class UnusedService:
        def search(self, *args, **kwargs):
            raise AssertionError("A graduation audit must not be passed to retrieval")

    service = SchoolRagService(UnusedService())
    client.app.dependency_overrides[get_school_rag_service] = lambda: service
    body = ask(client, question="저 졸업 가능한가요?").json()
    assert body["reason"] == "rule_engine_required"
    assert body["missing_fields"] == ["graduation_audit"]
    assert body["answer"] is None and body["citations"] == []


@pytest.mark.parametrize(
    "payload",
    [
        {"question": ""},
        {"question": "   "},
        {"question": "x" * 4001},
        {"question": "사회봉사", "preview": True},
        {"question": "사회봉사", "eligible_for_official_answers": True},
        {"question": "사회봉사", "context": {"institution": "  "}},
        {"question": "사회봉사", "context": {"admission_year": True}},
        {"question": "사회봉사", "context": {"admission_year": "2026"}},
        {"question": "사회봉사", "context": {"admission_year": 999}},
        {"question": "사회봉사", "context": {"admission_year": 10000}},
        {"question": "사회봉사", "context": {"user_id": "synthetic-private-id"}},
    ],
)
def test_invalid_input_and_preview_bypass_return_common_error(client, payload):
    response = client.post(ENDPOINT, json=payload)
    assert response.status_code == 422
    error = response.json()["error"]
    assert error["code"] == "VALIDATION_ERROR"
    assert error["request_id"] == response.headers["x-request-id"]
    assert error["field_errors"]
    assert "synthetic-private-id" not in response.text


@pytest.mark.parametrize(
    "field,value",
    [
        ("institution", "다른학교"),
        ("department", "다른학과"),
        ("admission_year", 2025),
        ("track", "double_major"),
    ],
)
def test_context_filters_do_not_return_other_students_evidence(client, field, value):
    install_service(client, [chunk()])
    context = dict(CONTEXT, **{field: value})
    body = ask(client, context=context).json()
    assert body["status"] == "insufficient_evidence"
    assert body["citations"] == []


def test_unapproved_candidates_never_become_public_citations(client):
    install_service(
        client, [chunk(review_status="needs_review", eligible_for_official_answers=False)]
    )
    body = ask(client).json()
    assert body["reason"] == "no_approved_matching_evidence"
    assert body["citations"] == [] and body["answer"] is None
    assert "candidates" not in body


def test_approved_evidence_does_not_generate_without_provider(client):
    install_service(client, [chunk()])
    body = ask(client).json()
    assert body["status"] == "failed"
    assert body["reason"] == "answer_generator_not_configured"


def test_synthetic_grounded_result_preserves_original_source_metadata(client):
    evidence = chunk()

    class SyntheticGenerator:
        def generate(self, request):
            return GeneratedAnswer("합성 학사규정의 사회봉사 기준 설명", [evidence["chunk_id"]])

    install_service(client, [evidence], SyntheticGenerator())
    response = ask(client)
    body = response.json()
    assert body["status"] == "grounded"
    citation = body["citations"][0]
    assert citation == {
        key: evidence[key] for key in ("chunk_id", "document_id", "title", "source_url", "page")
    } | {"excerpt": evidence["content"]}
    assert "source_file" not in response.text


def test_invented_generator_citation_is_rejected(client):
    class InvalidGenerator:
        def generate(self, request):
            return GeneratedAnswer("invented answer", ["invented-id"])

    install_service(client, [chunk()], InvalidGenerator())
    body = ask(client).json()
    assert body["status"] == "failed" and body["reason"] == "invalid_generator_citations"
    assert body["answer"] is None and body["citations"] == []


@pytest.mark.parametrize("invalid_result", [True, False])
def test_module_failures_do_not_leak_content_or_unvalidated_answers(client, caplog, invalid_result):
    class BrokenModule:
        def query(self, *args, **kwargs):
            if invalid_result:
                return SimpleNamespace(
                    status="grounded",
                    reason="generated_from_evidence",
                    answer="unverified-sensitive-text",
                    citations=[],
                    missing_fields=[],
                )
            raise RuntimeError("private-provider-token")

    client.app.dependency_overrides[get_school_rag_service] = lambda: BrokenModule()
    response = ask(client)
    assert response.status_code == 200
    assert response.json()["status"] == "failed"
    assert response.json()["reason"] == "rag_processing_failed"
    assert "unverified-sensitive-text" not in response.text + caplog.text
    assert "private-provider-token" not in response.text + caplog.text


def test_corpus_is_loaded_once_per_app_lifespan(tmp_path, monkeypatch):
    import app.services.assistant as module

    corpus = tmp_path / "chunks.jsonl"
    corpus.write_text(json.dumps(chunk()) + "\n", encoding="utf-8")
    original = module.load_chunks
    calls = []

    def counted(path):
        calls.append(path)
        return original(path)

    monkeypatch.setattr(module, "load_chunks", counted)
    settings = Settings(
        _env_file=None, postgres_password="synthetic", school_rag_corpus_path=corpus
    )
    with TestClient(create_app(settings)) as client:
        first = client.app.state.school_rag_service
        ask(client)
        ask(client)
        assert client.app.state.school_rag_service is first
    assert calls == [corpus]


def test_invalid_configured_corpus_fails_startup_without_exposing_content(tmp_path):
    corpus = tmp_path / "chunks.jsonl"
    corpus.write_text("private-invalid-document", encoding="utf-8")
    settings = Settings(
        _env_file=None, postgres_password="synthetic", school_rag_corpus_path=corpus
    )
    with pytest.raises(RuntimeError, match="school corpus cannot be loaded") as error:
        with TestClient(create_app(settings)):
            pass
    assert "private-invalid-document" not in str(error.value)


@pytest.mark.parametrize("environment", ["staging", "production"])
def test_file_based_corpus_cannot_be_used_as_production_approval_source(environment):
    with pytest.raises(ValidationError, match="local environment"):
        Settings(
            _env_file=None,
            postgres_password="synthetic",
            app_env=environment,
            school_rag_corpus_path=Path("backend/app/rag/output/chunks.jsonl"),
        )


def test_missing_explicit_corpus_does_not_silently_turn_into_empty_index(tmp_path):
    settings = Settings(
        _env_file=None,
        postgres_password="synthetic",
        school_rag_corpus_path=tmp_path / "missing.jsonl",
    )
    with pytest.raises(RuntimeError, match="school corpus cannot be loaded"):
        create_school_rag_service(settings)


def test_openapi_exposes_typed_contract_and_forbids_preview(client):
    schema = client.get("/api/v1/openapi.json").json()
    operation = schema["paths"][ENDPOINT]["post"]
    assert operation["requestBody"]["content"]["application/json"]["schema"]["$ref"].endswith(
        "AssistantQueryRequest"
    )
    assert schema["components"]["schemas"]["AssistantQueryRequest"]["additionalProperties"] is False
    assert schema["components"]["schemas"]["AssistantStatus"]["enum"] == [
        "grounded",
        "insufficient_evidence",
        "needs_user_input",
        "failed",
    ]
    assert "preview" not in schema["components"]["schemas"]["AssistantQueryRequest"]["properties"]
