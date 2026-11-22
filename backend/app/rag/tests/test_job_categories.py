"""Synthetic postings only: a chosen Work24 category scopes the search instead of title words."""

from dataclasses import replace
from unittest.mock import Mock

import pytest

from app.rag.career import categories, crawling
from app.rag.career.api import RecommendationRequest
from app.rag.career.contracts import SearchQuery
from app.rag.career.service import CareerService
from app.rag.tests.test_career_crawling import DETAIL, ID, LINK

RECORDS = {
    "records": [
        {
            "kind": "experience",
            "record_id": "00000000-0000-4000-8000-000000000041",
            "version": 1,
            "text": "React 화면 개발",
        }
    ]
}
QUERY = SearchQuery("", "전국", nationwide=True, limit=3, occupation_codes=("024",))


@pytest.fixture(autouse=True)
def empty_cache():
    crawling._CACHE.clear()


def posting(title, text="합성 업무", source_id=ID):
    return replace(crawling.parse_detail(DETAIL, ID), title=title, text=text, source_id=source_id)


def test_table_is_the_work24_tree_and_codes_are_checked():
    tree = categories.table()["categories"]
    assert len(tree) == 13 and sum(len(c["children"]) for c in tree) == 114
    software = next(c for c in tree if c["code"] == "02")
    assert {"code": "024", "name": "소프트웨어"} in software["children"]
    assert categories.validate_codes(["02", "024"]) == ("02", "024")
    for bad in (["999"], ["024", "024"], ["024"] * 11, [24]):
        with pytest.raises(ValueError):
            categories.validate_codes(bad)


def test_keyword_is_optional_only_with_a_category():
    assert QUERY.keyword == ""
    with pytest.raises(ValueError):
        SearchQuery("", "전국", nationwide=True)
    with pytest.raises(ValueError):
        SearchQuery("개발", "전국", nationwide=True, occupation_codes=("ZZZ",))
    base = {"region": "전국", "external_processing_consent": True}
    assert RecommendationRequest(**base, category_codes=["024"]).keyword == ""
    for bad in ({}, {"category_codes": ["999"]}, {"category_codes": ["0245"]}):
        with pytest.raises(ValueError):
            RecommendationRequest(**base, **bad)


def test_category_search_asks_work24_to_filter_by_its_codes():
    transport = Mock()

    def request(url, **kwargs):
        if url.endswith("robots.txt"):
            return b"User-agent: *\nAllow: /"
        if crawling.LIST in url:
            # A title without the keyword, and a training course the category alone would allow.
            return LINK.replace(b"Python", "합성 시스템 담당".encode()) + LINK.replace(
                ID.encode(), b"K000000000099"
            ).replace(b"Python", "웹개발 양성과정 교육생 모집".encode())
        return DETAIL

    transport.request.side_effect = request
    rows = crawling.Work24Crawler(transport).collect("지원", ("024", "026"))
    lists = [c.args[0] for c in transport.request.call_args_list if crawling.LIST in c.args[0]]
    assert all("occupation=024%2C026" in url and "keywordWantedTitle" not in url for url in lists)
    assert [p.source_id for p in rows] == [ID]


def test_unsupported_sources_are_skipped_and_the_keyword_orders_postings():
    work24 = Mock(supports_occupation=True)
    work24.name = "work24"
    work24.search.return_value = [
        posting("합성 서버 운영", source_id="K1"),
        posting("합성 데이터 업무", "본문에 기술지원 포함", source_id="K2"),
        posting("기술지원 엔지니어", source_id="K3"),
    ]
    saramin = Mock(spec=["name", "search"])
    saramin.name = "saramin"
    result = CareerService([work24, saramin]).recommend(replace(QUERY, keyword="기술지원"), RECORDS)
    assert work24.search.call_args.args[0].occupation_codes == ("024",)
    saramin.search.assert_not_called()
    assert {
        "source": "saramin",
        "keyword": "기술지원",
        "status": "skipped",
        "reason": "category_unsupported",
    } in result["sources"]
    # Title match first, then body match, then the rest.
    assert [i["posting"]["source_id"] for i in result["items"]] == ["K3", "K2", "K1"]
    assert result["query"]["occupation_label"] == "소프트웨어"
    assert result["search_notice"] is None and result["category_browse_available"] is False


def test_no_keyword_match_never_substitutes_postings_and_offers_the_category():
    work24 = Mock(supports_occupation=True)
    work24.name = "work24"
    work24.search.return_value = []
    result = CareerService([work24]).recommend(replace(QUERY, keyword="없는세부어"), RECORDS)
    # One search only: other postings are never shown in place of the detail words.
    assert [c.args[0].keyword for c in work24.search.call_args_list] == ["없는세부어"]
    assert result["items"] == [] and result["status"] == "no_results"
    assert result["category_browse_available"] is True
    assert result["search_notice"] == (
        "고른 직종에서 ‘없는세부어’와 맞는 공고를 찾지 못했습니다. "
        "다른 세부 검색어로 찾거나 직종 전체 공고를 볼 수 있습니다."
    )
    # The student's choice to browse is the same request with an empty keyword.
    work24.search.return_value = [posting("합성 개발자")]
    browse = CareerService([work24]).recommend(QUERY, RECORDS)
    assert len(browse["items"]) == 1
    assert browse["category_browse_available"] is False and browse["search_notice"] is None


def test_category_offer_counts_only_postings_left_after_scope():
    crawler = crawling.Work24Crawler(Mock())
    crawler.search = Mock(return_value=[posting("웹개발 양성과정 교육생 모집")])
    result = CareerService([crawler]).recommend(replace(QUERY, keyword="웹개발"), RECORDS)
    assert result["items"] == [] and result["excluded_occupation_count"] == 1
    assert result["category_browse_available"] is True


def test_failed_collection_is_not_reported_as_no_match():
    work24 = Mock(supports_occupation=True)
    work24.name = "work24"
    work24.search.side_effect = crawling.ProviderFailure("down", "timeout")
    result = CareerService([work24]).recommend(replace(QUERY, keyword="개발"), RECORDS)
    assert result["status"] == "not_available"
    assert result["category_browse_available"] is False and result["search_notice"] is None
