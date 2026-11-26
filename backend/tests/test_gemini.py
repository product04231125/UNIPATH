"""Provider adapters with a synthetic transport; no network or credential is used."""

import json
from threading import Event, Thread
from types import SimpleNamespace
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.core.config import Settings
from app.rag.career.analyzer import EvidenceAnalyzer
from app.rag.career.transport import Transport
from app.rag.career.vertex import VertexJSON
from app.rag.school.contracts import GroundingRequest
from app.rag.school.providers import InvalidGeneratorOutput, ProviderError
from app.schemas.personalization import PersonalEvidence, PersonalizationContext
from app.services import gemini
from app.services.job_analysis.service import validate_comparisons
from app.services.personalization.redaction import redact_context, redact_text


def settings(**values):
    return Settings(_env_file=None, postgres_password="synthetic-test-password", **values)


CONFIGURED = {
    "vertex_project": "synthetic-project",
    "vertex_location": "asia-northeast3",
    "vertex_model": "synthetic-gemini-model",
}


class FakeTransport(Transport):
    def __init__(self, reply):
        super().__init__(allow_network=True)
        self.reply = reply
        self.bodies = []

    def request(self, url, *, headers=None, body=None):
        self.bodies.append(json.loads(body))
        self.url, self.headers = url, headers
        return json.dumps(
            {
                "candidates": [
                    {
                        "finishReason": "STOP",
                        "content": {"parts": [{"text": json.dumps(self.reply)}]},
                    }
                ]
            }
        ).encode()


def vertex(reply):
    transport = FakeTransport(reply)
    return VertexJSON(
        "synthetic-project",
        "asia-northeast3",
        "synthetic-gemini-model",
        token_provider=lambda: "synthetic-token",
        transport=transport,
    ), transport


def test_gemini_is_off_until_every_identifier_is_set():
    assert settings().vertex_configured is False
    assert gemini.create_model(settings(), timeout=15) is None
    assert gemini.create_answer_generator(settings()) is None
    assert gemini.create_job_analyzer(None) is None
    blank = settings(vertex_project="", vertex_location="", vertex_model="")
    assert blank.vertex_configured is False
    for name in CONFIGURED:
        partial = {key: value for key, value in CONFIGURED.items() if key != name}
        with pytest.raises(ValidationError):
            settings(**partial)
    assert settings(**CONFIGURED).vertex_configured is True


def test_configuring_gemini_never_requests_a_token_during_startup():
    model = gemini.create_model(settings(**CONFIGURED), timeout=15)
    assert isinstance(gemini.create_job_analyzer(model), EvidenceAnalyzer)
    assert isinstance(gemini.create_answer_generator(settings(**CONFIGURED)).model, type(model))


@pytest.mark.parametrize(
    "text,expected",
    [
        ("메일 a.b+c@example.test 로", "메일 [이메일] 로"),
        ("문의 010-1234-5678", "문의 [연락처]"),
        ("문의 01012345678.", "문의 [연락처]."),
        ("+82 10 1234 5678", "[연락처]"),
        ("사무실 02-123-4567", "사무실 [연락처]"),
        ("번호 900101-1234567", "번호 [주민등록번호]"),
        ("학번: 20261234 입니다", "학번: [학번] 입니다"),
        ("Student ID A2026-1", "Student ID [학번]"),
        ("https://github.com/someone/repo 참고", "[링크] 참고"),
    ],
)
def test_direct_identifiers_are_redacted(text, expected):
    assert redact_text(text) == expected


@pytest.mark.parametrize(
    "text",
    [
        "2026년 3학년 평균 4.5",
        "학점 130, 봉사 40시간",
        "CS101 자료구조 3학점",
        "2024-03-02 ~ 2024-06-30",
        "인원 1234명, 예산 5000000원",
    ],
)
def test_ordinary_academic_numbers_are_kept(text):
    assert redact_text(text) == text


def test_redaction_handles_names_and_length_limits():
    assert redact_text("홍길동 팀장 홍길동", names=("홍길동",)) == "[이름] 팀장 [이름]"
    assert redact_text("김 교수님", names=("김",)) == "김 교수님"
    identity = SimpleNamespace(user=SimpleNamespace(display_name="가나"))
    record = PersonalEvidence(
        kind="experience",
        record_id=uuid4(),
        version=1,
        title="가나 프로젝트",
        text="가나" * 4000,
        truncated=False,
    )
    context = redact_context(PersonalizationContext(records=[record]), identity)
    assert context.records[0].title == "[이름] 프로젝트"
    assert len(context.records[0].text) == 8000 and context.records[0].truncated is True


def test_school_generator_redacts_questions_and_rejects_invalid_shapes():
    chunk = str(uuid4())
    model, transport = vertex(
        {"answer": "합성 답변", "citation_ids": [chunk], "insufficient_evidence": False}
    )
    generator = gemini.GeminiAnswerGenerator(gemini.BoundedModel(model))
    answer = generator.generate(
        GroundingRequest(
            "지시", "010-1234-5678 학생의 봉사 조건", [{"chunk_id": chunk, "content": "근거"}], {}
        )
    )
    assert answer.answer == "합성 답변" and answer.citation_ids == [chunk]
    sent = transport.bodies[0]["contents"][0]["parts"][0]["text"]
    assert "010-1234-5678" not in sent and "[연락처]" in sent
    assert transport.url.startswith("https://asia-northeast3-aiplatform.googleapis.com/")
    invalid = gemini.GeminiAnswerGenerator(vertex({"answer": "근거 없음"})[0])
    with pytest.raises(InvalidGeneratorOutput):
        invalid.generate(GroundingRequest("지시", "질문", [], {}))
    with pytest.raises(ProviderError):
        generator.generate(GroundingRequest("지시", "질문", [{"content": "x" * 48_001}], {}))


def test_representative_comparison_passes_analyzer_and_service_checks():
    record_id = uuid4()
    posting = "[필수] Python 백엔드 개발 경험\n[우대] 정보처리기사 자격증"
    context = PersonalizationContext(
        records=[
            PersonalEvidence(
                kind="experience",
                record_id=record_id,
                version=2,
                title="합성 프로젝트",
                text="result: FastAPI로 수강 API를 구현",
                truncated=False,
            )
        ]
    )
    model, transport = vertex(
        {
            "comparisons": [
                {
                    "priority": "required",
                    "requirement": "Python 백엔드 개발 경험",
                    "posting_quote": "Python 백엔드 개발 경험",
                    "status": "partially_supported",
                    "personal_evidence": [
                        {
                            "kind": "experience",
                            "record_id": str(record_id),
                            "version": 2,
                            "excerpt": "FastAPI로 수강 API를 구현",
                        }
                    ],
                    "explanation": "선택한 기록에 관련 구현 경험이 있습니다.",
                },
                {
                    "priority": "preferred",
                    "requirement": "정보처리기사",
                    "posting_quote": "정보처리기사 자격증",
                    "status": "insufficient_evidence",
                    "personal_evidence": [],
                    "explanation": "선택한 기록에서 확인되지 않습니다.",
                },
            ]
        }
    )
    values = gemini.create_job_analyzer(gemini.BoundedModel(model)).analyze(posting, context)
    comparisons = validate_comparisons(posting, context, values)
    assert [item.status for item in comparisons] == ["partially_supported", "insufficient_evidence"]
    assert posting[comparisons[1].posting_evidence.start :].startswith("정보처리기사")
    request = transport.bodies[0]
    assert request["generationConfig"]["responseMimeType"] == "application/json"
    assert "owner" not in json.dumps(request)


@pytest.mark.parametrize(
    "reply",
    [
        {"comparisons": [{"priority": "required"}]},
        {"wrong": []},
        {
            "comparisons": [
                {
                    "priority": "required",
                    "requirement": "x",
                    "posting_quote": "공고에 없는 문장",
                    "status": "insufficient_evidence",
                    "personal_evidence": [],
                    "explanation": "x",
                }
            ]
        },
    ],
)
def test_invalid_model_output_is_rejected_before_it_reaches_a_response(reply):
    context = PersonalizationContext(
        records=[
            PersonalEvidence(
                kind="experience",
                record_id=uuid4(),
                version=1,
                title="합성",
                text="합성 기록",
                truncated=False,
            )
        ]
    )
    with pytest.raises((KeyError, TypeError, ValueError)):
        EvidenceAnalyzer(vertex(reply)[0]).analyze("합성 공고", context)


def test_busy_model_fails_fast_instead_of_consuming_every_worker():
    entered, release = Event(), Event()

    class Slow:
        def generate(self, instruction, payload):
            entered.set()
            release.wait(5)
            return {}

    bounded = gemini.BoundedModel(Slow(), slots=1, wait_seconds=0.01)
    worker = Thread(target=bounded.generate, args=("지시", {}))
    worker.start()
    entered.wait(5)
    with pytest.raises(RuntimeError):
        bounded.generate("지시", {})
    release.set()
    worker.join()
    assert bounded.generate("지시", {}) == {}
