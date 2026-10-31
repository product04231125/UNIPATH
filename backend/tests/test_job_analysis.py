from copy import deepcopy
from uuid import uuid4

import pytest
from pydantic import ValidationError
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register
from test_personal import post

from app.schemas.job_analysis import JobAnalysisRequest

ROOT = "/api/v1/me"
POSTING = "필수: Python 개발 경험\n우대: FastAPI 경험"


def selection(record):
    return {
        "kind": "experience",
        "record_id": record["id"],
        "expected_version": record["version"],
    }


def test_request_rejects_spoofed_ownership_and_invalid_selections():
    reference = {"kind": "experience", "record_id": str(uuid4()), "expected_version": 1}
    for change in (
        {"owner_id": str(uuid4())},
        {"posting_text": " "},
        {"posting_text": "x" * 20001},
        {"records": [reference, reference]},
        {"records": [{**reference, "expected_version": True}]},
        {"records": [{**reference, "kind": "official"}]},
        {"personal_profile": {"skills": ["Python"]}},
    ):
        with pytest.raises(ValidationError):
            JobAnalysisRequest.model_validate({"posting_text": POSTING, **change})


def setup(c):
    owner = authorization(register(c))
    record = post(
        c,
        owner,
        "experience-records",
        {
            "title": "합성 Python 프로젝트",
            "experience_type": "프로젝트",
            "role": "개발",
            "result": "Python으로 API 구현",
        },
    )
    return owner, record, {"posting_text": POSTING, "records": [selection(record)]}


class SyntheticAnalyzer:
    def __init__(self, mutate=lambda values: values):
        self.calls = []
        self.mutate = mutate

    def analyze(self, posting, context):
        self.calls.append(context)
        record = context.records[0]
        python_start = posting.index("Python")
        python_end = python_start + len("Python 개발 경험")
        fastapi_start = posting.index("FastAPI")
        values = [
            {
                "requirement_id": str(uuid4()),
                "priority": "required",
                "requirement": "Python 개발 경험",
                "posting_evidence": {
                    "start": python_start,
                    "end": python_end,
                    "excerpt": posting[python_start:python_end],
                },
                "status": "supported",
                "personal_evidence": [
                    {
                        "kind": record.kind,
                        "record_id": str(record.record_id),
                        "version": record.version,
                        "excerpt": "Python으로 API 구현",
                    }
                ],
                "explanation": "선택한 개인 기록에 Python API 구현 경험이 기재되어 있습니다.",
            },
            {
                "requirement_id": str(uuid4()),
                "priority": "preferred",
                "requirement": "FastAPI 경험",
                "posting_evidence": {
                    "start": fastapi_start,
                    "end": len(posting),
                    "excerpt": posting[fastapi_start:],
                },
                "status": "insufficient_evidence",
                "personal_evidence": [],
                "explanation": "선택한 개인 기록으로는 FastAPI 경험을 확인할 수 없습니다.",
            },
        ]
        return self.mutate(values)


@pytest.mark.integration
def test_personal_context_is_explicit_owner_scoped_and_versioned(auth_client):
    c = auth_client
    owner, record, body = setup(c)
    result = c.post(
        ROOT + "/personalization-contexts", headers=owner, json={"records": body["records"]}
    )
    assert result.status_code == 200, result.text
    context = result.json()
    assert context["official"] is False
    assert len(context["records"]) == 1
    assert context["records"][0]["origin"] == "personal"
    assert context["records"][0]["official"] is False
    assert "owner_id" not in str(context) and "organization" not in str(context)
    assert result.headers["Cache-Control"] == "no-store"
    assert c.post(ROOT + "/job-analyses", json=body).status_code == 401
    other = authorization(register(c, "other@example.test"))
    for path in ("/personalization-contexts", "/job-analyses"):
        payload = body if path == "/job-analyses" else {"records": body["records"]}
        assert c.post(ROOT + path, headers=other, json=payload).status_code == 404
    stale = deepcopy(body)
    stale["records"][0]["expected_version"] += 1
    assert c.post(ROOT + "/job-analyses", headers=owner, json=stale).status_code == 409
    invalid = c.post(
        ROOT + "/job-analyses", headers=owner, json={**body, "owner_id": record["owner_id"]}
    )
    assert invalid.status_code == 422
    assert set(invalid.json()["error"]) == {"code", "message", "field_errors", "request_id"}


@pytest.mark.integration
def test_job_analysis_missing_inputs_unconfigured_and_synthetic_minimum_scenario(auth_client):
    c = auth_client
    owner, _, body = setup(c)
    missing = c.post(ROOT + "/job-analyses", headers=owner, json={"posting_text": POSTING})
    assert missing.json()["status"] == "needs_user_input"
    assert missing.json()["missing_fields"] == ["records"]
    unavailable = c.post(ROOT + "/job-analyses", headers=owner, json=body)
    assert unavailable.json()["status"] == "not_configured"
    assert unavailable.json()["comparisons"] == []
    analyzer = SyntheticAnalyzer()
    c.app.state.job_analyzer = analyzer
    result = c.post(ROOT + "/job-analyses", headers=owner, json=body)
    assert result.status_code == 200, result.text
    assert result.json()["status"] == "completed"
    assert [item["status"] for item in result.json()["comparisons"]] == [
        "supported",
        "insufficient_evidence",
    ]
    assert result.headers["Cache-Control"] == "no-store"
    assert len(analyzer.calls) == 1 and len(analyzer.calls[0].records) == 1
    c.app.state.job_analyzer = SyntheticAnalyzer(lambda values: [])
    assert (
        c.post(ROOT + "/job-analyses", headers=owner, json=body).json()["reason"]
        == "no_requirements_found"
    )


@pytest.mark.integration
@pytest.mark.parametrize(
    "case", ["posting", "record", "excerpt", "version", "duplicate", "missing"]
)
def test_untrusted_adapter_cannot_invent_evidence(auth_client, case):
    c = auth_client
    owner, _, body = setup(c)

    def corrupt(values):
        item = values[0]
        if case == "posting":
            item["posting_evidence"]["excerpt"] = "공고에 없는 문장"
        elif case == "record":
            item["personal_evidence"][0]["record_id"] = str(uuid4())
        elif case == "excerpt":
            item["personal_evidence"][0]["excerpt"] = "기록에 없는 경력"
        elif case == "version":
            item["personal_evidence"][0]["version"] += 1
        elif case == "duplicate":
            values.append(deepcopy(item))
        else:
            item["personal_evidence"] = []
        return values

    c.app.state.job_analyzer = SyntheticAnalyzer(corrupt)
    result = c.post(ROOT + "/job-analyses", headers=owner, json=body)
    assert result.status_code == 200
    assert result.json()["status"] == "failed"
    assert result.json()["comparisons"] == []
    assert "기록에 없는" not in result.text


@pytest.mark.integration
def test_personal_record_changes_during_analysis_invalidate_result(auth_client):
    c = auth_client
    owner, record, body = setup(c)

    def change(values):
        response = c.patch(
            ROOT + "/experience-records/" + record["id"],
            headers=owner,
            json={"expected_version": record["version"], "result": "변경된 합성 기록"},
        )
        assert response.status_code == 200
        return values

    c.app.state.job_analyzer = SyntheticAnalyzer(change)
    result = c.post(ROOT + "/job-analyses", headers=owner, json=body)
    assert result.status_code == 409
    assert "comparisons" not in result.json()
