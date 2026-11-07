"""Offline contract tests. All postings and model responses here are synthetic."""

import copy
import json
import unittest
from dataclasses import replace
from unittest.mock import Mock, patch

from app.rag.career.analyzer import EvidenceAnalyzer
from app.rag.career.contracts import NotConfigured, Posting, SearchQuery, selected_records
from app.rag.career.service import CareerService
from app.rag.career.sources import JobKorea, Saramin, Work24, parse_saramin, parse_work24
from app.rag.career.vertex import VertexJSON
from app.rag.guidance import respond

RID = "00000000-0000-4000-8000-000000000001"
CONTEXT = {
    "records": [
        {
            "kind": "credential",
            "record_id": RID,
            "version": 1,
            "text": "정보처리기사 취득",
            "private_field": "not forwarded",
        }
    ]
}
CITE = {"kind": "credential", "record_id": RID, "version": 1, "excerpt": "정보처리기사"}
VALUE = {
    "priority": "preferred",
    "requirement": "정보처리기사 우대",
    "posting_quote": "정보처리기사 우대",
    "status": "supported",
    "personal_evidence": [CITE],
    "explanation": "선택한 기록에 자격증이 기재되어 있습니다.",
}
QUERY = SearchQuery("개발", "전국", nationwide=True)
POSTING = Posting(
    "saramin",
    "synthetic-1",
    "테스트 공고",
    "가상 기업",
    "서울",
    "https://www.saramin.co.kr/jobs/1",
    "😀 정보처리기사 우대",
    "2026-11-06T00:00:00+00:00",
)


class CareerTests(unittest.TestCase):
    def analyzer(self, value=None):
        return EvidenceAnalyzer(
            Mock(
                generate=Mock(
                    return_value={"comparisons": [copy.deepcopy(VALUE if value is None else value)]}
                )
            )
        )

    def test_menu_requires_user_filters_and_records(self):
        response = respond("career:recommend")
        self.assertEqual(response["state"], "needs_input")
        self.assertEqual(response["missing_fields"], ["records", "job_keyword", "region"])
        self.assertEqual(response["workflow"]["region_selection"], "user_selected")
        self.assertEqual(response["cards"], [])

    def test_region_never_defaults_to_nationwide(self):
        with self.assertRaises(ValueError):
            SearchQuery("개발", "")
        transport = Mock()
        with self.assertRaises(ValueError):
            Saramin("key", transport=transport).search(SearchQuery("개발", "서울"))
        transport.request.assert_not_called()
        self.assertIsNone(QUERY.region("saramin"))

    def test_disabled_sources(self):
        for source in (Saramin(), Work24(), JobKorea(), Saramin("key"), Work24("key")):
            with self.subTest(source=source.name), self.assertRaises(NotConfigured):
                source.search(QUERY)

    def test_saramin_metadata_and_expiry(self):
        data = {
            "jobs": {
                "job": [
                    {
                        "id": "1",
                        "url": POSTING.url,
                        "active": "1",
                        "position": {"title": "개발", "location": {"name": "서울"}},
                        "company": {"detail": {"name": "가상 기업"}},
                        "close-type": {"code": "1"},
                        "expiration-timestamp": "1",
                    }
                ]
            }
        }
        item = parse_saramin(data)[0]
        self.assertEqual(item.text_scope, "metadata_only")
        self.assertTrue(item.active)
        self.assertTrue(item.expires_at.startswith("1970"))
        data["jobs"]["job"][0]["close-type"]["code"] = "2"
        self.assertIsNone(parse_saramin(data)[0].expires_at)

    def test_work24_xml_and_entities(self):
        raw = """<wantedRoot><total>1</total><wanted><wantedAuthNo>1</wantedAuthNo>
        <title>개발</title><company>가상 기업</company><region>서울</region>
        <closeDt>2026-12-31</closeDt><wantedInfoUrl>https://www.work24.go.kr/1</wantedInfoUrl>
        </wanted></wantedRoot>""".encode()
        item = parse_work24(raw)[0]
        self.assertEqual(item.expires_at, "2026-12-31T23:59:59+09:00")
        for invalid in (b"<!DOCTYPE x><wantedRoot/>", b"<error/>"):
            with self.assertRaises(ValueError):
                parse_work24(invalid)

    def test_unexpected_host_rejected(self):
        with self.assertRaises(ValueError):
            replace(POSTING, url="https://saramin.co.kr.evil.example/1")

    def test_evidence_offsets_and_whitelist(self):
        analyzer = self.analyzer()
        result = analyzer.analyze(POSTING.text, CONTEXT)[0]
        self.assertEqual(
            result["posting_evidence"], {"start": 2, "end": 11, "excerpt": "정보처리기사 우대"}
        )
        self.assertNotIn(
            "private_field", analyzer.generator.generate.call_args.args[1]["records"][0]
        )

    def test_invalid_citations_and_classifications(self):
        for change in (
            {"personal_evidence": []},
            {"posting_quote": "없는 내용"},
            {"priority": "invented"},
            {"status": "guaranteed"},
            {"personal_evidence": [{**CITE, "version": 2}]},
            {"personal_evidence": [{**CITE, "excerpt": "다른 자격증"}]},
            {"personal_evidence": [{**CITE, "excerpt": " "}]},
        ):
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.analyzer({**VALUE, **change}).analyze(POSTING.text, CONTEXT)
        with self.assertRaises(ValueError):
            self.analyzer().analyze(POSTING.text * 2, CONTEXT)

    def test_duplicate_records_rejected(self):
        with self.assertRaises(ValueError):
            selected_records({"records": CONTEXT["records"] * 2})

    def test_profile_requires_evidence(self):
        generator = Mock(
            generate=Mock(
                return_value={
                    "highlights": [{"summary": "자격증 보유 기록", "personal_evidence": [CITE]}]
                }
            )
        )
        self.assertFalse(EvidenceAnalyzer(generator).analyze_profile(CONTEXT)["official"])
        generator.generate.return_value["highlights"][0]["personal_evidence"] = []
        with self.assertRaises(ValueError):
            EvidenceAnalyzer(generator).analyze_profile(CONTEXT)

    def test_discovery_partial_closed_dedup_and_explicit_analysis(self):
        source = Mock()
        source.name = "saramin"
        source.search.return_value = [
            POSTING,
            POSTING,
            replace(POSTING, source_id="2", active=False),
            replace(POSTING, source_id="3", expires_at="2000-01-01T00:00:00Z"),
        ]
        analyzer = self.analyzer()
        service = CareerService([source, JobKorea()], analyzer)
        result = service.recommend(QUERY, CONTEXT)
        self.assertEqual(result["status"], "partial")
        self.assertEqual(len(result["items"]), 1)
        analyzer.generator.generate.assert_not_called()
        source.search.assert_called_once_with(QUERY)
        result = service.recommend(QUERY, CONTEXT, allow_personal_analysis=True)
        self.assertEqual(result["items"][0]["analysis_status"], "completed")
        self.assertEqual(result["ranking"], "source_order")

    def test_budget_and_not_available_are_distinct_from_no_results(self):
        self.assertEqual(
            CareerService([JobKorea()]).recommend(QUERY, CONTEXT)["status"], "not_available"
        )
        source = Mock()
        source.name = "saramin"
        source.search.return_value = []
        service = CareerService([source])
        self.assertEqual(service.recommend(QUERY, CONTEXT)["status"], "no_results")
        source.search.reset_mock()
        with patch("app.rag.career.service.monotonic", side_effect=[0, 61]):
            self.assertEqual(
                service.recommend(QUERY, CONTEXT)["sources"][0]["reason"], "time_budget"
            )
        source.search.assert_not_called()

    def test_vertex_disabled_never_refreshes_token(self):
        token = Mock()
        with self.assertRaises(NotConfigured):
            VertexJSON("project", "global", "explicit-model", token_provider=token).generate(
                "x", {}
            )
        token.assert_not_called()

    def test_vertex_json_and_incomplete_response(self):
        transport = Mock()
        payload = {
            "candidates": [
                {"finishReason": "STOP", "content": {"parts": [{"text": '{"comparisons": []}'}]}}
            ]
        }
        transport.request.return_value = json.dumps(payload).encode()
        vertex = VertexJSON(
            "project",
            "global",
            "explicit-model",
            token_provider=lambda: "test",
            transport=transport,
        )
        self.assertEqual(vertex.generate("test", {}), {"comparisons": []})
        body = json.loads(transport.request.call_args.kwargs["body"])
        self.assertEqual(body["generationConfig"]["responseMimeType"], "application/json")
        payload["candidates"][0]["finishReason"] = "MAX_TOKENS"
        transport.request.return_value = json.dumps(payload).encode()
        with self.assertRaises(RuntimeError):
            vertex.generate("test", {})
