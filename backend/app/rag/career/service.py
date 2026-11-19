"""Bounded job discovery + comparison. No persistence of personal context/results."""

import logging
import re
from dataclasses import asdict, replace
from datetime import UTC, datetime
from time import monotonic

from .contracts import NotConfigured, Posting, failure_reason, fit_records, selected_records
from .crawling import CrawlBatch
from .job_scope import occupation_matches
from .search_terms import search_terms

logger = logging.getLogger(__name__)


class CareerService:
    def __init__(self, sources, analyzer=None, *, analysis_limit=3, budget_seconds=60):
        if not 0 <= analysis_limit <= 10 or not 1 <= budget_seconds <= 120:
            raise ValueError("Invalid analysis budget")
        self.sources = sources
        self.analyzer = analyzer
        self.analysis_limit = analysis_limit
        self.budget = budget_seconds

    def recommend(self, query, context, *, allow_personal_analysis=False, before_analysis=None):
        records = selected_records(context)
        start = monotonic()
        postings, sources, seen = [], [], set()
        now = datetime.now(UTC)
        crawl_enabled = any(getattr(s, "collection_method", None) == "crawl" for s in self.sources)
        keywords = search_terms(query.keyword)
        rank_candidates = crawl_enabled or len(keywords) > 1
        searches = [
            (source, replace(query, keyword=keyword, limit=10 if rank_candidates else query.limit))
            for keyword in keywords
            for source in self.sources
        ]
        for source, search_query in searches:
            if monotonic() - start >= self.budget:
                sources.append(
                    {
                        "source": source.name,
                        "keyword": search_query.keyword,
                        "status": "skipped",
                        "reason": "time_budget",
                    }
                )
                continue
            try:
                batch = source.search(search_query)
                if not isinstance(batch, list):
                    raise ValueError("Invalid source batch")
                accepted = []
                for posting in batch[: search_query.limit]:
                    if not isinstance(posting, Posting) or posting.source != source.name:
                        raise ValueError("Invalid posting source")
                    if posting.active is False or (
                        posting.expires_at and datetime.fromisoformat(posting.expires_at) < now
                    ):
                        continue
                    key = (posting.source, posting.source_id)
                    accepted.append(posting)
                for posting in accepted:
                    key = (posting.source, posting.source_id)
                    if key not in seen:
                        seen.add(key)
                        postings.append(posting)
                    elif posting.text_scope == "full_text":
                        # Hybrid API discovery may already contain only this posting's metadata.
                        for index, previous in enumerate(postings):
                            if (previous.source, previous.source_id) == key:
                                if previous.text_scope != "full_text":
                                    postings[index] = posting
                                break
                detail_failures = batch.detail_failures if isinstance(batch, CrawlBatch) else {}
                sources.append(
                    {
                        "source": source.name,
                        "keyword": search_query.keyword,
                        "status": ("partial" if batch else "failed")
                        if detail_failures
                        else "completed",
                        "collection_method": getattr(source, "collection_method", "api"),
                        **({"detail_failures": detail_failures} if detail_failures else {}),
                    }
                )
            except NotConfigured:
                sources.append(
                    {
                        "source": source.name,
                        "keyword": search_query.keyword,
                        "status": "not_configured",
                    }
                )
            except ValueError as error:
                sources.append(
                    {
                        "source": source.name,
                        "keyword": search_query.keyword,
                        "status": "failed",
                        "reason": "invalid_query_or_data",
                        "failure_reason": failure_reason(error),
                    }
                )
                logger.warning("posting source %s failed: %s", source.name, failure_reason(error))
            except Exception as error:
                sources.append(
                    {
                        "source": source.name,
                        "keyword": search_query.keyword,
                        "status": "failed",
                        "reason": "source_failed",
                        "failure_reason": failure_reason(error),
                    }
                )
                logger.warning("posting source %s failed: %s", source.name, failure_reason(error))
        collected_count = len(postings)
        excluded_count = 0
        if crawl_enabled:
            scoped = [p for p in postings if occupation_matches(p, keywords)]
            excluded_count = len(postings) - len(scoped)
            postings = scoped
        # A source returns only public posting data; never sees selected personal records.
        if rank_candidates:
            terms = set(
                re.findall(r"[a-z0-9가-힣+#.]{2,}", " ".join(r["text"] for r in records).casefold())
            )

            def relevance(posting):
                words = set(re.findall(r"[a-z0-9가-힣+#.]{2,}", posting.text.casefold()))
                return len(terms & words)

            postings.sort(key=relevance, reverse=True)
        postings = postings[:10]
        items, attempted = [], 0
        for posting in postings[: query.limit]:
            item = {
                "posting": asdict(posting),
                "analysis_status": "not_configured",
                "comparisons": [],
                "analysis_scope": posting.text_scope,
            }
            notes = []
            if not allow_personal_analysis:
                item["analysis_status"] = "personal_analysis_not_authorized"
            elif self.analyzer is not None:
                if attempted >= self.analysis_limit or monotonic() - start >= self.budget:
                    item["analysis_status"] = "budget_exhausted"
                else:
                    if before_analysis is not None:
                        before_analysis()
                    attempted += 1
                    compared = fit_records(records, posting.text)
                    if len(compared) < len(records):
                        notes.append(
                            f"기록이 많아 이 공고와 관련이 높은 기록 {len(compared)}개만 "
                            f"비교했습니다(전체 {len(records)}개)."
                        )
                    try:
                        values = self.analyzer.analyze(posting.text, {"records": compared})
                        item.update(
                            comparisons=values,
                            analysis_status="completed" if values else "insufficient_evidence",
                        )
                    except NotConfigured:
                        item["analysis_status"] = "not_configured"
                    except Exception as error:
                        # The code tells which step failed; never the posting, records or output.
                        item["analysis_status"] = "failed"
                        item["failure_reason"] = failure_reason(error)
                        logger.warning(
                            "posting analysis failed: %s reason=%s",
                            type(error).__name__,
                            item["failure_reason"],
                        )
            item["warnings"] = notes
            if posting.text_scope == "metadata_only":
                item["warnings"].append(
                    "공고 요약 정보만 확보되어 상세 직무·필수조건 비교는 제한됩니다."
                )
            if posting.expires_at is None:
                item["warnings"].append("정확한 마감 시각은 원 공고에서 확인이 필요합니다.")
            items.append(item)
        # Candidate ordering is not a probability of employment.
        any_success = any(s["status"] in {"completed", "partial"} for s in sources)
        all_success = all(s["status"] == "completed" for s in sources)
        return {
            "official": False,
            "status": ("completed" if all_success else "partial")
            if items
            else "no_results"
            if any_success
            else "not_available",
            "query": {"keyword": query.keyword, "region_label": query.region_label},
            "sources": sources,
            "items": items,
            "search_keywords": keywords,
            "candidate_count": len(postings),
            "collected_count": collected_count,
            "excluded_occupation_count": excluded_count,
            "candidate_limit": 10,
            "ranking": "selected_record_term_overlap" if rank_candidates else "source_order",
            "notice": (
                "검색 조건에 따른 공고 후보와 선택 자료의 근거 비교이며 "
                "합격 가능성 점수가 아닙니다."
            ),
        }
