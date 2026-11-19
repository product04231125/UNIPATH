"""Regression tests for document evidence flowing into (and out of) recommendations."""

import base64
import unittest
from io import BytesIO
from types import SimpleNamespace
from unittest.mock import Mock, patch
from zipfile import ZipFile

from app.rag.career.analyzer import EvidenceAnalyzer
from app.rag.career.api import RecommendationRequest, recommendations
from app.rag.career.contracts import Posting
from app.rag.career.documents import prepare_documents


def synthetic_pdf():
    stream = b"BT /F1 14 Tf 10 80 Td (Python project test@example.com) Tj ET"
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 100] "
        b"/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"\nendstream",
    ]
    result = bytearray(b"%PDF-1.4\n")
    offsets = []
    for number, obj in enumerate(objects, 1):
        offsets.append(len(result))
        result.extend(f"{number} 0 obj\n".encode() + obj + b"\nendobj\n")
    start = len(result)
    result.extend(b"xref\n0 6\n0000000000 65535 f \n")
    for offset in offsets:
        result.extend(f"{offset:010d} 00000 n \n".encode())
    result.extend(f"trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n{start}\n%%EOF".encode())
    return bytes(result)


class DocumentRecommendations(unittest.TestCase):
    def test_authenticated_handler_pdf_to_verified_recommendation(self):
        identity = SimpleNamespace(user=SimpleNamespace(id="owner", display_name="임의사용자"))
        model = Mock()

        def generate(instruction, payload):
            record = payload["records"][0]
            self.assertNotIn("test@example.com", record["text"])
            self.assertNotIn("private-name.pdf", str(payload))
            return {
                "comparisons": [
                    {
                        "priority": "required",
                        "requirement": "Python",
                        "posting_quote": "Python",
                        "status": "supported",
                        "explanation": "프로젝트 기록에 Python이 있습니다.",
                        "personal_evidence": [
                            {
                                "kind": record["kind"],
                                "record_id": record["record_id"],
                                "version": 1,
                                "excerpt": "Python project",
                            }
                        ],
                    }
                ]
            }

        model.generate.side_effect = generate
        request = SimpleNamespace(
            app=SimpleNamespace(
                state=SimpleNamespace(
                    portfolio_analyzer=EvidenceAnalyzer(model),
                    settings=SimpleNamespace(vertex_model="gemini-3.5-flash"),
                )
            )
        )
        payload = RecommendationRequest(
            keyword="engineer",
            region="서울",
            documents=[
                {
                    "filename": "private-name.pdf",
                    "content_base64": base64.b64encode(synthetic_pdf()).decode(),
                }
            ],
        )
        db = Mock()
        self.assertEqual(
            recommendations(payload, request, db, identity)["status"], "needs_user_input"
        )
        model.generate.assert_not_called()
        payload.external_processing_consent = True
        posting = Posting(
            "greenhouse",
            "example/1",
            "Engineer",
            "Test",
            "서울",
            "https://job-boards.greenhouse.io/example/jobs/1",
            "Python required",
            "2026-01-01T00:00:00+00:00",
            text_scope="full_text",
        )
        with (
            patch.dict(
                "os.environ",
                {
                    "CAREER_GREENHOUSE_BOARD": "example",
                    "SARAMIN_ACCESS_KEY": "",
                    "WORK24_AUTH_KEY": "",
                },
            ),
            patch("app.services.auth.throttle"),
            patch("app.services.auth.current_identity", return_value=identity),
            patch("app.services.gemini.reserve_call") as reserve,
            patch("app.rag.career.api.Greenhouse.search", return_value=[posting]),
        ):
            result = recommendations(payload, request, db, identity)
            reserve.assert_called_once()
        (item,) = result["recommendations"]
        cite = item["matched_requirements"][0]["personal_evidence"][0]
        self.assertEqual(result["document_locations"][cite["record_id"]]["location"], "1쪽")
        self.assertEqual(item["url"], posting.url)

    def test_model_gaps_or_failure_do_not_become_recommendations(self):
        from app.rag.career.contracts import SearchQuery
        from app.rag.career.recommendations import recommend

        ctx, _, _ = prepare_documents([("portfolio.txt", b"Python project")])
        source = Mock()
        source.name = "greenhouse"
        source.search.return_value = [
            Posting(
                "greenhouse",
                "board/1",
                "Engineer",
                "Example",
                "Seoul",
                "https://example.com/open/1",
                "SQL required; Python preferred",
                "2026-01-01T00:00:00+00:00",
                text_scope="full_text",
            )
        ]
        analyzer = Mock()
        analyzer.analyze.return_value = [
            {"priority": "required", "status": "insufficient_evidence"},
            {"priority": "preferred", "status": "supported"},
        ]
        for preferred_status, failed in (
            ("supported", False), ("insufficient_evidence", False), ("supported", True)
        ):
            analyzer.analyze.return_value[1]["status"] = preferred_status
            if failed:
                analyzer.analyze.side_effect = RuntimeError("model failed")
            result = recommend(SearchQuery("Engineer", "Seoul"), ctx["records"], [source], analyzer)
            if failed:
                self.assertEqual(result["recommendations"], [])
                self.assertEqual(len(result["closest_candidates"]), 1)
                self.assertEqual(len(result["display_candidates"]), 1)
                self.assertEqual(
                    result["display_candidates"][0]["display_type"], "analysis_unavailable"
                )
            else:
                self.assertEqual(
                    result["display_candidates"][0]["display_type"], "closest_needs_review"
                )
                self.assertEqual(result["recommendations"], [])
            self.assertEqual(
                result["items"][0]["analysis_status"], "failed" if failed else "completed"
            )

    def test_docx_paragraphs_redaction_and_unsupported_input(self):
        buf = BytesIO()
        with ZipFile(buf, "w") as archive:
            archive.writestr(
                "word/document.xml",
                """
                <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
                <w:body><w:p><w:r><w:t>Python</w:t></w:r></w:p>
                <w:p><w:r><w:t>test@example.com</w:t></w:r></w:p></w:body></w:document>""",
            )
        records, _, _ = prepare_documents([("demo.docx", buf.getvalue())])
        self.assertEqual(records["records"][0]["text"], "Python\n[이메일]")
        for filename, raw in [("empty.txt", b" "), ("unsupported.exe", b"x")]:
            with self.assertRaises(ValueError):
                prepare_documents([(filename, raw)])
