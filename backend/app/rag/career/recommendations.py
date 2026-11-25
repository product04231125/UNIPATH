"""Rank only comparisons with selected evidence. Preserve all candidates for inspection."""

from .contracts import Posting
from .job_scope import occupation_matches
from .service import CareerService
from .stage_guidance import build_guidance


def recommend(query, records, sources, analyzer, *, before_analysis=None, academic_stage=None):
    result = CareerService(sources, analyzer, analysis_limit=3).recommend(
        query, {"records": records}, allow_personal_analysis=True, before_analysis=before_analysis
    )
    matches = []
    for item in result["items"]:
        if item["analysis_scope"] == "excerpt":
            item["warnings"].append("공고 본문 앞 20,000자만 비교했습니다.")
        if item["analysis_status"] != "completed":
            continue
        comparisons = item["comparisons"]
        required = [c for c in comparisons if c["priority"] == "required"]
        gaps = sum(c["status"] != "supported" for c in required)
        supported = [c for c in comparisons if c["status"] == "supported"]
        # Every 필수 requirement must be met; one met 필수 is not enough to recommend.
        if not supported or gaps:
            continue
        posting = item["posting"]
        matches.append(
            {
                "source": posting["source"],
                "source_id": posting["source_id"],
                "title": posting["title"],
                "company": posting["company"],
                "url": posting["url"],
                "matched_requirements": supported,
                "required_to_check": gaps,
                "analysis_scope": item["analysis_scope"],
            }
        )
    matches.sort(key=lambda item: (item["required_to_check"], -len(item["matched_requirements"])))
    result["closest_candidates"] = []
    relevant_items = [
        i
        for i in result["items"]
        if occupation_matches(
            Posting(**i["posting"]),
            result["search_keywords"],
            tuple(result["query"]["occupation_codes"]),
        )
    ]
    fallback = None
    if not matches:
        completed = [i for i in relevant_items if i["analysis_status"] == "completed"]
        if completed:

            def distance(item):
                required = [c for c in item["comparisons"] if c["priority"] == "required"]
                partial = sum(c["status"] == "partially_supported" for c in item["comparisons"])
                return (sum(c["status"] != "supported" for c in required), -partial)

            fallback = min(completed, key=distance)
            fallback["warnings"].append(
                "조건 확인 필요: 희망 직무 후보이며 지원조건 충족은 확인되지 않았습니다."
            )
        elif relevant_items:
            fallback = relevant_items[0]
            result["closest_candidates"] = [
                {
                    "posting": fallback["posting"],
                    "analysis_status": fallback["analysis_status"],
                    "notice": "희망 직무 검색 후보 · 분석 미완료",
                }
            ]
    for match in matches:
        match.setdefault("recommendation_type", "evidence_match")
    result["display_candidates"] = []
    matched = {(m["source"], m["source_id"]): m for m in matches}
    for item in result["items"]:
        item["stage_guidance"] = build_guidance(item, academic_stage)
        key = item["posting"]["source"], item["posting"]["source_id"]
        if key in matched:
            result["display_candidates"].append(
                {
                    "posting": item["posting"],
                    "analysis_status": item["analysis_status"],
                    "display_type": matched[key]["recommendation_type"],
                    "notice": matched[key].get("notice", "제출 자료와 일치하는 근거가 있습니다."),
                    "stage_guidance": item["stage_guidance"],
                }
            )
    if not result["display_candidates"] and fallback is not None:
        item = fallback
        completed = item["analysis_status"] == "completed"
        result["display_candidates"] = [
            {
                "posting": item["posting"],
                "analysis_status": item["analysis_status"],
                "display_type": "closest_needs_review" if completed else "analysis_unavailable",
                "notice": "조건 확인 필요 · 지원조건 충족은 확인되지 않았습니다."
                if completed
                else "분석 미완료 · 직무 검색 후보",
                "stage_guidance": item["stage_guidance"],
            }
        ]
    result["recommendations"] = matches
    result["recommendation_order"] = "fewest_unconfirmed_required_then_most_supported"
    return result
