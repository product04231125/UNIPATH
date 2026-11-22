"""Synthetic public HTML fixtures; no network or real applicant information."""

import unittest
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from threading import Barrier, Event
from unittest.mock import Mock, patch

from app.rag.career import crawling
from app.rag.career.api import configured_sources
from app.rag.career.contracts import ProviderFailure, SearchQuery
from app.rag.career.job_scope import title_matches
from app.rag.career.service import CareerService

ID = "K120612611180019"
QUERY = SearchQuery("Python", "전국", nationwide=True, limit=3)
DETAIL = """<strong class="title">Python 개발자</strong><p class="corp_info">예시 기업</p>
<div class="fold">직무내용 Python API 개발</div>
<table><tr><th>학력</th><td>무관</td><th>근무 예정지</th><td>서울특별시</td></tr>
<tr><th>담당자 연락처</th><td>010-0000-0000</td></tr></table>
<div><strong>접수 마감일</strong><p>2099.12.31</p></div>""".encode()
LINK = (
    f'<a data-emp-detail href="{crawling.DETAIL}?wantedAuthNo={ID}'
    '&infoTypeCd=VALIDATION">Python 개발자</a>'
).encode()


class CrawlingTests(unittest.TestCase):
    def setUp(self):
        crawling._CACHE.clear()

    def test_detail_extracts_requirements_and_excludes_contact(self):
        p = crawling.parse_detail(DETAIL, ID)
        self.assertIn("Python API", p.text)
        self.assertNotIn("010-", p.text)
        self.assertEqual(p.expires_at, "2099-12-31T23:59:59+09:00")
        self.assertEqual(p.source, "work24")
        with self.assertRaises(ProviderFailure):
            crawling.parse_detail(b"<html>blocked</html>", ID)

    def test_only_native_links_and_explicit_empty(self):
        self.assertEqual(crawling.detail_links(LINK + LINK), [ID])
        self.assertEqual(crawling.detail_links(LINK.replace(b"VALIDATION", b"CJK")), [])
        self.assertEqual(crawling.detail_links("검색 결과가 없습니다".encode()), [])
        for raw in (
            b"<html>blocked</html>",
            LINK.replace(b'href="/', b'href="https://evil.example/'),
        ):
            # Foreign links carrying listing metadata are ignored, never fetched.
            if b"evil" in raw:
                self.assertEqual(crawling.detail_links(raw), [])
            else:
                with self.assertRaises(ProviderFailure):
                    crawling.detail_links(raw)

    def test_cache_expiry_region_and_closed_filter(self):
        source = crawling.Work24Crawler(Mock())
        p = crawling.parse_detail(DETAIL, ID)
        with patch.object(source, "collect", return_value=[p, replace(p, active=False)]) as collect:
            self.assertEqual(len(source.search(QUERY)), 1)
            self.assertEqual(
                source.search(replace(QUERY, nationwide=False, region_label="부산")), []
            )
            collect.assert_called_once_with("Python")
            crawling._CACHE["python"] = (crawling.monotonic() - 301, [p])
            source.search(QUERY)
            self.assertEqual(collect.call_count, 2)

    def test_robots_denial_and_busy(self):
        source = crawling.Work24Crawler(
            Mock(request=Mock(return_value=b"User-agent: *\nDisallow: /"))
        )
        with self.assertRaises(ProviderFailure) as caught:
            source.search(QUERY)
        self.assertEqual(caught.exception.reason, "crawl_disallowed")
        source.transport.request.assert_called_once()
        with patch.object(crawling, "_FETCH_SLOTS") as slots:
            slots.acquire.return_value = False
            with self.assertRaises(ProviderFailure) as caught:
                source.search(QUERY)
            self.assertEqual(caught.exception.reason, "crawl_busy")

    def test_concurrent_users_share_one_collection_per_keyword(self):
        source = crawling.Work24Crawler(Mock())
        posting = crawling.parse_detail(DETAIL, ID)
        entered, release = Event(), Event()

        def slow(keyword):
            entered.set()
            release.wait(5)
            return [posting]

        with patch.object(source, "collect", side_effect=slow) as collect:
            with ThreadPoolExecutor(max_workers=3) as pool:
                first = pool.submit(source.search, QUERY)
                entered.wait(5)
                others = [pool.submit(source.search, QUERY) for _ in range(2)]
                release.set()
                results = [first.result(5)] + [f.result(5) for f in others]
        collect.assert_called_once_with("Python")
        self.assertTrue(all(len(rows) == 1 for rows in results))

    def test_different_keywords_are_collected_at_the_same_time(self):
        source = crawling.Work24Crawler(Mock())
        posting = crawling.parse_detail(DETAIL, ID)
        both = Barrier(2, timeout=5)

        def together(keyword):
            both.wait()  # Raises BrokenBarrierError if collections were serialized.
            return [posting]

        with patch.object(source, "collect", side_effect=together):
            with ThreadPoolExecutor(max_workers=2) as pool:
                futures = [
                    pool.submit(source.search, replace(QUERY, keyword=keyword))
                    for keyword in ("Python", "Java")
                ]
                self.assertTrue(all(len(f.result(10)) == 1 for f in futures))

    def test_a_third_keyword_waits_for_a_slot_then_reports_busy(self):
        source = crawling.Work24Crawler(Mock())
        crawling._FETCH_SLOTS.acquire()
        crawling._FETCH_SLOTS.acquire()
        try:
            with (
                patch.object(crawling, "FETCH_WAIT_SECONDS", 0.05),
                patch.object(source, "collect") as collect,
            ):
                with self.assertRaises(ProviderFailure) as caught:
                    source.search(QUERY)
            self.assertEqual(caught.exception.reason, "crawl_busy")
            collect.assert_not_called()
        finally:
            crawling._FETCH_SLOTS.release()
            crawling._FETCH_SLOTS.release()

    def test_switch_preserves_api_and_adds_hybrid(self):
        with patch.dict("os.environ", {"CAREER_SOURCE_MODE": "api"}):
            self.assertFalse(
                any(isinstance(s, crawling.Work24Crawler) for s in configured_sources())
            )
        with patch.dict("os.environ", {"CAREER_SOURCE_MODE": "crawl"}):
            self.assertEqual(len(configured_sources()), 1)
            self.assertIsInstance(configured_sources()[0], crawling.Work24Crawler)
        with patch.dict("os.environ", {"CAREER_SOURCE_MODE": "hybrid"}):
            self.assertTrue(
                any(isinstance(s, crawling.Work24Crawler) for s in configured_sources())
            )

    def test_selected_record_ranks_before_unrelated_posting(self):
        p = crawling.parse_detail(DETAIL, ID)
        source = crawling.Work24Crawler(Mock())
        source.search = Mock(return_value=[replace(p, source_id="OTHER123", text="회계 결산"), p])
        records = [
            {
                "kind": "experience",
                "record_id": "00000000-0000-4000-8000-000000000001",
                "version": 1,
                "text": "Python API 개발",
            }
        ]
        result = CareerService([source]).recommend(replace(QUERY, limit=1), {"records": records})
        self.assertEqual(result["items"][0]["posting"]["source_id"], ID)
        self.assertEqual(source.search.call_args.args[0].limit, 10)
        self.assertEqual(result["sources"][0]["collection_method"], "crawl")

    def test_hybrid_upgrades_api_metadata_without_duplicates(self):
        p = crawling.parse_detail(DETAIL, ID)
        api = Mock(name="api")
        api.name = "work24"
        api.collection_method = "api"
        api.search.return_value = [replace(p, text="요약", text_scope="metadata_only")]
        crawler = crawling.Work24Crawler(Mock())
        crawler.search = Mock(return_value=[p])
        records = [
            {
                "kind": "experience",
                "record_id": "00000000-0000-4000-8000-000000000001",
                "version": 1,
                "text": "Python 개발",
            }
        ]
        result = CareerService([api, crawler]).recommend(QUERY, {"records": records})
        self.assertEqual(len(result["items"]), 1)
        self.assertEqual(result["items"][0]["analysis_scope"], "full_text")

    def test_multiple_terms_normalize_deduplicate_and_merge(self):
        p = replace(crawling.parse_detail(DETAIL, ID), title="백엔드 개발자")
        source = crawling.Work24Crawler(Mock())
        source.search = Mock(return_value=[p])
        records = [
            {
                "kind": "experience",
                "record_id": "00000000-0000-4000-8000-000000000001",
                "version": 1,
                "text": "Python 개발",
            }
        ]
        result = CareerService([source]).recommend(
            replace(QUERY, keyword="프론트엔드, 벡엔드, 전산실, 백엔드"), {"records": records}
        )
        self.assertEqual(result["search_keywords"], ["프론트엔드", "백엔드", "전산실"])
        self.assertEqual(
            [c.args[0].keyword for c in source.search.call_args_list],
            ["프론트엔드", "백엔드", "전산실"],
        )
        self.assertEqual(result["candidate_count"], 1)
        self.assertEqual(len(result["items"]), 1)

    def test_multi_search_keeps_success_after_one_failure(self):
        p = crawling.parse_detail(DETAIL, ID)
        source = crawling.Work24Crawler(Mock())
        source.search = Mock(
            side_effect=[ProviderFailure("failed", "timeout"), [replace(p, title="백엔드 개발자")]]
        )
        records = [
            {
                "kind": "experience",
                "record_id": "00000000-0000-4000-8000-000000000001",
                "version": 1,
                "text": "Python 개발",
            }
        ]
        result = CareerService([source]).recommend(
            replace(QUERY, keyword="프론트엔드, 백엔드"), {"records": records}
        )
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["sources"][0]["keyword"], "프론트엔드")
        self.assertEqual(len(result["items"]), 1)

    def test_search_terms_bound_and_preserve_multiword_occupation(self):
        from app.rag.career.search_terms import search_terms

        self.assertEqual(
            search_terms("웹 개발자，백엔드\nBACKEND,backend"), ["웹 개발자", "백엔드", "BACKEND"]
        )
        for keyword in (", ,", "a,b,c,d,e,f"):
            with self.assertRaises(ValueError):
                replace(QUERY, keyword=keyword)

    def test_scope_excludes_facility_despite_workplace_keyword(self):
        from app.rag.career.job_scope import occupation_matches

        p = crawling.parse_detail(DETAIL, ID)
        facility = replace(
            p,
            title="전산실 항온항습기 유지보수",
            text="직무내용 전산실 설비 보수\n모집 직종: 냉난방 설비 조작원",
        )
        self.assertFalse(occupation_matches(facility, ["프론트엔드", "백엔드", "전산실"]))
        self.assertTrue(occupation_matches(replace(p, title="전산 시스템 관리자"), ["전산실"]))
        self.assertFalse(
            occupation_matches(replace(p, title="판매원", text="전산실 근무"), ["전산실"])
        )

    def test_collect_paginates_and_deduplicates_to_ten(self):
        def listing(start):
            return b"".join(
                LINK.replace(ID.encode(), f"K0000000{i:04d}".encode())
                for i in range(start, start + 5)
            )

        transport = Mock()

        def request(url, **kwargs):
            if url.endswith("robots.txt"):
                return b"User-agent: *\nAllow: /"
            if crawling.LIST in url:
                return listing(5 if "pageIndex=2" in url else 0)
            return DETAIL

        transport.request.side_effect = request
        rows = crawling.Work24Crawler(transport).collect("Python")
        self.assertEqual(len(rows), 10)
        self.assertEqual(len({p.source_id for p in rows}), 10)
        urls = [c.args[0] for c in transport.request.call_args_list]
        self.assertTrue(any("pageIndex=2" in url for url in urls))
        self.assertTrue(all("keywordWantedTitle=Y" in url for url in urls if crawling.LIST in url))

    def test_unrelated_candidates_never_become_fallback(self):
        from app.rag.career.recommendations import recommend

        p = replace(
            crawling.parse_detail(DETAIL, ID),
            title="항온항습기 유지보수",
            text="직무내용 전산실 냉난방 보수",
        )
        source = crawling.Work24Crawler(Mock())
        source.search = Mock(return_value=[p])
        records = [
            {
                "kind": "experience",
                "record_id": "00000000-0000-4000-8000-000000000001",
                "version": 1,
                "text": "Python 개발",
            }
        ]
        analyzer = Mock()
        result = recommend(replace(QUERY, keyword="전산실"), records, [source], analyzer)
        self.assertEqual(result["recommendations"], [])
        self.assertEqual(result["closest_candidates"], [])
        self.assertEqual(result["excluded_occupation_count"], 1)
        analyzer.analyze.assert_not_called()

    def test_teaching_or_training_titles_are_not_the_occupation(self):
        for title in (
            "[재택가능 / 프론트엔드] 국비과정 전문강사 채용",
            "[국비지원] 웹개발 양성과정 교육생 모집",
            "백엔드 개발 튜터 모집",
        ):
            with self.subTest(title=title):
                self.assertFalse(title_matches(title, ["프론트엔드", "백엔드"]))
        self.assertTrue(title_matches("프론트엔드 개발자 (React)", ["프론트엔드"]))
        # Searching for teaching jobs keeps them.
        self.assertTrue(title_matches("프론트엔드 강사 채용 (국비과정)", ["프론트엔드 강사"]))
        self.assertTrue(title_matches("IT 강사 채용", ["강사"]))

    def test_title_is_primary_not_generic_occupation(self):
        from app.rag.career.job_scope import title_matches

        self.assertFalse(title_matches("여수센텀병원 원내 약국보조 직원구인", ["전산실"]))
        self.assertFalse(title_matches("AI 응용 S/W 연구 개발자", ["백엔드"]))
        self.assertTrue(title_matches("서버 개발자 신입 채용", ["백엔드"]))
        self.assertTrue(title_matches("프론트엔드 React 개발자", ["프론트엔드"]))
        self.assertTrue(title_matches("정보시스템 운영 담당", ["전산실"]))
        self.assertFalse(title_matches("전산실 항온항습기 유지보수", ["전산실"]))
        self.assertFalse(title_matches("전산실 전기/통신 케이블 공사 지원 모집", ["전산실"]))

    def test_title_filter_applies_before_detail_request(self):
        transport = Mock()
        unrelated = LINK.replace("Python 개발자".encode(), "항온항습기 유지보수".encode())
        transport.request.side_effect = lambda url, **kwargs: (
            b"User-agent: *\nAllow: /" if url.endswith("robots.txt") else unrelated
        )
        self.assertEqual(crawling.Work24Crawler(transport).collect("전산실"), [])
        self.assertFalse(
            any(crawling.DETAIL in c.args[0] for c in transport.request.call_args_list)
        )

    def test_merged_candidate_pool_capped_at_ten(self):
        p = crawling.parse_detail(DETAIL, ID)
        source = crawling.Work24Crawler(Mock())
        source.search = Mock(
            side_effect=[
                [replace(p, source_id=f"FIRST{i}") for i in range(20)],
                [replace(p, source_id=f"SECOND{i}") for i in range(20)],
            ]
        )
        records = [
            {
                "kind": "experience",
                "record_id": "00000000-0000-4000-8000-000000000001",
                "version": 1,
                "text": "Python 개발",
            }
        ]
        result = CareerService([source]).recommend(
            replace(QUERY, keyword="Python, Java"), {"records": records}
        )
        self.assertEqual(result["collected_count"], 20)
        self.assertEqual(result["candidate_count"], 10)
        self.assertEqual(len(result["items"]), 3)

    def test_request_cannot_override_server_source_mode(self):
        from pydantic import ValidationError

        from app.rag.career.api import RecommendationRequest

        for mode in ("api", "crawl", "hybrid"):
            with self.subTest(mode=mode), self.assertRaises(ValidationError):
                RecommendationRequest(keyword="Python", region="전국", source_mode=mode)
        self.assertNotIn("source_mode", RecommendationRequest.model_json_schema()["properties"])

    def test_linked_only_first_page_does_not_stop_native_search(self):
        transport = Mock()

        def request(url, **kwargs):
            if url.endswith("robots.txt"):
                return b"User-agent: *\nAllow: /"
            if crawling.LIST in url:
                self.assertIn("siteClcd=WORK", url)
                if "pageIndex=1" in url:
                    return LINK.replace(b"VALIDATION", b"CWT")
                if "pageIndex=2" in url:
                    return LINK
                return "검색 결과가 없습니다".encode()
            return DETAIL

        transport.request.side_effect = request
        rows = crawling.Work24Crawler(transport).collect("Python")
        self.assertEqual([p.source_id for p in rows], [ID])
        detail_urls = [
            c.args[0] for c in transport.request.call_args_list if crawling.DETAIL in c.args[0]
        ]
        self.assertEqual(len(detail_urls), 1)
        self.assertIn("infoTypeCd=VALIDATION", detail_urls[0])

    def test_bad_detail_keeps_four_results_and_cached_failure_counts(self):
        listing = b"".join(LINK.replace(ID.encode(), f"K0000000000{i}".encode()) for i in range(5))
        transport = Mock()

        def request(url, **kwargs):
            if url.endswith("robots.txt"):
                return b"User-agent: *\nAllow: /"
            if crawling.LIST in url:
                return listing if "pageIndex=1" in url else "검색 결과가 없습니다".encode()
            return b"<html>incomplete</html>" if "K00000000000" in url else DETAIL

        transport.request.side_effect = request
        source = crawling.Work24Crawler(transport)
        query = replace(QUERY, limit=10)
        rows = source.search(query)
        self.assertEqual(len(rows), 4)
        self.assertEqual(rows.detail_failures, {"crawl_detail_incomplete": 1})
        calls = transport.request.call_count
        cached = source.search(query)
        self.assertEqual(cached.detail_failures, rows.detail_failures)
        self.assertEqual(transport.request.call_count, calls)
        record = {
            "kind": "experience",
            "record_id": "00000000-0000-4000-8000-000000000001",
            "version": 1,
            "text": "Python",
        }
        result = CareerService([source]).recommend(query, {"records": [record]})
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["sources"][0]["detail_failures"], {"crawl_detail_incomplete": 1})
        self.assertEqual(result["candidate_count"], 4)

    def test_all_details_failed_are_not_reported_as_empty_success(self):
        source = crawling.Work24Crawler(Mock())
        with patch.object(
            source, "collect", return_value=crawling.CrawlBatch(detail_failures={"timeout": 2})
        ):
            record = {
                "kind": "experience",
                "record_id": "00000000-0000-4000-8000-000000000001",
                "version": 1,
                "text": "Python",
            }
            result = CareerService([source]).recommend(QUERY, {"records": [record]})
        self.assertEqual(result["status"], "not_available")
        self.assertEqual(result["sources"][0]["status"], "failed")
        self.assertEqual(result["sources"][0]["detail_failures"], {"timeout": 2})
