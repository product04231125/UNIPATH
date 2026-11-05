"""Lossless splitting, human-review provenance and official context regression tests."""

import tempfile
import unittest
from copy import deepcopy
from pathlib import Path

from app.rag.evals.__main__ import DEFAULT_CASES, evaluate
from app.rag.ingestion.__main__ import DEFAULT_MANIFEST, REPOSITORY_ROOT, run
from app.rag.ingestion.review import apply_review, review_template
from app.rag.ingestion.sections import chunk_sections
from app.rag.ingestion.types import ExtractedDocument, ExtractedPage
from app.rag.school.contracts import SchoolContext
from app.rag.school.retriever import SchoolRetriever, load_chunks, validate_chunks
from app.rag.school.service import SchoolRagService
from app.rag.tests.test_ingestion import SOURCE
from app.rag.tests.test_school_rag import CONTEXT, RecordingGenerator, chunk


def sections(text="공통 예외\n2026학년도 입학자\n단일전공 120\n2025학년도 입학자\n단일전공 130"):
    return chunk_sections(ExtractedDocument(SOURCE, "a" * 64, "test", [ExtractedPage(1, text)]))[0]


def completed_review(chunks):
    review = review_template(chunks)
    review.update(reviewer="synthetic-reviewer", reviewed_at="2026-01-01T00:00:00+09:00")
    for c, entry in zip(chunks, review["entries"], strict=True):
        entry.update(
            decision="approved",
            source_url="https://example.invalid/rules",
            admission_years=c.get("observed_admission_years") or [2025, 2026],
            tracks=["single_major", "double_major"],
            resolved_warnings=c.get("warnings", []),
            review_note="Synthetic fixture only: checked scope, table headers and exceptions.",
        )
    return review


class ScopeReviewTests(unittest.TestCase):
    def test_split_is_lossless_deterministic_and_never_approved(self):
        text = "공통 예외\n2026학년도 입학자\n단일전공    120\n2025학년도 입학자\n단일전공 130"
        chunks = sections(text)
        self.assertEqual(chunks, sections(text))
        self.assertEqual("".join(c["content"] for c in chunks), text)
        self.assertEqual([c["observed_admission_years"] for c in chunks], [[], [2026], [2025]])
        self.assertTrue(all(c["admission_years"] is None for c in chunks))
        self.assertTrue(all(not c["eligible_for_official_answers"] for c in chunks))
        validate_chunks(chunks)

    def test_inline_year_mention_is_not_a_split_heading(self):
        self.assertEqual(len(sections("규정: 2026학년도 입학자 및 모든 재학생")), 1)

    def test_preview_does_not_mix_year_sections(self):
        hits = SchoolRetriever(sections()).search(
            "단일전공", SchoolContext(admission_year=2026), preview=True
        )
        self.assertTrue(hits)
        self.assertFalse(any("2025학년도" in h.content for h in hits))

    def test_missing_reordered_duplicate_or_tampered_parts(self):
        original = sections()
        validate_chunks(list(reversed(original)))
        for mutation in (
            lambda c: c.pop(),
            lambda c: c[1].update(page_part_index=0),
            lambda c: c[1].update(source_character_start=0),
            lambda c: c[1].update(page_content_hash="b" * 64),
        ):
            data = deepcopy(original)
            mutation(data)
            with self.assertRaises(ValueError):
                validate_chunks(data)

    def test_template_cannot_approve_without_human_fields(self):
        data = sections()
        with self.assertRaises(ValueError):
            apply_review(data, review_template(data))

    def test_review_bound_to_exact_corpus_and_complete_inventory(self):
        data = sections()
        review = completed_review(data)
        for mutation in (
            lambda r: r.update(corpus_sha256="b" * 64),
            lambda r: r["entries"].pop(),
            lambda r: r["entries"][1].update(chunk_id=r["entries"][0]["chunk_id"]),
            lambda r: r["entries"][0].update(content_hash="b" * 64),
        ):
            changed = deepcopy(review)
            mutation(changed)
            with self.assertRaises(ValueError):
                apply_review(data, changed)

    def test_scope_source_note_and_extraction_resolution_required(self):
        data = [chunk(warnings=["table_structure_requires_review"])]
        review = completed_review(data)
        for update in (
            {"admission_years": None},
            {"admission_years": [True]},
            {"tracks": []},
            {"source_url": "https://"},
            {"review_note": ""},
            {"resolved_warnings": []},
            {"resolved_warnings": ["invented"]},
        ):
            changed = deepcopy(review)
            changed["entries"][0].update(update)
            with self.assertRaises(ValueError):
                apply_review(data, changed)

    def test_review_timestamp_requires_timezone_and_cannot_be_future(self):
        data = sections()
        for timestamp in ("2026-01-01", "9999-01-01T00:00:00Z"):
            review = completed_review(data)
            review["reviewed_at"] = timestamp
            with self.assertRaises(ValueError):
                apply_review(data, review)

    def test_review_does_not_mutate_input_and_changes_identity(self):
        data = sections()
        original = deepcopy(data)
        review = completed_review(data)
        result = apply_review(data, review)
        self.assertEqual(data, original)
        self.assertEqual(result, apply_review(data, review))
        self.assertNotEqual(result[0]["chunk_id"], data[0]["chunk_id"])
        self.assertEqual(result[0]["review_record"]["input_chunk_id"], data[0]["chunk_id"])

    def test_approved_scoped_context_keeps_common_exception_and_matching_year(self):
        data = sections()
        reviewed = apply_review(data, completed_review(data))
        generator = RecordingGenerator()
        context = SchoolContext(SOURCE.institution, SOURCE.department, 2026, "single_major")
        result = SchoolRagService(SchoolRetriever(reviewed), generator).query("단일전공", context)
        self.assertEqual(result.status, "grounded")
        evidence = generator.requests[0].evidence
        self.assertTrue(any("공통 예외" in c["content"] for c in evidence))
        self.assertFalse(any("2025학년도" in c["content"] for c in evidence))

    def test_pending_context_blocks_even_when_matching_section_approved(self):
        data = sections()
        review = completed_review(data)
        review["entries"][0]["decision"] = "pending"
        generator = RecordingGenerator()
        result = SchoolRagService(SchoolRetriever(apply_review(data, review)), generator).query(
            "단일전공", SchoolContext(SOURCE.institution, SOURCE.department, 2026, "single_major")
        )
        self.assertEqual(result.reason, "document_context_not_approved_or_incomplete")
        self.assertEqual(generator.requests, [])

    def test_unknown_context_scope_is_not_silently_omitted(self):
        data = [
            chunk("사회봉사", pages=2),
            chunk("면제 조건", page=2, pages=2, admission_years=None),
        ]
        result = SchoolRagService(SchoolRetriever(data), RecordingGenerator()).query(
            "사회봉사", CONTEXT
        )
        self.assertEqual(result.reason, "document_context_not_approved_or_incomplete")

    def test_real_pdfs_v2_keep_all_pages_and_pass_existing_eval(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            report = run(DEFAULT_MANIFEST, REPOSITORY_ROOT, output, chunking="year-sections")
            self.assertEqual((report["page_count"], report["chunk_count"]), (6, 13))
            chunks = load_chunks(output / "chunks.jsonl")
            self.assertEqual(len({(c["document_id"], c["page"]) for c in chunks}), 6)
            evaluation = evaluate(output / "chunks.jsonl", DEFAULT_CASES)
            self.assertEqual(evaluation["passed_count"], evaluation["case_count"])
