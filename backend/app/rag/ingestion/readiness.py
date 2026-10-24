"""Read-only corpus review inventory; never grants official approval."""

import argparse
import json
from collections import defaultdict
from pathlib import Path

from ..school.retriever import approved, load_chunks, valid_source_url, validate_chunks
from .__main__ import write_atomic


def inspect_corpus(chunks: list[dict]) -> dict:
    validate_chunks(chunks)
    documents = defaultdict(list)
    for chunk in chunks:
        documents[chunk["document_id"]].append(chunk)
    results = []
    for document_id, group in sorted(documents.items()):
        expected = group[0]["document_page_count"]
        present = {c["page"] for c in group}
        missing = sorted(set(range(1, expected + 1)) - present)
        issues = []
        for chunk in sorted(group, key=lambda c: (c["page"], c.get("page_part_index", 0))):
            blockers = []
            for condition, code in (
                (not valid_source_url(chunk.get("source_url")), "source_url_missing_or_invalid"),
                (chunk.get("review_status") != "approved", "review_not_approved"),
                (chunk.get("applicability_status") != "verified", "applicability_not_verified"),
                (chunk.get("eligible_for_official_answers") is not True, "official_use_disabled"),
                (not chunk.get("admission_years"), "admission_years_unknown"),
                (not (chunk.get("track") or chunk.get("tracks")), "tracks_unknown"),
            ):
                if condition:
                    blockers.append(code)
            issues.append(
                {
                    "chunk_id": chunk["chunk_id"],
                    "page": chunk["page"],
                    "blockers": blockers,
                    "extraction_warnings": chunk.get("warnings", []),
                    "has_local_review_record": bool(chunk.get("review_record")),
                    "passes_retriever_approval_flags": approved(chunk),
                }
            )
        results.append(
            {
                "document_id": document_id,
                "title": group[0]["title"],
                "document_hash": group[0]["document_hash"],
                "chunk_count": len(group),
                "missing_pages": missing,
                "chunks": issues,
                "ready_for_scoped_local_test": not missing
                and all(not c["blockers"] and c["passes_retriever_approval_flags"] for c in issues),
            }
        )
    return {
        "schema_version": "1.0",
        "scope": "local_corpus_inventory_only",
        "does_not_authorize_production": True,
        "document_count": len(results),
        "chunk_count": len(chunks),
        "ready_for_scoped_local_test": bool(results)
        and all(d["ready_for_scoped_local_test"] for d in results),
        "documents": results,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Read-only RAG corpus readiness inventory")
    parser.add_argument("--chunks", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.chunks.resolve() == args.output.resolve():
            raise ValueError("Output must not overwrite the corpus")
        report = inspect_corpus(load_chunks(args.chunks))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        write_atomic(args.output, json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    except (ValueError, OSError, KeyError, TypeError):
        parser.exit(2, "Cannot inspect corpus; check input integrity and output path.\n")
    print(json.dumps({k: v for k, v in report.items() if k != "documents"}, ensure_ascii=False))
    return 0 if report["ready_for_scoped_local_test"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
