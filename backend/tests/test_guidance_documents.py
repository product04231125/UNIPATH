import base64
from types import SimpleNamespace as NS
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.core.auth_errors import AuthError
from app.schemas.personalization import PersonalizationContext
from app.schemas.personalized_guidance import GuidanceDocument, PersonalizedGuidanceRequest
from app.services.personalization import guidance


def document(text="봉사 12시간 contact@example.test"):
    return GuidanceDocument(
        filename="봉사.txt", content_base64=base64.b64encode(text.encode()).decode()
    )


def test_extracts_redacted_text_with_source():
    result = guidance.document_context(
        [document()], PersonalizationContext(records=[]), NS(user=NS(display_name="학생"))
    )
    record = result.records[0]
    assert "봉사.txt" in record.title and "본문" in record.title
    assert "contact@example.test" not in record.text
    assert "12시간" in record.text and record.official is False


def test_ocr_reuses_pipeline_and_labels_source(monkeypatch):
    from app.rag.career.ocr import DocumentOCR

    monkeypatch.setattr(DocumentOCR, "scan", lambda self, load: "도서관 봉사 12시간")
    doc = GuidanceDocument(
        filename="증빙.png", content_base64=base64.b64encode(b"synthetic").decode()
    )
    result = guidance.document_context(
        [doc], PersonalizationContext(records=[]), NS(user=NS(display_name="학생"))
    )
    assert "OCR 원본 대조 필요" in result.records[0].title
    assert "이미지" in result.records[0].title


def test_invalid_files_and_limits():
    identity = NS(user=NS(display_name="학생"))
    with pytest.raises(AuthError):
        guidance.document_context(
            [GuidanceDocument(filename="bad.pdf", content_base64="!!!!")],
            PersonalizationContext(records=[]),
            identity,
        )
    with pytest.raises(AuthError):
        guidance.document_context(
            [
                GuidanceDocument(
                    filename="broken.pdf", content_base64=base64.b64encode(b"not-pdf").decode()
                )
            ],
            PersonalizationContext(records=[]),
            identity,
        )
    with pytest.raises(ValidationError):
        PersonalizedGuidanceRequest(
            question="학사 안내",
            context={"institution_id": uuid4(), "department_id": uuid4()},
            documents=[document()] * 6,
        )
    with pytest.raises(AuthError):
        guidance.document_context(
            [document("봉사 12시간\n" * 24001)], PersonalizationContext(records=[]), identity
        )


def test_document_only_answer_and_consent_gate(monkeypatch):
    identity = NS(user=NS(id=uuid4(), display_name="학생"))
    school = NS(
        status="evidence_found",
        sources=[NS(chunk_id=uuid4(), title="봉사 기준", page=1, excerpt="봉사 안내")],
    )
    empty = PersonalizationContext(records=[])
    monkeypatch.setattr(guidance.auth, "current_identity", lambda *args: identity)
    monkeypatch.setattr(guidance.auth, "throttle", lambda *args, **kwargs: None)
    monkeypatch.setattr(guidance.knowledge_queries, "execute", lambda *args, **kwargs: school)
    monkeypatch.setattr(guidance.knowledge_queries, "selection", lambda *args: ("stable",))
    monkeypatch.setattr(guidance, "assemble", lambda *args: empty)
    monkeypatch.setattr(guidance.gemini, "reserve_call", lambda *args: None)
    monkeypatch.setattr(guidance, "PersonalizedGuidanceResponse", lambda **kwargs: NS(**kwargs))
    db = NS(expire_all=lambda: None, rollback=lambda: None)
    payload = PersonalizedGuidanceRequest(
        question="봉사 신청 안내",
        context={"institution_id": uuid4(), "department_id": uuid4()},
        documents=[document()],
    )
    calls = []

    class Model:
        def generate(self, instruction, value):
            calls.append(value)
            record = value["personal_records"][0]
            return {
                "answer": "내 자료 기준 봉사 신청 안내",
                "school_chunk_ids": [str(school.sources[0].chunk_id)],
                "personal_evidence": [
                    {
                        "kind": record["kind"],
                        "record_id": record["record_id"],
                        "version": record["version"],
                        "excerpt": "봉사 12시간",
                    }
                ],
                "insufficient_evidence": False,
            }

    original = guidance.document_context
    extracted = []

    def capture(*args):
        extracted.append(True)
        return original(*args)

    monkeypatch.setattr(guidance, "document_context", capture)
    response = guidance.execute(db, NS(), payload, None, Model())
    assert response.reason == "external_processing_consent_required"
    assert not extracted and not calls
    payload.external_processing_consent = True
    response = guidance.execute(db, NS(), payload, None, Model())
    assert response.status == "grounded"
    assert len(calls) == 1 and response.personal_citations
    assert "contact@example.test" not in str(calls)
    assert "봉사.txt" in response.personal.records[0].title
    # Without a configured generator no answer can follow, so files are not read at all.
    extracted.clear()
    response = guidance.execute(db, NS(), payload, None, None)
    assert response.reason == "generator_not_configured" and not extracted
