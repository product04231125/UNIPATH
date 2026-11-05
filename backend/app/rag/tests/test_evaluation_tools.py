"""Regression checks for evaluation tools; synthetic approvals only."""

import tempfile
import unittest
from copy import deepcopy
from pathlib import Path

from app.rag.evals.__main__ import evaluate
from app.rag.evals.answers import evaluate_answers
from app.rag.evals.evidence import check_evidence
from app.rag.ingestion.__main__ import DEFAULT_MANIFEST, REPOSITORY_ROOT, run
from app.rag.ingestion.readiness import inspect_corpus
from app.rag.school.retriever import SchoolRetriever
from app.rag.school.service import SchoolRagService
from app.rag.tests.test_school_rag import CONTEXT, RecordingGenerator, chunk


class EvaluationToolTests(unittest.TestCase):
    def fixture(self):
        corpus = [chunk("합성 기준: 사회봉사 36시간. 단일전공에만 적용.")]
        item = corpus[0]
        case = {
            "id": "synthetic",
            "context": {
                "institution": CONTEXT.institution,
                "department": CONTEXT.department,
                "admission_year": 2026,
                "track": "single_major",
            },
            "expected_status": "grounded",
            "expected_reason": "generated_from_evidence",
            "source_versions": {item["document_id"]: item["document_hash"]},
            "evidence": [
                {"document_id": item["document_id"], "page": 1, "quote": "사회봉사 36시간"}
            ],
            "required_patterns": [r"(?<!\d)36\s*시간", "단일전공"],
            "forbidden_patterns": [r"(?<!\d)16\s*시간", "졸업 가능"],
        }
        result = (
            SchoolRagService(SchoolRetriever(corpus), RecordingGenerator())
            .query("사회봉사", CONTEXT)
            .as_dict()
        )
        result["answer"] = "합성 기준은 단일전공 사회봉사 36시간입니다."
        return corpus, [case], [{"id": "synthetic", "result": result}]

    def test_correct_page_wrong_fragment_fails(self):
        ref = {"document_id": "doc", "page": 1, "quote": "2026학년도"}
        self.assertFalse(
            check_evidence([{"document_id": "doc", "page": 1, "content": "2025학년도"}], [ref], [])[
                "passed"
            ]
        )

    def test_forbidden_year_fails_even_with_expected_quote(self):
        ref = {"document_id": "doc", "page": 1, "quote": "2026학년도"}
        forbidden = dict(ref, quote="2025학년도")
        result = check_evidence([dict(ref, content="2026학년도\n2025학년도")], [ref], [forbidden])
        self.assertEqual(result["forbidden_reference_indices"], [0])
        self.assertFalse(result["passed"])

    def test_saved_valid_answer_passes_without_semantic_claim(self):
        corpus, cases, predictions = self.fixture()
        report = evaluate_answers(cases, predictions, corpus)
        self.assertEqual(report["passed_count"], 1)
        self.assertFalse(report["semantic_correctness_verified"])

    def test_wrong_quantity_missing_condition_and_wrong_citation_fail(self):
        for kind in ("quantity", "condition", "page", "id", "excerpt"):
            corpus, cases, predictions = self.fixture()
            result = predictions[0]["result"]
            if kind == "quantity":
                result["answer"] = result["answer"].replace("36", "16")
            elif kind == "condition":
                result["answer"] = result["answer"].replace("단일전공", "")
            elif kind == "page":
                result["citations"][0]["page"] = 2
            elif kind == "id":
                result["citations"][0]["chunk_id"] = "invented"
            else:
                result["citations"][0]["excerpt"] = "tampered"
            self.assertEqual(evaluate_answers(cases, predictions, corpus)["passed_count"], 0)

    def test_unapproved_and_wrong_track_are_not_valid_citations(self):
        for update in ({"review_status": "needs_review"}, {"track": "minor"}):
            corpus, cases, predictions = self.fixture()
            corpus[0].update(update)
            self.assertEqual(evaluate_answers(cases, predictions, corpus)["passed_count"], 0)

    def test_missing_duplicate_and_unknown_prediction_ids_rejected(self):
        corpus, cases, predictions = self.fixture()
        for data in ([], predictions * 2, [dict(predictions[0], id="unknown")]):
            with self.assertRaises(ValueError):
                evaluate_answers(cases, data, corpus)

    def test_stale_source_hash_or_reference_rejected(self):
        for field in ("source_versions", "evidence"):
            corpus, cases, predictions = self.fixture()
            if field == "source_versions":
                cases[0][field] = {}
            else:
                cases[0][field][0]["quote"] = "not in source"
            with self.assertRaises(ValueError):
                evaluate_answers(cases, predictions, corpus)

    def test_non_grounded_cannot_leak_answer(self):
        corpus, _, _ = self.fixture()
        cases = [
            {
                "id": "abstain",
                "expected_status": "insufficient_evidence",
                "expected_reason": "no_approved_matching_evidence",
            }
        ]
        result = {
            "status": "insufficient_evidence",
            "reason": "no_approved_matching_evidence",
            "answer": None,
            "citations": [],
            "missing_fields": [],
        }
        predictions = [{"id": "abstain", "result": result}]
        self.assertEqual(evaluate_answers(cases, predictions, corpus)["passed_count"], 1)
        result["answer"] = "unsupported answer"
        self.assertEqual(evaluate_answers(cases, predictions, corpus)["passed_count"], 0)

    def test_readiness_empty_incomplete_and_draft_never_ready(self):
        for corpus in (
            [],
            [chunk(pages=2)],
            [chunk(review_status="needs_review")],
            [chunk(admission_years=None)],
            [chunk(source_url=None)],
        ):
            original = deepcopy(corpus)
            self.assertFalse(inspect_corpus(corpus)["ready_for_scoped_local_test"])
            self.assertEqual(corpus, original)

    def test_readiness_explains_missing_source_and_review(self):
        report = inspect_corpus([chunk(source_url=None, review_status="needs_review")])
        blockers = report["documents"][0]["chunks"][0]["blockers"]
        self.assertIn("source_url_missing_or_invalid", blockers)
        self.assertIn("review_not_approved", blockers)
        self.assertTrue(report["does_not_authorize_production"])

    def test_synthetic_metadata_ready_does_not_mean_production_authorized(self):
        report = inspect_corpus([chunk()])
        self.assertTrue(report["ready_for_scoped_local_test"])
        self.assertTrue(report["does_not_authorize_production"])

    def test_real_scope_suite_catches_v1_mixing_and_accepts_v2(self):
        cases = Path(__file__).resolve().parents[1] / "evals/scope_questions.jsonl"
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            run(DEFAULT_MANIFEST, REPOSITORY_ROOT, out, chunking="page")
            old = evaluate(out / "chunks.jsonl", cases)
            self.assertLess(old["passed_count"], old["case_count"])
            run(DEFAULT_MANIFEST, REPOSITORY_ROOT, out, chunking="year-sections")
            new = evaluate(out / "chunks.jsonl", cases)
            self.assertEqual(new["passed_count"], 12)
