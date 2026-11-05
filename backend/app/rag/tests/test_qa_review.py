import re
import unittest
from copy import deepcopy

from app.rag.evals.answers import evaluate_answers
from app.rag.evals.qa import compile_cases, literal_pattern
from app.rag.ingestion.readiness import inspect_corpus
from app.rag.ingestion.review_pack import render
from app.rag.tests import test_evaluation_tools
from app.rag.tests.test_school_rag import chunk


class QAReviewTests(unittest.TestCase):
    def worksheet(self):
        corpus, cases, predictions = test_evaluation_tools.EvaluationToolTests().fixture()
        row = dict(
            cases[0],
            question="단일전공 사회봉사 시간은?",
            author="QA 작성자",
            reviewer="원문 검토자",
            reviewed=True,
            suite="holdout",
            required_phrases=["36시간", "단일전공"],
            forbidden_phrases=["16시간"],
        )
        return corpus, [row], predictions

    def test_reviewed_blank_is_complete_but_never_searchable_text(self):
        corpus = [chunk(pages=2, reviewed_blank_pages=[2])]
        original = deepcopy(corpus)
        report = inspect_corpus(corpus)["documents"][0]
        self.assertTrue(report["ready_for_scoped_local_test"])
        self.assertEqual(report["missing_pages"], [])
        self.assertEqual(report["reviewed_blank_pages"], [2])
        self.assertEqual(corpus, original)
        corpus[0]["reviewed_blank_pages"] = []
        self.assertEqual(inspect_corpus(corpus)["documents"][0]["missing_pages"], [2])

    def test_invalid_blank_declaration_is_rejected(self):
        for blank in ([1], [3], [2, 2]):
            with self.assertRaises(ValueError):
                inspect_corpus([chunk(pages=2, reviewed_blank_pages=blank)])

    def test_html_escapes_source_and_preserves_review_blockers(self):
        corpus = [chunk("<script>alert(1)</script>", source_url=None)]
        original = deepcopy(corpus)
        page = render(corpus)
        self.assertNotIn("<script>", page)
        self.assertIn("&lt;script&gt;", page)
        self.assertIn("source_url_missing_or_invalid", page)
        self.assertEqual(corpus, original)

    def test_qa_compiles_into_existing_answer_evaluator(self):
        corpus, rows, predictions = self.worksheet()
        compiled = compile_cases(rows, corpus)
        self.assertEqual(evaluate_answers(compiled, predictions, corpus)["passed_count"], 1)
        for bad in ("단일전공 136시간", "단일전공 36.5시간", "복수전공 36시간"):
            predictions[0]["result"]["answer"] = bad
            self.assertEqual(evaluate_answers(compiled, predictions, corpus)["passed_count"], 0)

    def test_unreviewed_self_reviewed_or_stale_qa_rejected(self):
        for update in (
            {"reviewed": False},
            {"reviewer": "QA 작성자"},
            {"source_versions": {}},
            {"required_phrases": []},
        ):
            corpus, rows, _ = self.worksheet()
            rows[0].update(update)
            with self.assertRaises(ValueError):
                compile_cases(rows, corpus)

    def test_literals_are_not_regex_and_spacing_is_flexible(self):
        pattern = literal_pattern("36 시간 (단일전공)")
        self.assertIsNotNone(re.search(pattern, "36시간 (단일 전공)"))
        self.assertIsNone(re.search(pattern, "136시간 (단일전공)"))
        self.assertIsNone(re.search(literal_pattern("36"), "36.5"))

    def test_wrong_year_and_track_answer_is_rejected(self):
        corpus, rows, predictions = self.worksheet()
        rows[0]["required_phrases"] += ["2026학년도"]
        cases = compile_cases(rows, corpus)
        for answer, count in [
            ("2026학년도 단일전공 36시간", 1),
            ("2025학년도 단일전공 36시간", 0),
            ("2026학년도 부전공 36시간", 0),
        ]:
            predictions[0]["result"]["answer"] = answer
            self.assertEqual(evaluate_answers(cases, predictions, corpus)["passed_count"], count)
