"""Chosen work regions are searched per source, never filtered afterwards; synthetic data only."""

import unittest
from unittest.mock import Mock
from uuid import uuid4

from pydantic import ValidationError

from app.rag.career import crawling, regions
from app.rag.career.api import RecommendationRequest
from app.rag.career.contracts import ProviderFailure, SearchQuery
from app.rag.career.service import CareerService
from app.rag.career.stage_guidance import STAGES

BASE = {"keyword": "프론트엔드", "external_processing_consent": True}


class RegionTests(unittest.TestCase):
    def test_request_takes_several_regions_or_nationwide(self):
        payload = RecommendationRequest(**BASE, regions=["경기", "서울"])
        ordered = [name for name in regions.WORK24 if name in payload.regions]
        self.assertEqual(regions.label(ordered), "서울·경기")
        self.assertEqual(regions.provider_codes(ordered), {"work24": "11000,41000"})
        RecommendationRequest(**BASE, region="전국")
        for bad in ({}, {"regions": ["서울", "서울"]}, {"regions": ["평양"]}):
            with self.subTest(bad=bad), self.assertRaises(ValidationError):
                RecommendationRequest(**BASE, **bad)

    def test_graduating_stage_has_its_own_guidance(self):
        payload = RecommendationRequest(**BASE, region="전국", academic_stage="graduating")
        self.assertEqual(payload.academic_stage, "graduating")
        self.assertIn("졸업 전", STAGES["graduating"])

    def test_list_request_carries_region_codes(self):
        urls = []

        def request(url, **kwargs):
            urls.append(url)
            if url.endswith("robots.txt"):
                return b"User-agent: *\nAllow: /"
            return b""

        # The empty synthetic page stops collection after the first list request.
        with self.assertRaises(ProviderFailure):
            crawling.Work24Crawler(Mock(request=Mock(side_effect=request))).collect(
                "Python", region="11000,41000"
            )
        listing = [u for u in urls if crawling.LIST in u]
        self.assertTrue(listing)
        self.assertTrue(all("region=11000%2C41000" in u for u in listing))

    def test_source_without_region_codes_is_skipped_not_nationwide(self):
        coded, uncoded = Mock(), Mock()
        coded.name, uncoded.name = "work24", "saramin"
        coded.search.return_value = []
        uncoded.filters_region_by_label = False
        query = SearchQuery("Python", "서울", region_codes={"work24": "11000"}, occupation_codes=())
        record = {
            "kind": "experience",
            "record_id": str(uuid4()),
            "version": 1,
            "text": "Python 개발",
        }
        result = CareerService([coded, uncoded], None).recommend(query, {"records": [record]})
        uncoded.search.assert_not_called()
        statuses = {s["source"]: (s["status"], s.get("reason")) for s in result["sources"]}
        self.assertEqual(statuses["saramin"], ("skipped", "region_unsupported"))
        self.assertEqual(statuses["work24"][0], "completed")


if __name__ == "__main__":
    unittest.main()
