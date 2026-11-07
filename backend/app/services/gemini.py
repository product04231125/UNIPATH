"""Vertex Gemini wiring. Nothing is called unless every setting and credential is present."""

import json
import logging
from threading import BoundedSemaphore, Lock

from app.core.config import Settings
from app.rag.career.analyzer import EvidenceAnalyzer
from app.rag.career.transport import Transport
from app.rag.career.vertex import VertexJSON
from app.rag.school.contracts import GeneratedAnswer, GroundingRequest
from app.rag.school.providers import ProviderError, parse_answer
from app.services import auth
from app.services.personalization.redaction import redact_text

logger = logging.getLogger(__name__)
SCHOOL_TIMEOUT_SECONDS = 15
ANSWER_RULES = """
출력은 answer, citation_ids, insufficient_evidence 키만 가진 JSON 객체다.
근거가 부족하면 answer는 빈 문자열, citation_ids는 빈 배열, insufficient_evidence는 true다."""


class CachedAdcToken:
    """Reuse Application Default Credentials until the access token expires."""

    def __init__(self):
        self._lock = Lock()
        self._credentials = None

    def __call__(self) -> str:
        # Optional at import time so an unconfigured application never touches Google auth.
        import google.auth
        from google.auth.transport.requests import Request

        with self._lock:
            if self._credentials is None:
                self._credentials, _ = google.auth.default(
                    scopes=["https://www.googleapis.com/auth/cloud-platform"]
                )
            if not self._credentials.valid:
                self._credentials.refresh(Request())
            return self._credentials.token


class BoundedModel:
    """Keep slow provider calls from occupying the API's worker threads."""

    def __init__(self, model, *, slots: int = 3, wait_seconds: float = 5):
        self._model = model
        self._slots = BoundedSemaphore(slots)
        self._wait = wait_seconds

    def generate(self, instruction: str, payload: dict) -> dict:
        if not self._slots.acquire(timeout=self._wait):
            raise RuntimeError("Model capacity is busy")
        try:
            return self._model.generate(instruction, payload)
        finally:
            self._slots.release()


class GeminiAnswerGenerator:
    """Adapt the structured model to the school RAG generator boundary."""

    def __init__(self, model):
        self.model = model

    def generate(self, request: GroundingRequest) -> GeneratedAnswer:
        payload = {
            "question": redact_text(request.question),
            "context": request.context,
            "evidence": request.evidence,
        }
        if len(json.dumps(payload, ensure_ascii=False)) > 48_000:
            raise ProviderError("Evidence exceeds the configured budget; it was not truncated")
        data = self.model.generate(request.system_instruction + ANSWER_RULES, payload)
        return parse_answer(json.dumps(data, ensure_ascii=False))


def create_model(config: Settings, *, timeout: int) -> BoundedModel | None:
    if not config.vertex_configured:
        return None
    return BoundedModel(
        VertexJSON(
            config.vertex_project,
            config.vertex_location,
            config.vertex_model,
            token_provider=CachedAdcToken(),
            transport=Transport(allow_network=True, timeout=timeout),
        )
    )


def create_job_analyzer(model) -> EvidenceAnalyzer | None:
    return EvidenceAnalyzer(model) if model is not None else None


def create_answer_generator(config: Settings) -> GeminiAnswerGenerator | None:
    model = create_model(config, timeout=min(SCHOOL_TIMEOUT_SECONDS, config.vertex_timeout_seconds))
    return GeminiAnswerGenerator(model) if model is not None else None


def reserve_call(db, request) -> None:
    """Shared ceiling for paid calls; the monthly budget belongs in the cloud account."""
    limit = request.app.state.settings.llm_requests_per_15_minutes
    auth.throttle(db, "llm:global", limit=limit)


def log_failure(operation: str, error: Exception) -> None:
    # Only the type: provider errors could echo prompts, records or credentials.
    logger.warning("%s failed: %s", operation, type(error).__name__)
