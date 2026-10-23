"""Offline scoring of saved QueryResult/API responses. Never invokes a model."""

import argparse
import json
import re
from pathlib import Path

from ..ingestion.__main__ import write_atomic
from ..school.contracts import SchoolContext
from ..school.retriever import approved, load_chunks, matches_scope, validate_chunks
from .evidence import check_evidence


def indexed(rows: list[dict]) -> dict:
    if not rows or any(not isinstance(r.get("id"), str) or not r["id"].strip() for r in rows):
        raise ValueError("Cases and predictions require nonempty IDs")
    result = {r["id"]: r for r in rows}
    if len(result) != len(rows):
        raise ValueError("Duplicate evaluation ID")
    return result


def evaluate_answers(cases: list[dict], predictions: list[dict], chunks: list[dict]) -> dict:
    validate_chunks(chunks)
    expected, actual = indexed(cases), indexed(predictions)
    if expected.keys() != actual.keys():
        raise ValueError("Missing or unexpected prediction IDs")
    corpus = {c["chunk_id"]: c for c in chunks}
    results = []
    for case_id, case in expected.items():
        context = SchoolContext(**case.get("context", {}))
        status = case["expected_status"]
        if status not in ("grounded", "insufficient_evidence", "needs_user_input", "failed"):
            raise ValueError("Unknown expected status")
        references = case.get("evidence", [])
        if status == "grounded" and not references:
            raise ValueError("Grounded cases require expected evidence")
        versions = case.get("source_versions", {})
        for ref in references:
            if not isinstance(ref.get("quote"), str) or not ref["quote"].strip():
                raise ValueError("Expected evidence quote must not be empty")
            matching = [c for c in chunks if c["document_id"] == ref["document_id"]]
            if (
                not matching
                or any(c["document_hash"] != versions.get(ref["document_id"]) for c in matching)
                or not check_evidence(matching, [ref], [])["passed"]
            ):
                raise ValueError("Expected source hash or evidence does not match corpus")
        result = actual[case_id].get("result", {})
        if not isinstance(result, dict):
            raise ValueError("Prediction result must be an object")
        failures = []
        if result.get("status") != status:
            failures.append("status_mismatch")
        if result.get("reason") != case["expected_reason"]:
            failures.append("reason_mismatch")
        missing = result.get("missing_fields")
        if (
            not isinstance(missing, list)
            or any(not isinstance(x, str) for x in missing)
            or sorted(missing) != sorted(case.get("missing_fields", []))
        ):
            failures.append("missing_fields_mismatch")
        answer, citations = result.get("answer"), result.get("citations")
        if status != "grounded":
            if answer is not None or citations != []:
                failures.append("unconfirmed_answer_or_citations")
        else:
            if not isinstance(answer, str) or not answer.strip():
                failures.append("empty_answer")
            if not isinstance(citations, list) or not citations:
                failures.append("missing_citations")
                citations = []
            verified = []
            for citation in citations:
                key = citation.get("chunk_id") if isinstance(citation, dict) else None
                original = corpus.get(key) if isinstance(key, str) else None
                if original is None:
                    failures.append("unknown_citation")
                    continue
                if not approved(original) or not matches_scope(original, context, preview=False):
                    failures.append("unapproved_or_wrong_scope_citation")
                if (
                    any(
                        citation.get(k) != original[k]
                        for k in ("document_id", "title", "source_url", "page")
                    )
                    or citation.get("excerpt") != original["content"]
                ):
                    failures.append("citation_metadata_mismatch")
                verified.append(original)
            if not check_evidence(verified, references, [])["passed"]:
                failures.append("expected_evidence_not_cited")
        # These are reviewer-authored regression patterns, not semantic truth judgments.
        for key, should_match in (("required_patterns", True), ("forbidden_patterns", False)):
            patterns = case.get(key, [])
            if not isinstance(patterns, list) or any(
                not isinstance(p, str) or not p for p in patterns
            ):
                raise ValueError("Answer patterns must be nonempty regex strings")
            for index, pattern in enumerate(patterns):
                matched = re.search(pattern, answer if isinstance(answer, str) else "") is not None
                if matched != should_match:
                    failures.append(f"{key}:{index}")
        results.append({"id": case_id, "passed": not failures, "failures": sorted(set(failures))})
    return {
        "suite": "saved_answer_regression_v1",
        "semantic_correctness_verified": False,
        "case_count": len(results),
        "passed_count": sum(r["passed"] for r in results),
        "results": results,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Score saved answers without model/API calls")
    for name in ("cases", "predictions", "chunks", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.output.resolve() in {
            p.resolve() for p in (args.cases, args.predictions, args.chunks)
        }:
            raise ValueError("Output must not overwrite inputs")
        cases, predictions = [
            [
                json.loads(line)
                for line in p.read_text(encoding="utf-8").splitlines()
                if line.strip()
            ]
            for p in (args.cases, args.predictions)
        ]
        report = evaluate_answers(cases, predictions, load_chunks(args.chunks))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        write_atomic(args.output, json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    except (OSError, ValueError, KeyError, TypeError, AttributeError, re.error):
        parser.exit(2, "Invalid answer evaluation input; check IDs, source hashes and patterns.\n")
    print(json.dumps({k: v for k, v in report.items() if k != "results"}))
    return 0 if report["passed_count"] == report["case_count"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
