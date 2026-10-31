from datetime import UTC, datetime, timedelta
from unittest.mock import patch
from uuid import uuid4

import pytest
from pydantic import ValidationError
from sqlalchemy import select
from test_academic import department, operator, post, school
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register

from app.models.identity import IdentityAudit
from app.models.knowledge import KnowledgeChunk, KnowledgeDocument
from app.rag.school.contracts import GeneratedAnswer
from app.schemas.knowledge import KnowledgeApprove, KnowledgeCreate, PageReplace

ROOT = "/api/v1/admin/knowledge-revisions"
integration = pytest.mark.integration


def applied_document(c, h, institution, dep=None, curriculum=None, **extra):
    body = {
        "name": "합성 공식 봉사 규정",
        "institution_id": institution["id"],
        "department_id": dep["id"] if dep else None,
        "curriculum_id": curriculum["id"] if curriculum else None,
        "source_url": "https://school.example.invalid/regulations.pdf",
        "document_type": "academic",
        **extra,
    }
    source = post(c, h, "documents", body)
    response = c.post(
        "/api/v1/admin/documents/" + source["id"] + "/apply",
        headers=h,
        json={"expected_version": source["version"]},
    )
    assert response.status_code == 200, response.text
    return response.json()


def create(c, h, source, page_count=1):
    body = {
        "source_document_id": source["id"],
        "expected_source_version": source["version"],
        "document_hash": "a" * 64,
        "page_count": page_count,
        "extractor_version": "synthetic-test-v2",
        "source_checked_on": datetime.now(UTC).date().isoformat(),
    }
    response = c.post(ROOT, headers=h, json=body)
    assert response.status_code == 201, response.text
    return response.json()


def replace(
    c, h, document, page=1, *, content="합성 사회봉사 승인 조건은 10시간입니다.", parts=None
):
    body = {
        "expected_version": document["version"],
        "parts": parts
        or [{"content": content, "admission_years": [2026], "tracks": ["single_major"]}],
    }
    response = c.put(ROOT + "/" + document["id"] + "/pages/" + str(page), headers=h, json=body)
    assert response.status_code == 200, response.text
    document["version"] = response.json()["version"]
    return response.json()


def approval(document, **extra):
    return {
        "expected_version": document["version"],
        "reviewed_document_hash": document["document_hash"],
        "source_verified": True,
        "applicability_verified": True,
        "extraction_verified": True,
        "complete_document_verified": True,
        "review_note": "합성 테스트 검토 — 실제 규정 승인 아님",
        **extra,
    }


def approve(c, h, document, expected=200):
    response = c.post(ROOT + "/" + document["id"] + "/approve", headers=h, json=approval(document))
    assert response.status_code == expected, response.text
    if expected == 200:
        document.update(response.json())
    return response.json()


def context(institution, dep, curriculum=None, **extra):
    return {
        "institution_id": institution["id"],
        "department_id": dep["id"],
        "curriculum_id": curriculum["id"] if curriculum else None,
        "admission_year": 2026,
        "track": "single_major",
        **extra,
    }


def search(
    c, h, scope, *, question="사회봉사 승인 조건은?", endpoint="school-searches", expected=200
):
    response = c.post(
        "/api/v1/me/" + endpoint, headers=h, json={"question": question, "context": scope}
    )
    assert response.status_code == expected, response.text
    assert response.headers["Cache-Control"] == "no-store"
    return response.json()


class SyntheticGenerator:
    def __init__(self):
        self.calls = []

    def generate(self, request):
        self.calls.append(request)
        return GeneratedAnswer(
            "합성 규정의 봉사 조건 설명입니다.", [request.evidence[0]["chunk_id"]]
        )


def test_explicit_review_contract_rejects_flags_from_untrusted_ingestion():
    body = {
        "source_document_id": str(uuid4()),
        "expected_source_version": 1,
        "document_hash": "a" * 64,
        "page_count": 1,
        "extractor_version": "synthetic",
        "source_checked_on": "2026-10-19",
    }
    for extra in [
        {"approved": True},
        {"eligible_for_official_answers": True},
        {"institution_id": str(uuid4())},
        {"page_count": True},
    ]:
        with pytest.raises(ValidationError):
            KnowledgeCreate.model_validate({**body, **extra})
    draft = {"id": str(uuid4()), "version": 1, "document_hash": "a" * 64}
    for change in [{"source_verified": False}, {"extraction_verified": 1}, {"review_note": " "}]:
        with pytest.raises(ValidationError):
            KnowledgeApprove.model_validate(approval(draft, **change))
    for parts in [
        [{"content": " \n"}],
        [{"content": "x" * 20000}, {"content": "y"}],
        [{"content": "text", "tracks": ["single_major", "single_major"]}],
    ]:
        with pytest.raises(ValidationError):
            PageReplace.model_validate({"expected_version": 1, "parts": parts})


@integration
def test_complete_scoped_review_search_generation_and_terminal_revocation(auth_client, auth_db):
    c, h = auth_client, operator(auth_client, auth_db)
    inst = school(c, h)
    dep = department(c, h, inst)
    source = applied_document(c, h, inst, dep)
    document = create(c, h, source, page_count=2)
    student = authorization(register(c, "knowledge-student@example.test"))
    scope = context(inst, dep)
    assert search(c, student, scope)["status"] == "insufficient_evidence"
    first = replace(
        c,
        h,
        document,
        parts=[
            {"content": "합성 사회봉사 ", "admission_years": [2026], "tracks": ["single_major"]},
            {"content": "승인 기준 10시간.", "admission_years": [2026], "tracks": ["single_major"]},
        ],
    )
    assert first["parts"][0]["character_start"] == 0
    assert first["parts"][1]["character_start"] == len(first["parts"][0]["content"])
    approve(c, h, document, expected=422)  # An exception page is still absent.
    replace(c, h, document, page=2, content="합성 예외: 특정 경로의 예외를 별도로 확인하세요.")
    assert search(c, student, scope)["status"] == "insufficient_evidence"
    approve(c, h, document)
    result = search(c, student, scope)
    assert result["status"] == "evidence_found"
    assert {s["document_id"] for s in result["sources"]} == {source["id"]}
    assert all(s["source_url"] == source["source_url"] for s in result["sources"])
    applicability = result["sources"][0]["applicability"]
    assert applicability["institution_id"] == inst["id"]
    assert applicability["department_id"] == dep["id"]
    assert applicability["source_version"] == source["version"]
    assert applicability["knowledge_document_id"] == document["id"]
    assert applicability["knowledge_version"] == document["version"]
    assert applicability["admission_years"] == [2026]
    assert applicability["tracks"] == ["single_major"]
    assert "answer" not in result and "source_file" not in str(result)
    no_generator = search(c, student, scope, endpoint="school-queries")
    assert (no_generator["status"], no_generator["reason"]) == (
        "failed",
        "answer_generator_not_configured",
    )
    generator = SyntheticGenerator()
    c.app.state.knowledge_index_cache.generator = generator
    grounded = search(c, student, scope, endpoint="school-queries")
    assert grounded["status"] == "grounded" and grounded["citations"]
    assert grounded["citations"][0]["applicability"] == applicability
    assert len(generator.calls[-1].evidence) == 3  # Both parts and the exception page.
    assert not search(c, student, context(inst, dep, admission_year=2025))["sources"]
    missing = search(c, student, context(inst, dep, admission_year=None, track=None))
    assert missing["status"] == "needs_user_input" and missing["sources"] == []
    assert missing["missing_fields"] == ["admission_year", "track"]
    assert (
        search(c, student, scope, question="저 졸업 가능한가요?")["reason"]
        == "rule_engine_required"
    )
    response = c.put(
        ROOT + "/" + document["id"] + "/pages/1",
        headers=h,
        json={"expected_version": document["version"], "parts": [{"content": "수정"}]},
    )
    assert response.status_code == 409
    response = c.post(
        ROOT + "/" + document["id"] + "/revoke",
        headers=h,
        json={"expected_version": document["version"], "reason": "합성 승인 회수"},
    )
    assert response.status_code == 200
    assert search(c, student, scope)["status"] == "insufficient_evidence"
    assert search(c, student, scope, endpoint="school-queries")["answer"] is None
    assert len(generator.calls) == 1  # Revocation prevents cache reuse and further generation.
    assert (
        c.delete(
            ROOT + "/" + document["id"] + "?expected_version=" + str(response.json()["version"]),
            headers=h,
        ).status_code
        == 409
    )
    with auth_db() as db:
        assert db.scalar(select(KnowledgeChunk)) is not None  # History retained for review.
        audits = list(
            db.scalars(select(IdentityAudit).where(IdentityAudit.action.like("knowledge:%")))
        )
        assert {a.action for a in audits} >= {
            "knowledge:create",
            "knowledge:approve",
            "knowledge:revoke",
        }
        assert all("조건" not in a.action and "검토" not in a.action for a in audits)


@integration
def test_unknown_scope_warnings_and_stale_versions_cannot_be_approved(auth_client, auth_db):
    c, h = auth_client, operator(auth_client, auth_db)
    inst = school(c, h)
    dep = department(c, h, inst)
    source = applied_document(c, h, inst, dep)
    document = create(c, h, source)
    page = replace(
        c,
        h,
        document,
        parts=[{"content": "합성 봉사 표", "warnings": ["table_structure_requires_review"]}],
    )
    approve(c, h, document, expected=422)
    page = replace(c, h, document)
    bad = approval(document, expected_version=1)
    assert c.post(ROOT + "/" + document["id"] + "/approve", headers=h, json=bad).status_code == 409
    bad = approval(document, reviewed_document_hash="b" * 64)
    assert c.post(ROOT + "/" + document["id"] + "/approve", headers=h, json=bad).status_code == 409
    approve(c, h, document)
    assert (
        page["parts"][0]["id"]
        == c.get(ROOT + "/" + document["id"] + "/pages/1", headers=h).json()["parts"][0]["id"]
    )


@integration
def test_students_other_schools_and_revoked_administrators_cannot_manage_sources(
    auth_client, auth_db
):
    c, root = auth_client, operator(auth_client, auth_db)
    inst = school(c, root)
    dep = department(c, root, inst)
    document = create(c, root, applied_document(c, root, inst, dep))
    student_response = register(c, "knowledge-staff@example.test")
    student = authorization(student_response)
    assert c.get(ROOT, headers=student).status_code == 403
    assert c.get(ROOT + "/" + document["id"], headers=student).status_code == 403
    other = school(c, root, "다른 합성대")
    scope = post(
        c,
        root,
        "scopes",
        {
            "user_id": student_response.json()["user"]["id"],
            "institution_id": other["id"],
            "reason": "합성 범위",
        },
    )
    assert c.get(ROOT, headers=student).json()["items"] == []
    assert c.get(ROOT + "/" + document["id"], headers=student).status_code == 403
    scope = post(
        c,
        root,
        "scopes",
        {
            "user_id": student_response.json()["user"]["id"],
            "institution_id": inst["id"],
            "reason": "합성 허용 범위",
        },
    )
    assert c.get(ROOT + "/" + document["id"], headers=student).status_code == 200
    post(
        c,
        root,
        "scopes/" + scope["id"] + "/revoke",
        {"expected_version": scope["version"], "reason": "합성 회수"},
        expected=200,
    )
    assert (
        c.put(
            ROOT + "/" + document["id"] + "/pages/1",
            headers=student,
            json={"expected_version": 1, "parts": [{"content": "합성"}]},
        ).status_code
        == 403
    )
    search(c, {}, context(inst, dep), expected=401)


@integration
def test_new_applied_metadata_hides_old_index_without_falling_back_to_old_approval(
    auth_client, auth_db
):
    c, h = auth_client, operator(auth_client, auth_db)
    inst = school(c, h)
    dep = department(c, h, inst)
    source = applied_document(c, h, inst, dep)
    document = create(c, h, source)
    replace(c, h, document)
    approve(c, h, document)
    student = authorization(register(c))
    scope = context(inst, dep)
    assert search(c, student, scope)["status"] == "evidence_found"
    draft = post(
        c, h, "documents/" + source["id"] + "/drafts", {"expected_version": source["version"]}
    )
    post(
        c,
        h,
        "documents/" + draft["id"] + "/apply",
        {"expected_version": draft["version"]},
        expected=200,
    )
    assert search(c, student, scope)["status"] == "insufficient_evidence"
    other_dep = department(c, h, inst, code="OTHER")
    assert search(c, student, context(inst, other_dep))["status"] == "insufficient_evidence"
    assert (
        search(c, student, context(inst, {"id": str(uuid4())}), expected=404)["error"]["code"]
        == "NOT_FOUND"
    )


@integration
def test_revocation_during_generation_discards_answer_and_citations(auth_client, auth_db):
    c, h = auth_client, operator(auth_client, auth_db)
    inst = school(c, h)
    dep = department(c, h, inst)
    document = create(c, h, applied_document(c, h, inst, dep))
    replace(c, h, document)
    approve(c, h, document)
    student = authorization(register(c))

    class RevokingGenerator(SyntheticGenerator):
        def generate(self, request):
            with auth_db() as db:
                row = db.get(KnowledgeDocument, document["id"])
                row.status, row.revoked_by, row.revoked_at = (
                    "revoked",
                    row.approved_by,
                    datetime.now(UTC),
                )
                row.revocation_reason, row.version = "합성 진행 중 회수", row.version + 1
                db.commit()
            return super().generate(request)

    generator = RevokingGenerator()
    c.app.state.knowledge_index_cache.generator = generator
    response = search(c, student, context(inst, dep), endpoint="school-queries")
    assert len(generator.calls) == 1
    assert response["status"] == "insufficient_evidence"
    assert response["answer"] is None and response["citations"] == []
    assert not c.app.state.knowledge_index_cache._indexes


@integration
def test_scope_dates_index_reuse_and_safe_capacity_failure(auth_client, auth_db):
    c, h = auth_client, operator(auth_client, auth_db)
    inst = school(c, h)
    dep = department(c, h, inst)
    curriculum = post(
        c,
        h,
        "curricula",
        {
            "name": "합성 과정",
            "institution_id": inst["id"],
            "department_id": dep["id"],
            "year": 2026,
        },
    )
    today = datetime.now(UTC).date()
    scoped = create(c, h, applied_document(c, h, inst, dep, curriculum))
    replace(c, h, scoped)
    approve(c, h, scoped)
    expired = create(
        c,
        h,
        applied_document(c, h, inst, dep, effective_to=(today - timedelta(days=1)).isoformat()),
    )
    replace(c, h, expired)
    approve(c, h, expired)
    future = create(
        c,
        h,
        applied_document(c, h, inst, dep, effective_from=(today + timedelta(days=1)).isoformat()),
    )
    replace(c, h, future)
    approve(c, h, future)
    student = authorization(register(c))
    assert search(c, student, context(inst, dep))["status"] == "insufficient_evidence"
    selected = context(inst, dep, curriculum)
    from app.services import knowledge_queries

    original = knowledge_queries.build_index
    with patch.object(knowledge_queries, "build_index", wraps=original) as build:
        for _ in range(2):
            found = search(c, student, selected)
            assert found["status"] == "evidence_found"
            assert {s["document_id"] for s in found["sources"]} == {scoped["source_document_id"]}
        assert build.call_count == 1
    with patch.object(knowledge_queries, "MAX_DOCUMENTS", 0):
        failed = search(c, student, selected)
        assert failed["status"] == "failed" and failed["sources"] == []
    cache = c.app.state.knowledge_index_cache
    cache._indexes.clear()
    with patch.object(knowledge_queries, "MAX_CHARACTERS", 1):
        failed = search(c, student, selected)
        assert failed["reason"] == "rag_processing_failed" and failed["sources"] == []


@integration
def test_reviewed_blank_page_covers_source_without_inventing_citable_text(auth_client, auth_db):
    c, h = auth_client, operator(auth_client, auth_db)
    inst = school(c, h)
    dep = department(c, h, inst)
    document = create(c, h, applied_document(c, h, inst, dep), page_count=2)
    replace(c, h, document)
    approve(c, h, document, expected=422)
    response = c.put(
        ROOT + "/" + document["id"] + "/pages/2",
        headers=h,
        json={"expected_version": document["version"], "is_blank": True, "parts": []},
    )
    assert response.status_code == 200, response.text
    assert response.json()["is_blank"] is True and response.json()["parts"] == []
    document["version"] = response.json()["version"]
    approve(c, h, document)
    student = authorization(register(c))
    generator = SyntheticGenerator()
    c.app.state.knowledge_index_cache.generator = generator
    result = search(c, student, context(inst, dep), endpoint="school-queries")
    assert result["status"] == "grounded"
    assert len(generator.calls[0].evidence) == 1
    assert all(source["page"] == 1 for source in result["citations"])
    pages = c.get(ROOT + "/" + document["id"] + "/pages", headers=h).json()["items"]
    assert pages[1]["is_blank"] is True and pages[1]["part_count"] == 0
