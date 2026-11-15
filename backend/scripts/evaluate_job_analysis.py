"""Evaluate job analysis on synthetic scenarios, offline or against configured Gemini.

    uv run --frozen python -m scripts.evaluate_job_analysis --replies replies.json
    uv run --frozen python -m scripts.evaluate_job_analysis --live
    uv run --frozen python -m scripts.evaluate_job_analysis --live --representative --repeat 3

--replies reads stored model JSON objects keyed by scenario ID and calls nothing.
--live sends only the synthetic scenarios in tests/fixtures to the configured model.
--representative uses the representative postings fixture; --repeat runs each scenario N times
and reports pass rate, rejection causes, requirement recall, stability and latency percentiles.
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
REPRESENTATIVE = FIXTURES.with_name("job_analysis_representative.json")
# Claims the analysis must never make about any posting (see the analyzer instruction).
FORBIDDEN_CLAIMS = (
    "합격 가능성",
    "채용 가능성",
    "합격이 보장",
    "채용이 보장",
    "검증되었",
    "확실히 충족",
)


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
    for word in expect.get("not_supported_keywords", []):
        if any(c.status == "supported" for c in by_keyword(word)):
            problems.append(f"unsupported claim for {word}")
    for word in expect.get("requirement_keywords", []):
        if not by_keyword(word):
            problems.append(f"missing requirement: {word}")
    for word in expect.get("not_requirement_keywords", []):
        if by_keyword(word):
            problems.append(f"not a requirement: {word}")
    if expect.get("forbid_supported") and any(c.status == "supported" for c in comparisons):
        problems.append("fully supported claim")
    text = " ".join(c.requirement + " " + c.explanation for c in comparisons)
    forbidden = (*expect.get("forbidden_text", []), *FORBIDDEN_CLAIMS)
    problems += [f"forbidden text: {w}" for w in forbidden if w in text]
    return problems


def rejection_cause(error):
    text = str(error).lower()
    if "posting" in text or "quote" in text:
        return "posting_quote"
    if any(word in text for word in ("evidence", "citation", "personal")):
        return "personal_citation"
    if "classification" in text:
        return "classification"
    return "output_shape" if isinstance(error, ValueError) else type(error).__name__


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
            "cause": rejection_cause(error),
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
                "explanation": item.explanation,
            }
            for item in comparisons
        ],
        "problems": check(scenario, comparisons),
    }


def percentile(values, share):
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, round(share * (len(ordered) - 1)))]


def summarize(scenarios, runs):
    results = [item for run in runs for item in run]
    seconds = [item["seconds"] for item in results]
    expected = {s["id"]: s["expect"].get("requirement_keywords", []) for s in scenarios}
    found = missing = 0
    for item in results:
        lost = sum(p.startswith("missing requirement: ") for p in item["problems"])
        if item["valid"]:
            found += len(expected[item["id"]]) - lost
        missing += len(expected[item["id"]]) if not item["valid"] else lost
    by_id = {s["id"]: [item for item in results if item["id"] == s["id"]] for s in scenarios}
    statuses = {
        sid: len(
            {
                tuple(sorted((c["priority"], c["status"]) for c in i.get("comparisons", [])))
                if i["valid"]
                else ("rejected",)
                for i in items
            }
        )
        for sid, items in by_id.items()
    }
    causes = {}
    for item in results:
        if not item["valid"]:
            causes[item["cause"]] = causes.get(item["cause"], 0) + 1
    return {
        "runs": len(runs),
        "calls": len(results),
        "passed": sum(1 for item in results if item["valid"] and not item["problems"]),
        "rejected": sum(1 for item in results if not item["valid"]),
        "rejection_causes": causes,
        "requirement_recall": round(found / (found + missing), 3) if found + missing else None,
        "scenarios_with_stable_statuses": sum(1 for count in statuses.values() if count == 1),
        "scenarios": len(scenarios),
        "seconds": {
            "p50": round(statistics.median(seconds), 2),
            "p95": round(percentile(seconds, 0.95), 2),
            "max": round(max(seconds), 2),
        },
        "problems": {
            sid: sorted({p for i in items for p in i["problems"]})
            for sid, items in by_id.items()
            if any(i["problems"] for i in items)
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--replies", type=Path)
    mode.add_argument("--live", action="store_true")
    mode.add_argument("--print-prompts", action="store_true")
    parser.add_argument("--only")
    parser.add_argument("--representative", action="store_true")
    parser.add_argument("--repeat", type=int, default=1)
    parser.add_argument("--output", type=Path, help="write every run's results as JSON")
    args = parser.parse_args()
    if not 1 <= args.repeat <= 10:
        parser.error("--repeat must be between 1 and 10")
    fixtures = REPRESENTATIVE if args.representative else FIXTURES
    scenarios = json.loads(fixtures.read_text(encoding="utf-8"))
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
    runs = [[evaluate(item, models[item["id"]]) for item in scenarios] for _ in range(args.repeat)]
    if args.output:
        args.output.write_text(json.dumps(runs, ensure_ascii=False, indent=1), encoding="utf-8")
    elif args.repeat == 1:
        print(json.dumps(runs[0], ensure_ascii=False, indent=1))
    summary = summarize(scenarios, runs)
    print(json.dumps(summary, ensure_ascii=False, indent=1))
    print(
        f"passed {summary['passed']}/{summary['calls']}, "
        f"median {summary['seconds']['p50']:.2f}s, p95 {summary['seconds']['p95']:.2f}s"
    )
    return 0 if summary["passed"] == summary["calls"] else 1


if __name__ == "__main__":
    sys.exit(main())
