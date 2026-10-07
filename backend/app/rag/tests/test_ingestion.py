"""Run from backend/: python -m unittest discover -s app/rag/tests -v."""

import hashlib
import json
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path
from unittest.mock import MagicMock, patch

from app.rag.ingestion.__main__ import DEFAULT_MANIFEST, REPOSITORY_ROOT, read_manifest, run
from app.rag.ingestion.chunker import chunk_document
from app.rag.ingestion.pdf_loader import IngestionError, load_pdf, normalize_layout
from app.rag.ingestion.types import DocumentSource, ExtractedDocument, ExtractedPage, ExtractedTable

SOURCE = DocumentSource(
    document_id="f04d1983-f366-4b22-b4d0-ecaeaa16fe11",
    source_file="fixture.pdf",
    title="Synthetic rules",
    institution="Test university",
    department="Test department",
    expected_sha256="0" * 64,
)


def fixture_pdf(text: str | None) -> bytes:
    """Small valid PDF fixture; no extra PDF-authoring test dependency is needed."""
    stream = b"" if text is None else f"BT /F1 12 Tf 50 700 Td ({text}) Tj ET".encode()
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
        b"/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"\nendstream",
    ]
    raw = b"%PDF-1.4\n"
    offsets = [0]
    for index, obj in enumerate(objects, 1):
        offsets.append(len(raw))
        raw += f"{index} 0 obj\n".encode() + obj + b"\nendobj\n"
    xref = len(raw)
    raw += f"xref\n0 {len(offsets)}\n0000000000 65535 f \n".encode()
    raw += b"".join(f"{offset:010d} 00000 n \n".encode() for offset in offsets[1:])
    raw += (f"trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n").encode()
    return raw


class ChunkTests(unittest.TestCase):
    def document(self, pages):
        return ExtractedDocument(SOURCE, "a" * 64, "test", pages)

    def test_keeps_table_spacing_headers_and_null_cells(self):
        content = "2026 admission\nMajor    Total\n66       120\n2025 admission\n66       120"
        table = ExtractedTable((1, 2, 3, 4), [["Major", "Total"], [None, "120"]])
        chunks, _ = chunk_document(self.document([ExtractedPage(1, content, [table])]))
        self.assertEqual(chunks[0]["content"], content)
        self.assertIsNone(chunks[0]["tables"][0]["rows"][1][0])
        self.assertIsNone(chunks[0]["admission_years"])
        self.assertIsNone(chunks[0]["track"])
        self.assertFalse(chunks[0]["eligible_for_official_answers"])

    def test_no_empty_chunks_and_original_page_numbers_are_preserved(self):
        pages = [ExtractedPage(1, ""), ExtractedPage(2, "Actual evidence")]
        chunks, report = chunk_document(self.document(pages))
        self.assertEqual(len(chunks), 1)
        self.assertEqual(chunks[0]["page"], 2)
        self.assertEqual(chunks[0]["chunk_index"], 0)
        self.assertEqual(report["pages"][0]["status"], "needs_review")

    def test_identity_is_stable_but_changes_with_content_or_metadata(self):
        document = self.document([ExtractedPage(1, "Evidence")])
        first, _ = chunk_document(document)
        second, _ = chunk_document(document)
        self.assertEqual(first, second)
        changed, _ = chunk_document(replace(document, pages=[ExtractedPage(1, "New evidence")]))
        self.assertNotEqual(first[0]["chunk_id"], changed[0]["chunk_id"])
        changed, _ = chunk_document(replace(document, source=replace(SOURCE, title="New title")))
        self.assertNotEqual(first[0]["chunk_id"], changed[0]["chunk_id"])

    def test_large_page_is_flagged_not_silently_truncated(self):
        text = "a" * 12001
        chunks, _ = chunk_document(self.document([ExtractedPage(1, text)]))
        self.assertEqual(chunks[0]["content"], text)
        self.assertIn("large_page_not_split", chunks[0]["warnings"])

    def test_normalization_preserves_column_spacing(self):
        self.assertEqual(
            normalize_layout("\n   \n  Major    66  \r\n  Total   120\n  "),
            "  Major    66\n  Total   120",
        )


class LoaderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def source(self, raw):
        (self.root / "fixture.pdf").write_bytes(raw)
        return replace(SOURCE, expected_sha256=hashlib.sha256(raw).hexdigest())

    def test_extracts_real_text_layer(self):
        document = load_pdf(self.source(fixture_pdf("Major 66 Total 120")), self.root)
        self.assertIn("Major 66 Total 120", document.pages[0].content)
        self.assertEqual(document.pages[0].page, 1)

    def test_blank_page_requires_review_and_produces_no_chunk(self):
        document = load_pdf(self.source(fixture_pdf(None)), self.root)
        self.assertIn("no_text_layer_needs_review_or_ocr", document.pages[0].warnings)
        chunks, _ = chunk_document(document)
        self.assertEqual(chunks, [])

    def test_changed_source_is_rejected(self):
        source = self.source(fixture_pdf("Old"))
        (self.root / "fixture.pdf").write_bytes(fixture_pdf("Changed"))
        with self.assertRaisesRegex(IngestionError, "hash mismatch"):
            load_pdf(source, self.root)

    def test_malformed_pdf_is_reported(self):
        with self.assertRaisesRegex(IngestionError, "Cannot extract PDF"):
            load_pdf(self.source(b"%PDF-1.4\nbroken"), self.root)

    def test_missing_file_is_reported(self):
        with self.assertRaisesRegex(IngestionError, "Cannot read source"):
            load_pdf(SOURCE, self.root)

    def test_paths_outside_source_root_are_rejected(self):
        with self.assertRaisesRegex(IngestionError, "inside source_root"):
            load_pdf(replace(SOURCE, source_file="../fixture.pdf"), self.root)

    def test_table_failure_keeps_text_but_marks_review(self):
        source = self.source(fixture_pdf("Evidence"))
        page = MagicMock()
        page.extract_text.return_value = "Evidence"
        page.find_tables.side_effect = ValueError("broken table")
        pdf = MagicMock()
        pdf.__enter__.return_value.pages = [page]
        with patch("pdfplumber.open", return_value=pdf):
            document = load_pdf(source, self.root)
        self.assertEqual(document.pages[0].content, "Evidence")
        self.assertIn("table_extraction_failed", document.pages[0].warnings)


class PipelineTests(unittest.TestCase):
    def test_bundled_sources_provenance_tables_and_idempotent_output(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            report = run(DEFAULT_MANIFEST, REPOSITORY_ROOT, output)
            first = (output / "chunks.jsonl").read_bytes()
            first_report = (output / "report.json").read_bytes()
            run(DEFAULT_MANIFEST, REPOSITORY_ROOT, output)
            self.assertEqual(first, (output / "chunks.jsonl").read_bytes())
            self.assertEqual(first_report, (output / "report.json").read_bytes())
            self.assertEqual(
                (
                    report["document_count"],
                    report["page_count"],
                    report["chunk_count"],
                    report["empty_page_count"],
                ),
                (2, 6, 6, 0),
            )
            chunks = [json.loads(line) for line in first.decode().splitlines()]
            self.assertEqual(len({chunk["chunk_id"] for chunk in chunks}), 6)
            self.assertEqual([chunk["page"] for chunk in chunks], [1, 2, 3, 1, 2, 3])
            self.assertTrue(all(chunk["tables"] for chunk in chunks))
            for year in (2026, 2025, 2024):
                self.assertIn(f"{year}학년도", chunks[0]["content"])
            for year in (2020, 2019, 2018):
                self.assertIn(f"{year}학년도", chunks[2]["content"])
            self.assertIn("130", chunks[2]["content"])
            self.assertIn("120", chunks[0]["content"])
            # Check actual column alignment, not merely presence of isolated numbers.
            first_table = chunks[0]["tables"][0]["rows"]
            single_major = next(row for row in first_table if "단일전공" in row)
            self.assertEqual(
                single_major[2:13],
                ["7", "5", "6", "4", "9", "31", "15", "51", "66", "23", "120"],
            )
            self.assertIn("36시간", chunks[4]["content"])
            self.assertIn("16시간", chunks[5]["content"])
            self.assertTrue(all(not c["eligible_for_official_answers"] for c in chunks))

    def test_failed_extraction_does_not_replace_previous_outputs(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            old = root / "chunks.jsonl"
            old.write_text("previous output", encoding="utf-8")
            payload = json.loads(DEFAULT_MANIFEST.read_text(encoding="utf-8"))
            payload["documents"][-1]["expected_sha256"] = "0" * 64
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaises(IngestionError):
                run(manifest, REPOSITORY_ROOT, root)
            self.assertEqual(old.read_text(), "previous output")

    def test_duplicate_manifest_documents_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            manifest = Path(folder) / "manifest.json"
            payload = json.loads(DEFAULT_MANIFEST.read_text(encoding="utf-8"))
            payload["documents"].append(payload["documents"][0])
            manifest.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(IngestionError, "Duplicate document_id"):
                read_manifest(manifest)


if __name__ == "__main__":
    unittest.main()
