"""RAG-local tests: synthetic approval only, no network or real user records."""

import hashlib
import json
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path
from uuid import NAMESPACE_URL, uuid5

from app.rag.evals.__main__ import DEFAULT_CASES, evaluate
from app.rag.ingestion.__main__ import DEFAULT_MANIFEST, REPOSITORY_ROOT, run
from app.rag.school.contracts import GeneratedAnswer, SchoolContext
from app.rag.school.embeddings import EmbeddingRanker, unit_vector
from app.rag.school.retriever import SchoolRetriever, load_chunks, tokenize
from app.rag.school.service import SchoolRagService

CONTEXT = SchoolContext("테스트대학교", "테스트학과", 2026, "single_major")


def chunk(text="사회봉사 인증 기준", *, page=1, pages=1, doc="synthetic", **overrides):
    result = {
        "chunk_id": str(uuid5(NAMESPACE_URL, f"{doc}/{page}")),
        "document_id": str(uuid5(NAMESPACE_URL, doc)),
        "title": "합성 학사규정",
        "source_file": "synthetic.pdf",
        "source_url": "https://example.invalid/rules",
        "page": page,
        "document_page_count": pages,
        "document_hash": "a" * 64,
        "content": text,
        "content_hash": hashlib.sha256(text.encode()).hexdigest(),
        "institution": "테스트대학교",
        "department": "테스트학과",
        "admission_years": [2026],
        "track": "single_major",
        "eligible_for_official_answers": True,
        "review_status": "approved",
        "applicability_status": "verified",
        "warnings": [],
    }
    result.update(overrides)
    return result


class RecordingGenerator:
    def __init__(self, response=None, error=None):
        self.response = response
        self.error = error
        self.requests = []

    def generate(self, request):
        self.requests.append(request)
        if self.error:
            raise self.error
        return self.response or GeneratedAnswer(
            "합성 근거를 설명합니다.", [request.evidence[0]["chunk_id"]]
        )


class RetrievalTests(unittest.TestCase):
    def test_korean_suffixes_share_search_terms(self):
        self.assertTrue(set(tokenize("사회봉사는")) & set(tokenize("사회봉사")))
        self.assertIn("2026", tokenize("2026학번"))

    def test_drafts_are_excluded_by_default(self):
        corpus = [chunk(review_status="needs_review", eligible_for_official_answers=False)]
        retriever = SchoolRetriever(corpus)
        self.assertEqual(retriever.search("사회봉사", CONTEXT), [])
        self.assertEqual(len(retriever.search("사회봉사", CONTEXT, preview=True)), 1)

    def test_all_scope_fields_are_enforced_before_ranking(self):
        for updates in (
            {"institution": "다른대학교"},
            {"department": "다른학과"},
            {"admission_years": [2019]},
            {"track": "minor"},
            {"admission_years": None},
            {"track": None},
        ):
            with self.subTest(updates=updates):
                self.assertEqual(
                    SchoolRetriever([chunk(**updates)]).search("사회봉사", CONTEXT), []
                )

    def test_review_warnings_block_official_retrieval(self):
        self.assertEqual(
            SchoolRetriever([chunk(warnings=["table_structure_requires_review"])]).search(
                "사회봉사", CONTEXT
            ),
            [],
        )

    def test_year_headings_filter_preview_without_becoming_approved_scope(self):
        retriever = SchoolRetriever([chunk("2019학년도 입학자 졸업학점", admission_years=None)])
        self.assertEqual(retriever.search("졸업학점", CONTEXT, preview=True), [])
        hits = retriever.search("졸업학점", SchoolContext(admission_year=2019), preview=True)
        self.assertEqual(len(hits), 1)

    def test_empty_corpus_and_no_shared_terms(self):
        self.assertEqual(SchoolRetriever([]).search("사회봉사", CONTEXT), [])
        self.assertEqual(SchoolRetriever([chunk()]).search("블랙홀", CONTEXT), [])
        self.assertEqual(SchoolRetriever([chunk("😀", title="😀")]).search("😀", CONTEXT), [])

    def test_invalid_top_k_and_empty_question(self):
        retriever = SchoolRetriever([chunk()])
        for top_k in (0, 21):
            with self.assertRaises(ValueError):
                retriever.search("사회봉사", CONTEXT, top_k=top_k)
        with self.assertRaises(ValueError):
            retriever.search("  ", CONTEXT)

    def test_duplicate_chunk_and_content_tampering_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            SchoolRetriever([chunk(), chunk()])
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            SchoolRetriever([chunk(content="tampered")])

    def test_mixed_document_versions_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "Mixed document"):
            SchoolRetriever(
                [chunk(page=1, pages=2), chunk(page=2, pages=2, document_hash="b" * 64)]
            )

    def test_invalid_context_is_rejected(self):
        for data in (
            {"admission_year": True},
            {"admission_year": "2026"},
            {"admission_year": 0},
            {"institution": " "},
        ):
            with self.assertRaises(ValueError):
                SchoolContext(**data)


class ServiceTests(unittest.TestCase):
    def test_missing_school_and_academic_scope(self):
        service = SchoolRagService(SchoolRetriever([chunk()]))
        self.assertEqual(
            service.query("사회봉사", SchoolContext()).missing_fields, ["institution", "department"]
        )
        result = service.query("전공학점", SchoolContext("테스트대학교", "테스트학과"))
        self.assertEqual(result.missing_fields, ["admission_year", "track"])

    def test_conflicting_year_is_not_silently_overridden(self):
        result = SchoolRagService(SchoolRetriever([chunk()])).query("2019학번 학점", CONTEXT)
        self.assertEqual(result.reason, "conflicting_admission_year")

    def test_personal_graduation_requires_rule_engine(self):
        generator = RecordingGenerator()
        service = SchoolRagService(SchoolRetriever([chunk()]), generator)
        for question in ("졸업 가능한가요?", "제가 졸업할 수 있나요?", "졸업 되나요?"):
            self.assertEqual(service.query(question, CONTEXT).reason, "rule_engine_required")
        self.assertEqual(generator.requests, [])

    def test_preview_never_calls_generator_or_returns_grounded_answer(self):
        generator = RecordingGenerator()
        result = SchoolRagService(SchoolRetriever([chunk()]), generator).query(
            "사회봉사", CONTEXT, preview=True
        )
        self.assertEqual(result.status, "insufficient_evidence")
        self.assertTrue(result.candidates)
        self.assertIsNone(result.answer)
        self.assertEqual(result.citations, [])
        self.assertEqual(generator.requests, [])

    def test_unapproved_sources_do_not_reach_generator(self):
        generator = RecordingGenerator()
        service = SchoolRagService(
            SchoolRetriever([chunk(review_status="needs_review")]), generator
        )
        self.assertEqual(service.query("사회봉사", CONTEXT).reason, "no_approved_matching_evidence")
        self.assertEqual(generator.requests, [])

    def test_document_context_and_user_scope_reach_generator(self):
        generator = RecordingGenerator()
        corpus = [
            chunk("전체 적용 조건", page=1, pages=2),
            chunk("사회봉사 인증 기준", page=2, pages=2),
        ]
        result = SchoolRagService(SchoolRetriever(corpus), generator).query("사회봉사", CONTEXT)
        self.assertEqual(result.status, "grounded")
        request = generator.requests[0]
        self.assertEqual(len(request.evidence), 2)
        self.assertEqual(request.context["admission_year"], 2026)
        self.assertIn("신뢰할 수 없는 데이터", request.system_instruction)
        self.assertEqual(result.citations[0]["source_url"], corpus[0]["source_url"])
        self.assertEqual(result.citations[0]["page"], 1)

    def test_incomplete_or_unapproved_context_blocks_generation(self):
        generator = RecordingGenerator()
        for corpus in (
            [chunk(pages=2)],
            [chunk(page=1, pages=2), chunk(page=2, pages=2, review_status="needs_review")],
        ):
            with self.subTest(corpus=corpus):
                result = SchoolRagService(SchoolRetriever(corpus), generator).query(
                    "사회봉사", CONTEXT
                )
                self.assertEqual(result.reason, "document_context_not_approved_or_incomplete")
        self.assertEqual(generator.requests, [])

    def test_missing_generator_is_explicit(self):
        result = SchoolRagService(SchoolRetriever([chunk()])).query("사회봉사", CONTEXT)
        self.assertEqual(result.reason, "answer_generator_not_configured")

    def test_invented_or_missing_citations_are_rejected(self):
        for references in ([], ["made-up"], [123]):
            generator = RecordingGenerator(GeneratedAnswer("unsupported", references))
            result = SchoolRagService(SchoolRetriever([chunk()]), generator).query(
                "사회봉사", CONTEXT
            )
            self.assertEqual(result.status, "failed")
            self.assertEqual(result.citations, [])

    def test_generator_abstention(self):
        generator = RecordingGenerator(GeneratedAnswer("", [], insufficient_evidence=True))
        result = SchoolRagService(SchoolRetriever([chunk()]), generator).query("사회봉사", CONTEXT)
        self.assertEqual(result.status, "insufficient_evidence")

    def test_provider_error_details_are_not_exposed(self):
        generator = RecordingGenerator(error=RuntimeError("secret-api-key"))
        result = SchoolRagService(SchoolRetriever([chunk()]), generator).query("사회봉사", CONTEXT)
        self.assertEqual(result.status, "failed")
        self.assertNotIn("secret-api-key", json.dumps(result.as_dict()))

    def test_non_boolean_abstention_is_invalid(self):
        generator = RecordingGenerator(GeneratedAnswer("answer", [], insufficient_evidence="false"))
        result = SchoolRagService(SchoolRetriever([chunk()]), generator).query("사회봉사", CONTEXT)
        self.assertEqual(result.reason, "invalid_generator_output")


class VectorTests(unittest.TestCase):
    class Provider:
        model_id = "synthetic-v1"

        def embed_documents(self, texts):
            return [[1.0, 0.0], [0.0, 1.0]]

        def embed_query(self, text):
            return [0.0, 1.0]

    def test_cosine_ranking_and_scope_filter(self):
        corpus = [chunk(doc="one"), chunk(doc="two")]
        ranker = EmbeddingRanker(corpus, self.Provider())
        retriever = SchoolRetriever(corpus, ranker)
        self.assertEqual(retriever.search("any", CONTEXT)[0].document_id, corpus[1]["document_id"])
        self.assertEqual(retriever.search("any", SchoolContext(institution="other")), [])

    def test_invalid_vectors(self):
        for vector in ([], [0, 0], [float("nan"), 1], [float("inf"), 1], [True, 1]):
            with self.assertRaises(ValueError):
                unit_vector(vector)
        with self.assertRaises(ValueError):
            unit_vector([1, 0], dimension=3)

    def test_changed_model_is_rejected(self):
        provider = self.Provider()
        ranker = EmbeddingRanker([chunk(doc="one"), chunk(doc="two")], provider)
        provider.model_id = "synthetic-v2"
        with self.assertRaisesRegex(ValueError, "changed"):
            ranker.score("query", [0])

    def test_wrong_number_of_embeddings(self):
        with self.assertRaisesRegex(ValueError, "number"):
            EmbeddingRanker([chunk()], self.Provider())


class EvaluationTests(unittest.TestCase):
    def test_real_corpus_development_suite(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            run(DEFAULT_MANIFEST, REPOSITORY_ROOT, output)
            report = evaluate(output / "chunks.jsonl", DEFAULT_CASES)
            self.assertEqual(report["case_count"], 36)
            self.assertEqual(report["passed_count"], 36)
            self.assertTrue(report["not_an_independent_accuracy_estimate"])

    def test_evaluation_detects_source_version_drift(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "chunks.jsonl"
            path.write_text(json.dumps(chunk()), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "source versions changed"):
                evaluate(path, DEFAULT_CASES)

    def test_loader_rejects_corrupted_corpus(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "chunks.jsonl"
            data = deepcopy(chunk())
            data["content"] = "different text"
            path.write_text(json.dumps(data), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "hash mismatch"):
                load_chunks(path)


if __name__ == "__main__":
    unittest.main()
