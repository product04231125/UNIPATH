from datetime import UTC, datetime
from uuid import uuid4

import pytest
from pydantic import ValidationError
from test_academic import department, operator, school
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register
from test_knowledge import applied_document, approve, context, create, replace
from test_personal import post

from app.models.knowledge import KnowledgeDocument
from app.schemas.personalized_guidance import (
    PersonalizedGuidanceRequest,
    PersonalizedGuidanceResponse,
)

PATH = "/api/v1/me/personalized-guidance"
integration = pytest.mark.integration
QUESTION = "사회봉사 승인 조건은?"


def world(c, db):
    h = operator(c, db)
    inst = school(c, h)
    dep = department(c, h, inst)
    document = create(c, h, applied_document(c, h, inst, dep))
    replace(c, h, document)
    approve(c, h, document)
    student = register(c, "personalized@example.test")
    owner = authorization(student)
    record = post(
        c,
        owner,
        "activity-records",
        {
            "title": "합성 교내 봉사",
            "detail": "도서관 정리 봉사 12시간, 010-1234-5678",
            "reported_hours": "12",
        },
    )
    return owner, student, context(inst, dep), document, record


def body(scope, record, **extra):
    return {
        "question": QUESTION,
        "context": scope,
        "records": [
            {"kind": "activity", "record_id": record["id"], "expected_version": record["version"]}
        ],
        "external_processing_consent": True,
        **extra,
    }


class SyntheticModel:
    def __init__(self, build=None):
        self.calls = []
        self.build = build

    def generate(self, instruction, payload):
        self.calls.append((instruction, payload))
        if self.build:
            return self.build(payload)
        record = payload["personal_records"][0]
        return {
            "answer": "학교 기준은 10시간이며, 내 기록 기준 12시간을 입력했습니다.",
            "school_chunk_ids": [payload["school_evidence"][0]["chunk_id"]],
            "personal_evidence": [
                {
                    "kind": record["kind"],
                    "record_id": record["record_id"],
                    "version": record["version"],
                    "excerpt": "도서관 정리 봉사 12시간",
                }
            ],
            "insufficient_evidence": False,
        }


def test_request_rejects_unknown_fields_and_consent_coercion():
    reference = {"kind": "activity", "record_id": str(uuid4()), "expected_version": 1}
    base = {
        "question": QUESTION,
        "context": {"institution_id": str(uuid4()), "department_id": str(uuid4())},
    }
    PersonalizedGuidanceRequest.model_validate(base)
    for change in (
        {"owner_id": str(uuid4())},
        {"external_processing_consent": "yes"},
        {"records": [reference, reference]},
    ):
        with pytest.raises(ValidationError):
            PersonalizedGuidanceRequest.model_validate({**base, **change})


def test_only_grounded_responses_can_contain_answers():
    with pytest.raises(ValidationError):
        PersonalizedGuidanceResponse.model_validate(
            {
                "query_id": str(uuid4()),
                "status": "evidence_only",
                "reason": "generator_not_configured",
                "answer": "추측한 답변",
                "school": {
                    "query_id": str(uuid4()),
                    "status": "insufficient_evidence",
                    "reason": "no_approved_matching_evidence",
                },
                "personal": {"records": []},
            }
        )


@integration
def test_school_and_personal_material_stay_separate_without_a_model(auth_client, auth_db):
    c = auth_client
    owner, _, scope, _, record = world(c, auth_db)
    assert c.post(PATH, json=body(scope, record)).status_code == 401
    response = c.post(PATH, headers=owner, json=body(scope, record))
    assert response.status_code == 200, response.text
    assert response.headers["Cache-Control"] == "no-store"
    value = response.json()
    assert (value["status"], value["reason"]) == ("evidence_only", "generator_not_configured")
    assert value["official"] is False and value["answer"] is None
    assert value["school"]["status"] == "evidence_found"
    assert value["school"]["sources"][0]["applicability"]["admission_years"] == [2026]
    assert "도서관" not in str(value["school"])
    personal = value["personal"]["records"][0]
    assert (personal["origin"], personal["official"]) == ("personal", False)
    assert "010-1234-5678" not in personal["text"] and "[연락처]" in personal["text"]
    empty = c.post(PATH, headers=owner, json={**body(scope, record), "records": []}).json()
    assert (empty["status"], empty["missing_fields"]) == ("needs_user_input", ["records"])
    assert empty["school"]["status"] == "evidence_found"


@integration
def test_generation_needs_consent_and_cites_each_side_separately(auth_client, auth_db):
    c = auth_client
    owner, _, scope, _, record = world(c, auth_db)
    model = SyntheticModel()
    c.app.state.guidance_model = model
    denied = c.post(
        PATH, headers=owner, json=body(scope, record, external_processing_consent=False)
    ).json()
    assert denied["reason"] == "external_processing_consent_required"
    assert denied["missing_fields"] == ["external_processing_consent"]
    assert model.calls == []
    value = c.post(PATH, headers=owner, json=body(scope, record)).json()
    assert (value["status"], value["official"]) == ("grounded", False)
    assert value["school_chunk_ids"] == [value["school"]["sources"][0]["chunk_id"]]
    assert value["personal_citations"][0]["record_id"] == record["id"]
    instruction, payload = model.calls[0]
    assert "Rule Engine" in instruction
    assert set(payload) == {"question", "school_evidence", "personal_records"}
    assert "010-1234-5678" not in str(payload)
    assert "owner" not in str(payload)


@integration
@pytest.mark.parametrize("case", ["chunk", "excerpt", "shape", "failure"])
def test_invalid_generation_never_reaches_the_student(auth_client, auth_db, case):
    c = auth_client
    owner, _, scope, _, record = world(c, auth_db)

    def build(payload):
        value = SyntheticModel().generate("", payload)
        if case == "chunk":
            value["school_chunk_ids"] = [str(uuid4())]
        if case == "excerpt":
            value["personal_evidence"][0]["excerpt"] = "선택 기록에 없는 문장"
        if case == "shape":
            value["extra"] = True
        if case == "failure":
            raise RuntimeError("provider detail must stay private")
        return value

    c.app.state.guidance_model = SyntheticModel(build)
    value = c.post(PATH, headers=owner, json=body(scope, record)).json()
    assert (value["status"], value["reason"]) == ("failed", "generation_failed")
    assert value["answer"] is None and value["personal_citations"] == []
    assert "provider detail" not in str(value)


@integration
def test_model_reported_gaps_and_unavailable_school_evidence_stop_generation(auth_client, auth_db):
    c = auth_client
    owner, _, scope, document, record = world(c, auth_db)
    empty = {
        "answer": "",
        "school_chunk_ids": [],
        "personal_evidence": [],
        "insufficient_evidence": True,
    }
    c.app.state.guidance_model = SyntheticModel(lambda payload: empty)
    value = c.post(PATH, headers=owner, json=body(scope, record)).json()
    assert value["reason"] == "generator_reported_insufficient_evidence"
    model = SyntheticModel()
    c.app.state.guidance_model = model
    judged = c.post(
        PATH, headers=owner, json=body(scope, record, question="저 졸업 가능한가요?")
    ).json()
    assert (judged["status"], judged["reason"]) == (
        "needs_user_input",
        "school_evidence_unavailable",
    )
    assert judged["school"]["reason"] == "rule_engine_required"
    assert model.calls == []


@integration
def test_revocation_or_record_change_during_generation_discards_the_answer(auth_client, auth_db):
    c = auth_client
    owner, _, scope, document, record = world(c, auth_db)

    def revoke(payload):
        with auth_db() as db:
            row = db.get(KnowledgeDocument, document["id"])
            row.status, row.revoked_by, row.revoked_at = (
                "revoked",
                row.approved_by,
                datetime.now(UTC),
            )
            row.revocation_reason, row.version = "합성 진행 중 회수", row.version + 1
            db.commit()
        return SyntheticModel().generate("", payload)

    c.app.state.guidance_model = SyntheticModel(revoke)
    value = c.post(PATH, headers=owner, json=body(scope, record)).json()
    assert (value["status"], value["answer"]) == ("insufficient_evidence", None)
    assert value["personal_citations"] == []


@integration
def test_other_students_cannot_select_records_and_changes_invalidate_versions(auth_client, auth_db):
    c = auth_client
    owner, _, scope, _, record = world(c, auth_db)
    other = authorization(register(c, "personalized-other@example.test"))
    assert c.post(PATH, headers=other, json=body(scope, record)).status_code == 404
    stale = body(scope, record)
    stale["records"][0]["expected_version"] += 1
    assert c.post(PATH, headers=owner, json=stale).status_code == 409
