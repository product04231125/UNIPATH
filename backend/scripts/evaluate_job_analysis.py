"""Evaluate job analysis on synthetic scenarios, offline or against configured Gemini.

    uv run --frozen python -m scripts.evaluate_job_analysis --replies replies.json
    uv run --frozen python -m scripts.evaluate_job_analysis --live

--replies reads stored model JSON objects keyed by scenario ID and calls nothing.
--live sends only the synthetic scenarios in tests/fixtures to the configured model.
"""

import argparse
import json
import statistics
import sys
import time
from pathlib import Path

from app.core.config import Settings
from app.rag.career.analyzer import INSTRUCTION, EvidenceAnalyzer
from app.schemas.personalization import PersonalizationContext
from app.services import gemini
from app.services.job_analysis.service import validate_comparisons

FIXTURES = Path(__file__).resolve().parents[1] / "tests/fixtures/job_analysis_scenarios.json"


class StoredReply:
    def __init__(self, reply):
        self.reply = reply

    def generate(self, instruction, payload):
        return self.reply


def context_of(scenario):
    records = [
        {**record, "title": record["text"].split("\n")[0].removeprefix("title: ")}
        for record in scenario["records"]
    ]
    return PersonalizationContext(records=records)


def check(scenario, comparisons):
    expect, problems = scenario["expect"], []
    if expect.get("no_comparisons"):
        return [f"unexpected comparison: {c.requirement}" for c in comparisons]
    by_keyword = lambda word: [c for c in comparisons if word.lower() in c.requirement.lower()]  # noqa: E731
    if expect.get("require_required") and not any(c.priority == "required" for c in comparisons):
        problems.append("no required item")
    for word in expect.get("supported_keywords", []):
        if not any(c.status != "insufficient_evidence" for c in by_keyword(word)):
            problems.append(f"expected support for {word}")
    for word in expect.get("insufficient_keywords", []):
        items = by_keyword(word)
        if not items or any(c.status != "insufficient_evidence" for c in items):
            problems.append(f"expected insufficient evidence for {word}")
    for word in expect.get("priority_preferred_keywords", []):
        if any(c.priority != "preferred" for c in by_keyword(word)):
            problems.append(f"expected preferred priority for {word}")
    if expect.get("forbid_supported") and any(c.status == "supported" for c in comparisons):
        problems.append("fully supported claim")
    text = " ".join(c.requirement + " " + c.explanation for c in comparisons)
    problems += [f"forbidden text: {w}" for w in expect.get("forbidden_text", []) if w in text]
    return problems


def evaluate(scenario, model):
    context = context_of(scenario)
    started = time.perf_counter()
    try:
        values = EvidenceAnalyzer(model).analyze(scenario["posting_text"], context)
        comparisons = validate_comparisons(scenario["posting_text"], context, values)
    except Exception as error:
        return {
            "id": scenario["id"],
            "seconds": time.perf_counter() - started,
            "valid": False,
            "error": type(error).__name__ + ": " + str(error)[:120],
            "problems": ["output rejected"],
        }
    return {
        "id": scenario["id"],
        "seconds": time.perf_counter() - started,
        "valid": True,
        "comparisons": [
            {
                "priority": item.priority,
                "requirement": item.requirement,
                "status": item.status,
                "citations": len(item.personal_evidence),
            }
            for item in comparisons
        ],
        "problems": check(scenario, comparisons),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--replies", type=Path)
    mode.add_argument("--live", action="store_true")
    mode.add_argument("--print-prompts", action="store_true")
    parser.add_argument("--only")
    args = parser.parse_args()
    scenarios = json.loads(FIXTURES.read_text(encoding="utf-8"))
    if args.only:
        scenarios = [item for item in scenarios if item["id"] == args.only]
    if args.print_prompts:
        for item in scenarios:
            payload = {"posting_text": item["posting_text"], "records": item["records"]}
            print(item["id"], INSTRUCTION, json.dumps(payload, ensure_ascii=False), sep="\n")
        return 0
    if args.live:
        config = Settings()
        model = gemini.create_model(config, timeout=config.vertex_timeout_seconds)
        if model is None:
            parser.error("Set VERTEX_PROJECT, VERTEX_LOCATION and VERTEX_MODEL first")
        models = {item["id"]: model for item in scenarios}
    else:
        replies = json.loads(args.replies.read_text(encoding="utf-8"))
        models = {item["id"]: StoredReply(replies[item["id"]]) for item in scenarios}
    results = [evaluate(item, models[item["id"]]) for item in scenarios]
    print(json.dumps(results, ensure_ascii=False, indent=1))
    passed = sum(1 for item in results if item["valid"] and not item["problems"])
    seconds = [item["seconds"] for item in results]
    print(f"passed {passed}/{len(results)}, median {statistics.median(seconds):.2f}s")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
