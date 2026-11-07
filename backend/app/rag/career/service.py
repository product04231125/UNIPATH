"""Bounded job discovery + comparison. No persistence of personal context/results."""

from dataclasses import asdict
from datetime import UTC, datetime
from time import monotonic

from .contracts import NotConfigured, Posting, selected_records


class CareerService:
    def __init__(self, sources, analyzer=None, *, analysis_limit=3, budget_seconds=60):
        if not 0 <= analysis_limit <= 10 or not 1 <= budget_seconds <= 120:
            raise ValueError("Invalid analysis budget")
        self.sources = sources
        self.analyzer = analyzer
        self.analysis_limit = analysis_limit
        self.budget = budget_seconds

    def recommend(self, query, context, *, allow_personal_analysis=False):
        records = selected_records(context)
        start = monotonic()
        postings, sources, seen = [], [], set()
        now = datetime.now(UTC)
        for source in self.sources:
            if monotonic() - start >= self.budget:
                sources.append(
                    {"source": source.name, "status": "skipped", "reason": "time_budget"}
                )
                continue
            try:
                batch = source.search(query)
                if not isinstance(batch, list):
                    raise ValueError("Invalid source batch")
                accepted = []
                for posting in batch[: query.limit]:
                    if not isinstance(posting, Posting) or posting.source != source.name:
                        raise ValueError("Invalid posting source")
                    if posting.active is False or (
                        posting.expires_at and datetime.fromisoformat(posting.expires_at) < now
                    ):
                        continue
                    key = (posting.source, posting.source_id)
                    if key not in seen:
                        accepted.append(posting)
                for posting in accepted:
                    key = (posting.source, posting.source_id)
                    if key not in seen:
                        seen.add(key)
                        postings.append(posting)
                sources.append({"source": source.name, "status": "completed"})
            except NotConfigured:
                sources.append({"source": source.name, "status": "not_configured"})
            except ValueError:
                sources.append(
                    {"source": source.name, "status": "failed", "reason": "invalid_query_or_data"}
                )
            except Exception:
                sources.append(
                    {"source": source.name, "status": "failed", "reason": "source_failed"}
                )
        # A source returns only public posting data; never sees selected personal records.
        items, attempted = [], 0
        for posting in postings[: query.limit]:
            item = {
                "posting": asdict(posting),
                "analysis_status": "not_configured",
                "comparisons": [],
                "analysis_scope": posting.text_scope,
            }
            if not allow_personal_analysis:
                item["analysis_status"] = "personal_analysis_not_authorized"
            elif self.analyzer is not None:
                if attempted >= self.analysis_limit or monotonic() - start >= self.budget:
                    item["analysis_status"] = "budget_exhausted"
                else:
                    attempted += 1
                    try:
                        values = self.analyzer.analyze(posting.text, {"records": records})
                        item.update(
                            comparisons=values,
                            analysis_status="completed" if values else "insufficient_evidence",
                        )
                    except NotConfigured:
                        item["analysis_status"] = "not_configured"
                    except Exception:
                        item["analysis_status"] = "failed"
            item["warnings"] = []
            if posting.text_scope == "metadata_only":
                item["warnings"].append(
                    "공고 요약 정보만 확보되어 상세 직무·필수조건 비교는 제한됩니다."
                )
            if posting.expires_at is None:
                item["warnings"].append("정확한 마감 시각은 원 공고에서 확인이 필요합니다.")
            items.append(item)
        # Keep provider order: do not disguise partial metadata evidence counts as a fit score.
        any_success = any(s["status"] == "completed" for s in sources)
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
            "ranking": "source_order",
            "notice": (
                "검색 조건에 따른 공고 후보와 선택 자료의 근거 비교이며 "
                "합격 가능성 점수가 아닙니다."
            ),
        }
