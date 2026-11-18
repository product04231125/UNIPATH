"""Failures carry a fixed reason code so operators can tell them apart without any content."""

import json
import logging
from unittest.mock import Mock
from urllib.error import HTTPError, URLError

import pytest

from app.rag.career import transport as transport_module
from app.rag.career import vertex as vertex_module
from app.rag.career.analyzer import EvidenceAnalyzer
from app.rag.career.contracts import (
    AnalysisRejected,
    ProviderFailure,
    SearchQuery,
    failure_reason,
)
from app.rag.career.service import CareerService
from app.rag.career.transport import Transport
from app.rag.career.vertex import VertexJSON
from app.rag.tests.test_career import CONTEXT, POSTING
from app.services import gemini

SECRET = "개인 기록 본문 secret@example.test"


def test_reason_codes_never_depend_on_messages():
    assert failure_reason(ProviderFailure("x", "http_429")) == "http_429"
    assert failure_reason(AnalysisRejected(SECRET, "posting_quote")) == "posting_quote"
    assert failure_reason(KeyError("posting_quote")) == "output_shape"
    assert failure_reason(ValueError(SECRET)) == "output_shape"
    assert failure_reason(OSError(SECRET)) == "unexpected_OSError"
    # Existing callers still catch the same base types.
    assert isinstance(ProviderFailure("x", "y"), RuntimeError)
    assert isinstance(AnalysisRejected("x", "y"), ValueError)


@pytest.mark.parametrize(
    ("raised", "reason"),
    [
        (HTTPError("https://provider.invalid/?key=secret", 404, "nf", {}, None), "http_404"),
        (TimeoutError(), "timeout"),
        (URLError(TimeoutError()), "timeout"),
        (URLError("refused"), "network"),
        (OSError("boom"), "request_failed"),
    ],
)
def test_transport_keeps_only_the_status_or_failure_kind(monkeypatch, raised, reason):
    opener = Mock()
    opener.open.side_effect = raised
    monkeypatch.setattr(transport_module, "build_opener", lambda *args: opener)
    with pytest.raises(ProviderFailure) as caught:
        Transport(allow_network=True).request("https://provider.invalid/?key=secret")
    assert caught.value.reason == reason
    assert "secret" not in str(caught.value)


class Reply:
    def __init__(self, value=None, error=None):
        self.value, self.error = value, error

    def request(self, url, *, headers=None, body=None):
        if self.error:
            raise self.error
        return json.dumps(self.value).encode()


def vertex(reply, sleeps=None):
    return VertexJSON(
        "project",
        "asia-northeast1",
        "model",
        token_provider=lambda: "t",
        transport=reply,
        sleep=(sleeps if sleeps is not None else []).append,
    )


def candidate(text, finish="STOP"):
    return {"candidates": [{"finishReason": finish, "content": {"parts": [{"text": text}]}}]}


@pytest.mark.parametrize(
    ("reply", "reason"),
    [
        (Reply(error=ProviderFailure("x", "http_429")), "model_http_429"),
        (Reply(error=ProviderFailure("x", "timeout")), "model_timeout"),
        (Reply({"candidates": []}), "model_no_candidate"),
        (Reply(candidate("{}", "MAX_TOKENS")), "model_incomplete_max_tokens"),
        (Reply(candidate("{}", "weird value!")), "model_incomplete_other"),
        (Reply(candidate("not json")), "model_invalid_json"),
        (Reply(candidate("[1]")), "model_invalid_json"),
    ],
)
def test_vertex_failures_say_which_step_failed(reply, reason):
    with pytest.raises(ProviderFailure) as caught:
        vertex(reply).generate("instruction", {"records": [SECRET]})
    assert caught.value.reason == reason
    assert str(caught.value) == "Model response unavailable or invalid"


def test_recommendation_items_and_logs_carry_only_the_code(caplog):
    source = Mock()
    source.name = "saramin"
    source.search.return_value = [POSTING]
    model = Mock()
    model.generate.return_value = {
        "comparisons": [
            {
                "priority": "required",
                "requirement": "요건",
                "posting_quote": SECRET,
                "status": "insufficient_evidence",
                "personal_evidence": [],
                "explanation": SECRET,
            }
        ]
    }
    failing = Mock()
    failing.name = "work24"
    failing.search.side_effect = ProviderFailure("x", "http_503")
    service = CareerService([source, failing], EvidenceAnalyzer(model))
    query = SearchQuery("개발", "전국", nationwide=True)
    with caplog.at_level(logging.WARNING):
        result = service.recommend(query, CONTEXT, allow_personal_analysis=True)
    item = result["items"][0]
    assert item["analysis_status"] == "failed" and item["failure_reason"] == "posting_quote"
    work24 = next(s for s in result["sources"] if s["source"] == "work24")
    assert work24["reason"] == "source_failed" and work24["failure_reason"] == "http_503"
    assert "reason=posting_quote" in caplog.text and "http_503" in caplog.text
    assert SECRET not in caplog.text


def test_service_failure_log_names_the_reason(caplog):
    with caplog.at_level(logging.WARNING):
        gemini.log_failure("job analysis", AnalysisRejected(SECRET, "personal_citation"))
    assert "job analysis failed: AnalysisRejected reason=personal_citation" in caplog.text
    assert SECRET not in caplog.text


class Replies:
    """Answers each request with the next outcome: an exception or a JSON reply."""

    def __init__(self, *outcomes):
        self.outcomes, self.calls = list(outcomes), 0

    def request(self, url, *, headers=None, body=None):
        self.calls += 1
        outcome = self.outcomes.pop(0)
        if isinstance(outcome, Exception):
            raise outcome
        return json.dumps(outcome).encode()


def throttled():
    return ProviderFailure("x", "http_429")


def test_a_quick_429_is_retried_once_after_a_short_wait(caplog):
    replies, sleeps = Replies(throttled(), candidate('{"comparisons": []}')), []
    with caplog.at_level(logging.WARNING):
        assert vertex(replies, sleeps).generate("instruction", {"records": [SECRET]}) == {
            "comparisons": []
        }
    assert replies.calls == 2 and len(sleeps) == 1 and 1.0 <= sleeps[0] <= 2.0
    assert "Vertex call throttled (http_429); retrying once" in caplog.text
    assert SECRET not in caplog.text


def test_a_second_429_is_reported_without_more_retries():
    replies, sleeps = Replies(throttled(), throttled(), candidate("{}")), []
    with pytest.raises(ProviderFailure) as caught:
        vertex(replies, sleeps).generate("instruction", {})
    assert caught.value.reason == "model_http_429"
    assert replies.calls == 2 and len(sleeps) == 1


def test_other_failures_are_not_retried():
    for error in (ProviderFailure("x", "http_503"), ProviderFailure("x", "timeout")):
        replies, sleeps = Replies(error, candidate("{}")), []
        with pytest.raises(ProviderFailure):
            vertex(replies, sleeps).generate("instruction", {})
        assert replies.calls == 1 and sleeps == []


def test_a_slow_429_is_not_retried(monkeypatch):
    clock = iter([0.0, vertex_module.RETRY_WINDOW_SECONDS + 1])
    monkeypatch.setattr(vertex_module.time, "monotonic", lambda: next(clock))
    replies, sleeps = Replies(throttled(), candidate("{}")), []
    with pytest.raises(ProviderFailure) as caught:
        vertex(replies, sleeps).generate("instruction", {})
    assert caught.value.reason == "model_http_429"
    assert replies.calls == 1 and sleeps == []
