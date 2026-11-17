"""Exercise image decoding, PDF rendering, and redaction before model calls."""

import unittest
from io import BytesIO
from subprocess import CompletedProcess, TimeoutExpired
from unittest.mock import patch

from PIL import Image

from app.rag.career.documents import prepare_documents
from app.rag.career.ocr import OcrInputError, OcrUnavailable


def image_bytes(fmt):
    with Image.new("RGB", (300, 100), "white") as image, BytesIO() as buf:
        image.save(buf, format=fmt)
        return buf.getvalue()


class CareerOcrTests(unittest.TestCase):
    @patch("app.rag.career.ocr.subprocess.run")
    def test_images_and_pdf_reach_personal_context_with_citations(self, run):
        run.return_value = CompletedProcess([], 0, "자격증 test@example.com".encode(), b"")
        for ext, fmt in [("png", "PNG"), ("jpg", "JPEG"), ("webp", "WEBP"), ("pdf", "PDF")]:
            with self.subTest(fmt=fmt):
                records, refs, warnings = prepare_documents([("sample." + ext, image_bytes(fmt))])
                (record,) = records["records"]
                self.assertEqual(record["text"], "자격증 [이메일]")
                ref = refs[record["record_id"]]
                self.assertEqual(ref["method"], "ocr")
                self.assertEqual(ref["location"], "1쪽" if fmt == "PDF" else "이미지")
                self.assertTrue(warnings)
                self.assertTrue(run.call_args.kwargs["input"].startswith(b"\x89PNG"))
                self.assertIn("kor+eng", run.call_args.args[0])

    @patch("app.rag.career.ocr.subprocess.run")
    def test_invalid_blank_timeout_and_missing_engine(self, run):
        with self.assertRaises(ValueError):
            prepare_documents([("fake.jpg", b"not a jpeg")])
        run.assert_not_called()
        file = [("blank.png", image_bytes("PNG"))]
        run.return_value = CompletedProcess([], 0, b"\n", b"")
        with self.assertRaises(OcrInputError):
            prepare_documents(file)
        for failure, expected in [
            (TimeoutExpired("tesseract", 20), OcrInputError),
            (FileNotFoundError(), OcrUnavailable),
        ]:
            run.side_effect = failure
            with self.assertRaises(expected):
                prepare_documents(file)
