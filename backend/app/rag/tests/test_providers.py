"""Provider wire contracts and failure behavior, with no external API calls."""

import ast
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from app.rag.school.budget import remaining_timeout, request_budget
from app.rag.school.contracts import GroundingRequest
from app.rag.school.embeddings import EmbeddingRanker
from app.rag.school.hybrid import HybridRanker
from app.rag.school.providers import (
    HttpAnswerGenerator,
    HttpEmbeddingProvider,
    HttpJsonTransport,
    InvalidGeneratorOutput,
    ProviderError,
    parse_answer,
)
from app.rag.school.retriever import SchoolRetriever
from app.rag.school.service import SchoolRagService
from app.rag.tests.test_school_rag import CONTEXT, RecordingGenerator, chunk


class FakeTransport:
    identity = "https://example.invalid/v1"

    def __init__(self, response):
        self.response = response
        self.calls = []

    def post(self, path, payload):
        self.calls.append((path, payload))
        return self.response


def completion(content=None, **choice_overrides):
    return {
        "choices": [
            {
                "finish_reason": "stop",
                "message": {
                    "content": content
                    or json.dumps(
                        {
                            "answer": "합성 답변",
                            "citation_ids": [chunk()["chunk_id"]],
                            "insufficient_evidence": False,
                        }
                    )
                },
                **choice_overrides,
            }
        ]
    }


class ProviderTests(unittest.TestCase):
    def test_deadline_is_shared_by_calls_and_reset_after_request(self):
        with patch("app.rag.school.budget.time.monotonic", return_value=100) as clock:
            with request_budget(15):
                self.assertEqual(remaining_timeout(12), 12)
                clock.return_value = 110
                self.assertEqual(remaining_timeout(12), 5)
                with request_budget(15):
                    self.assertEqual(remaining_timeout(12), 5)
                clock.return_value = 116
                with self.assertRaises(TimeoutError):
                    remaining_timeout(12)
            self.assertEqual(remaining_timeout(12), 12)

    def test_exhausted_request_budget_prevents_another_http_call(self):
        client = HttpJsonTransport("https://example.invalid", allow_network=True)
        with patch("http.client.HTTPSConnection") as connection, request_budget(-1):
            with self.assertRaises(ProviderError):
                client.post("/chat/completions", {})
            connection.assert_not_called()

    def test_structured_output_rejects_ambiguous_or_malformed_json(self):
        for payload in (
            "{}",
            "[]",
            "```json\n{}\n```",
            '{"answer":"a","answer":"b"}',
            '{"answer":NaN,"citation_ids":[],"insufficient_evidence":true}',
            json.dumps({"answer": "a", "citation_ids": [1], "insufficient_evidence": False}),
            json.dumps({"answer": "a", "citation_ids": [], "insufficient_evidence": "false"}),
            json.dumps({"answer": "a", "citation_ids": [], "insufficient_evidence": True}),
        ):
            with self.subTest(payload=payload), self.assertRaises(InvalidGeneratorOutput):
                parse_answer(payload)

    def test_abstention_is_explicit_empty_answer(self):
        result = parse_answer('{"answer":"","citation_ids":[],"insufficient_evidence":true}')
        self.assertTrue(result.insufficient_evidence)

    def test_commercial_wire_contract_and_public_service_contract(self):
        transport = FakeTransport(completion())
        generator = HttpAnswerGenerator(
            transport, dialect="openai-compatible", model="chosen-model"
        )
        result = SchoolRagService(SchoolRetriever([chunk()]), generator).query("사회봉사", CONTEXT)
        self.assertEqual(result.status, "grounded")
        path, payload = transport.calls[0]
        self.assertEqual(path, "/chat/completions")
        self.assertFalse(payload["stream"])
        self.assertFalse(payload["store"])
        self.assertTrue(payload["response_format"]["json_schema"]["strict"])
        self.assertEqual(payload["model"], "chosen-model")
        prompt = json.loads(payload["messages"][1]["content"])
        self.assertEqual(prompt["context"]["admission_year"], 2026)
        self.assertEqual(prompt["evidence"][0]["chunk_id"], chunk()["chunk_id"])
        self.assertNotIn("source_file", prompt["evidence"][0])
        self.assertEqual(result.citations[0]["source_url"], chunk()["source_url"])

    def test_ollama_uses_same_answer_contract_without_forcing_a_model(self):
        transport = FakeTransport(
            {"done": True, "done_reason": "stop", "message": completion()["choices"][0]["message"]}
        )
        generator = HttpAnswerGenerator(transport, dialect="ollama", model="local-choice")
        result = SchoolRagService(SchoolRetriever([chunk()]), generator).query("사회봉사", CONTEXT)
        self.assertEqual(result.status, "grounded")
        self.assertEqual(transport.calls[0][0], "/api/chat")
        self.assertEqual(transport.calls[0][1]["format"]["type"], "object")

    def test_truncation_refusal_bad_json_and_forged_citations_fail_closed(self):
        for response in (
            completion(finish_reason="length"),
            completion(content="{}"),
            completion(message={"refusal": "no"}),
            completion(
                content=json.dumps(
                    {"answer": "a", "citation_ids": ["invented"], "insufficient_evidence": False}
                )
            ),
        ):
            generator = HttpAnswerGenerator(
                FakeTransport(response), dialect="openai-compatible", model="chosen-model"
            )
            result = SchoolRagService(SchoolRetriever([chunk()]), generator).query(
                "사회봉사", CONTEXT
            )
            self.assertEqual(result.status, "failed")
            self.assertIsNone(result.answer)
            self.assertEqual(result.citations, [])
            self.assertIn(
                result.reason, ("invalid_generator_output", "invalid_generator_citations")
            )

    def test_draft_and_preview_never_call_chat_provider(self):
        transport = FakeTransport(completion())
        generator = HttpAnswerGenerator(transport, dialect="openai-compatible", model="chosen")
        service = SchoolRagService(
            SchoolRetriever([chunk(review_status="needs_review")]), generator
        )
        for preview in (False, True):
            service.query("사회봉사", CONTEXT, preview=preview)
        self.assertEqual(transport.calls, [])

    def test_evidence_budget_fails_without_silently_truncating_or_calling_provider(self):
        generator = RecordingGenerator()
        service = SchoolRagService(SchoolRetriever([chunk("사회봉사 " * 9000)]), generator)
        self.assertEqual(service.query("사회봉사", CONTEXT).reason, "rag_processing_failed")
        self.assertEqual(generator.requests, [])
        transport = FakeTransport(completion())
        provider = HttpAnswerGenerator(transport, dialect="openai-compatible", model="chosen")
        with self.assertRaises(ProviderError):
            provider.generate(GroundingRequest("", "a" * 49_000, [], {}))
        self.assertEqual(transport.calls, [])

    def test_network_is_disabled_by_default(self):
        transport = HttpJsonTransport("https://example.invalid/v1", api_key="secret")
        with patch("http.client.HTTPSConnection") as connection, self.assertRaises(ProviderError):
            transport.post("/chat/completions", {})
        connection.assert_not_called()

    def test_endpoint_validation(self):
        for url in (
            "http://external.example",
            "https://user:secret@host",
            "https://host?key=x",
            "https://host#secret",
            "file:///tmp/model",
            "https://",
        ):
            with self.assertRaises(ValueError):
                HttpJsonTransport(url)
        for url in ("http://127.0.0.1:11434", "http://[::1]:11434", "https://example.invalid/v1"):
            HttpJsonTransport(url)
        for timeout in (0, 16, float("nan"), True):
            with self.assertRaises(ValueError):
                HttpJsonTransport("https://example.invalid", timeout_seconds=timeout)

    def test_transport_builds_post_and_caps_response_and_hides_failures(self):
        transport = HttpJsonTransport(
            "https://example.invalid/v1", api_key="secret", allow_network=True
        )
        with patch("http.client.HTTPSConnection") as factory:
            connection = factory.return_value
            response = connection.getresponse.return_value
            response.status = 200
            response.read1.side_effect = [b'{"ok":true}', b""]
            self.assertEqual(transport.post("/chat/completions", {"model": "chosen"}), {"ok": True})
            request = connection.request.call_args.args
            self.assertEqual(request[:2], ("POST", "/v1/chat/completions"))
            self.assertEqual(request[3]["Authorization"], "Bearer secret")
            connection.close.assert_called()
            for status in (301, 429, 500):
                response.status = status
                with self.assertRaises(ProviderError) as error:
                    transport.post("/chat/completions", {})
                self.assertNotIn("secret", str(error.exception))
            response.status = 200
            response.read1.side_effect = [b"x" * 1_000_001]
            with self.assertRaises(ProviderError):
                transport.post("/chat/completions", {})
            connection.request.side_effect = TimeoutError("secret prompt or token")
            with self.assertRaises(ProviderError) as error:
                transport.post("/chat/completions", {})
            self.assertNotIn("secret", str(error.exception))

    def test_embedding_indices_are_sorted_validated_and_not_truncated(self):
        transport = FakeTransport(
            {"data": [{"index": 1, "embedding": [0, 1]}, {"index": 0, "embedding": [1, 0]}]}
        )
        provider = HttpEmbeddingProvider(transport, dialect="openai-compatible", model="chosen")
        self.assertEqual(provider.embed_documents(["a", "b"]), [[1.0, 0.0], [0.0, 1.0]])
        transport.response["data"][1]["index"] = 1
        with self.assertRaises(ProviderError):
            provider.embed_documents(["a", "b"])
        local = FakeTransport({"embeddings": [[1, 0]]})
        HttpEmbeddingProvider(local, dialect="ollama", model="chosen").embed_query("a")
        self.assertFalse(local.calls[0][1]["truncate"])

    def test_embedding_count_dimension_and_values_are_validated(self):
        for vectors in ([], [[0, 0]], [[float("nan"), 1]], [[True, 1]], ["wrong"]):
            provider = HttpEmbeddingProvider(
                FakeTransport({"embeddings": vectors}), dialect="ollama", model="chosen"
            )
            with self.assertRaises(ProviderError):
                provider.embed_query("a")

    def test_cache_reuses_document_embeddings_but_invalidates_for_content_or_model(self):
        provider = MagicMock(model_id="synthetic-v1")
        provider.embed_documents.return_value = [[1, 0]]
        provider.embed_query.return_value = [1, 0]
        with tempfile.TemporaryDirectory() as folder:
            cache = Path(folder) / "vectors.json"
            EmbeddingRanker([chunk()], provider, cache_path=cache)
            cached = EmbeddingRanker([chunk()], provider, cache_path=cache)
            self.assertEqual(provider.embed_documents.call_count, 1)
            self.assertEqual(cached.score("q", [0]), {0: 1.0})
            EmbeddingRanker([chunk("다른 내용")], provider, cache_path=cache)
            provider.model_id = "synthetic-v2"
            EmbeddingRanker([chunk("다른 내용")], provider, cache_path=cache)
            self.assertEqual(provider.embed_documents.call_count, 3)

    def test_hybrid_receives_only_eligible_indices_and_is_deterministic(self):
        lexical, dense = MagicMock(), MagicMock()
        lexical.score.return_value = {0: 3.0, 1: 100.0}
        dense.score.return_value = {0: 0.5, 1: 100.0}
        retriever = SchoolRetriever(
            [chunk(), chunk(doc="other", admission_years=[2019])], HybridRanker(lexical, dense)
        )
        hits = retriever.search("사회봉사", CONTEXT)
        self.assertEqual([h.chunk_id for h in hits], [chunk()["chunk_id"]])
        lexical.score.assert_called_once_with("사회봉사", [0])
        dense.score.assert_called_once_with("사회봉사", [0])

    def test_backend_enum_contract_covers_official_results(self):
        # AST reads teammate's contract without adding FastAPI/Pydantic test dependencies.
        path = Path(__file__).resolve().parents[2] / "schemas/assistant.py"
        enums = {}
        for node in ast.parse(path.read_text()).body:
            if isinstance(node, ast.ClassDef):
                enums[node.name] = {
                    item.value.value
                    for item in node.body
                    if isinstance(item, ast.Assign) and isinstance(item.value, ast.Constant)
                }
        generators = [
            None,
            RecordingGenerator(),
            HttpAnswerGenerator(
                FakeTransport(completion(content="{}")), dialect="openai-compatible", model="chosen"
            ),
        ]
        for generator in generators:
            result = SchoolRagService(SchoolRetriever([chunk()]), generator).query(
                "사회봉사", CONTEXT
            )
            self.assertIn(result.status, enums["AssistantStatus"])
            self.assertIn(result.reason, enums["AssistantReason"])
            self.assertTrue(set(result.missing_fields) <= enums["MissingContextField"])
