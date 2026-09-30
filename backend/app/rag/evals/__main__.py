"""Evaluate expected source pages and orchestration behavior independently."""

import argparse
import json
import re
from pathlib import Path

from ..ingestion.__main__ import write_atomic
from ..school.__main__ import DEFAULT_CHUNKS
from ..school.contracts import SchoolContext
from ..school.retriever import SchoolRetriever, load_chunks
from ..school.service import SchoolRagService

DEFAULT_CASES = Path(__file__).with_name("questions.jsonl")
SOURCE_VERSIONS = Path(__file__).with_name("source_versions.json")


def compact(text: str) -> str:
    return re.sub(r"\s+", "", text)


def evaluate(chunks_path: Path, cases_path: Path, *, top_k: int = 3) -> dict:
    chunks = load_chunks(chunks_path)
    sources = json.loads(SOURCE_VERSIONS.read_text(encoding="utf-8"))
    actual = {c["document_id"]: c["document_hash"] for c in chunks}
    if actual != sources:
        raise ValueError("Evaluation source versions changed; review expected evidence first")
    pages = {(c["document_id"], c["page"]): c for c in chunks}
    cases = [
        json.loads(line)
        for line in cases_path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    if not cases or len({case["id"] for case in cases}) != len(cases):
        raise ValueError("Evaluation needs nonempty cases with unique IDs")
    retriever = SchoolRetriever(chunks)
    service = SchoolRagService(retriever)
    results = []
    recalls = []
    reciprocals = []
    hit_flags = []
    for case in cases:
        context = SchoolContext(**case.get("context", {}))
        if case["kind"] == "retrieval":
            expected = {(ref["document_id"], ref["page"]) for ref in case["evidence"]}
            for ref in case["evidence"]:
                page = pages.get((ref["document_id"], ref["page"]))
                if page is None or compact(ref["quote"]) not in compact(page["content"]):
                    raise ValueError(
                        f"Expected evidence no longer matches the source: {case['id']}"
                    )
            hits = retriever.search(
                case["question"], context, top_k=top_k, preview=case.get("preview", True)
            )
            found = [(hit.document_id, hit.page) for hit in hits]
            matched = expected.intersection(found)
            recall = len(matched) / len(expected) if expected else float(not found)
            reciprocal = next(
                (1 / rank for rank, ref in enumerate(found, 1) if ref in expected), 0.0
            )
            if expected:
                recalls.append(recall)
                reciprocals.append(reciprocal)
                hit_flags.append(bool(matched))
            results.append(
                {
                    "id": case["id"],
                    "kind": "retrieval",
                    "passed": recall == 1.0,
                    "recall_at_k": recall,
                    "reciprocal_rank": reciprocal,
                    "found": [{"document_id": doc, "page": page} for doc, page in found],
                }
            )
        elif case["kind"] == "behavior":
            result = service.query(case["question"], context, preview=case.get("preview", False))
            passed = (
                result.status == case["expected_status"]
                and result.reason == case["expected_reason"]
                and set(result.missing_fields) == set(case.get("missing_fields", []))
                and bool(result.candidates) == case.get("has_candidates", False)
                and not result.citations
                and result.answer is None
            )
            results.append(
                {
                    "id": case["id"],
                    "kind": "behavior",
                    "passed": passed,
                    "status": result.status,
                    "reason": result.reason,
                }
            )
        else:
            raise ValueError(f"Unknown case kind: {case['kind']}")
    behaviors = [result for result in results if result["kind"] == "behavior"]
    return {
        "suite": "development_source_retrieval_and_policy_v1",
        "not_an_independent_accuracy_estimate": True,
        "ranking": "bm25_korean_ngrams",
        "top_k": top_k,
        "case_count": len(results),
        "passed_count": sum(result["passed"] for result in results),
        "retrieval_hit_at_k": sum(hit_flags) / len(hit_flags) if hit_flags else None,
        "retrieval_mean_recall_at_k": sum(recalls) / len(recalls) if recalls else None,
        "retrieval_mrr_at_k": sum(reciprocals) / len(reciprocals) if reciprocals else None,
        "behavior_pass_rate": sum(r["passed"] for r in behaviors) / len(behaviors)
        if behaviors
        else None,
        "results": results,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate the local RAG development suite")
    parser.add_argument("--chunks", type=Path, default=DEFAULT_CHUNKS)
    parser.add_argument("--cases", type=Path, default=DEFAULT_CASES)
    parser.add_argument("--top-k", type=int, default=3)
    parser.add_argument("--output", type=Path, default=DEFAULT_CHUNKS.with_name("evaluation.json"))
    args = parser.parse_args()
    try:
        report = evaluate(args.chunks, args.cases, top_k=args.top_k)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        write_atomic(args.output, json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    except (ValueError, OSError, KeyError, TypeError) as exc:
        parser.exit(2, f"Evaluation input error: {exc}\n")
    print(
        json.dumps(
            {key: value for key, value in report.items() if key != "results"},
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0 if report["passed_count"] == report["case_count"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
