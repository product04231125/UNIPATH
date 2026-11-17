"""Rank only comparisons with selected evidence. Preserve all candidates for inspection."""

from .service import CareerService


def recommend(query, records, sources, analyzer, *, before_analysis=None):
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
        if not supported or (required and gaps == len(required)):
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
    result["recommendations"] = matches
    result["recommendation_order"] = "fewest_unconfirmed_required_then_most_supported"
    return result
