"""Offline review manifest. Records human decisions, never authenticates a reviewer."""

import argparse
import hashlib
import json
from copy import deepcopy
from datetime import datetime
from pathlib import Path
from uuid import UUID, uuid5

from ..school.retriever import approved, load_chunks, valid_source_url, validate_chunks
from .__main__ import write_atomic


def digest(value: object) -> str:
    return hashlib.sha256(
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


def review_template(chunks: list[dict]) -> dict:
    validate_chunks(chunks)
    return {
        "schema_version": "1.0",
        "corpus_sha256": digest(chunks),
        "reviewer": "",
        "reviewed_at": "",
        "entries": [
            {
                "chunk_id": c["chunk_id"],
                "document_hash": c["document_hash"],
                "content_hash": c["content_hash"],
                "decision": "pending",
                "source_url": c.get("source_url"),
                "admission_years": None,
                "tracks": None,
                "resolved_warnings": [],
                "review_note": "",
            }
            for c in chunks
        ],
    }


def apply_review(chunks: list[dict], review: dict) -> list[dict]:
    validate_chunks(chunks)
    if review.get("schema_version") != "1.0" or review.get("corpus_sha256") != digest(chunks):
        raise ValueError("Review does not match this exact corpus; review the new extraction")
    if not isinstance(review.get("reviewer"), str) or not review["reviewer"].strip():
        raise ValueError("A reviewer is required")
    date = datetime.fromisoformat(review.get("reviewed_at", ""))
    if date.tzinfo is None or date > datetime.now(date.tzinfo):
        raise ValueError("reviewed_at needs a timezone and must not be in the future")
    entries = review.get("entries")
    if not isinstance(entries, list) or len(entries) != len(chunks):
        raise ValueError("Review must cover every chunk")
    lookup = {e["chunk_id"]: e for e in entries}
    if len(lookup) != len(entries) or set(lookup) != {c["chunk_id"] for c in chunks}:
        raise ValueError("Missing, duplicate, or unknown review chunk")
    result = []
    for original in chunks:
        item = deepcopy(original)
        entry = lookup[item["chunk_id"]]
        if any(entry.get(k) != item[k] for k in ("document_hash", "content_hash")):
            raise ValueError("Reviewed source/content hash changed")
        if entry.get("decision") not in ("approved", "rejected", "pending"):
            raise ValueError("Invalid review decision")
        item.update(
            eligible_for_official_answers=False,
            review_status="needs_review",
            applicability_status="unverified",
        )
        if entry["decision"] == "approved":
            years, tracks = entry.get("admission_years"), entry.get("tracks")
            if (
                not isinstance(years, list)
                or not years
                or any(type(y) is not int or not 1000 <= y <= 9999 for y in years)
            ):
                raise ValueError("Approval requires explicit admission years")
            if (
                not isinstance(tracks, list)
                or not tracks
                or any(not isinstance(t, str) or not t.strip() for t in tracks)
            ):
                raise ValueError("Approval requires explicit tracks")
            if not valid_source_url(entry.get("source_url")):
                raise ValueError("Approval requires an HTTP(S) source URL")
            if not isinstance(entry.get("review_note"), str) or not entry["review_note"].strip():
                raise ValueError("Approval requires a note about scope, conditions and exceptions")
            resolved = entry.get("resolved_warnings", [])
            if not isinstance(resolved, list) or any(not isinstance(w, str) for w in resolved):
                raise ValueError("Invalid resolved warnings")
            if not set(resolved).issubset(item.get("warnings", [])):
                raise ValueError("Cannot resolve an unknown warning")
            item.update(
                source_url=entry["source_url"],
                admission_years=sorted(set(years)),
                track=None,
                tracks=sorted(set(tracks)),
                review_status="approved",
                applicability_status="verified",
                eligible_for_official_answers=True,
                warnings=[w for w in item.get("warnings", []) if w not in resolved],
            )
            if not approved(item):
                raise ValueError("Extraction warnings still block approval")
        elif entry["decision"] == "rejected":
            item["review_status"] = "rejected"
        item["review_record"] = {
            "reviewer": review["reviewer"],
            "reviewed_at": review["reviewed_at"],
            "input_chunk_id": original["chunk_id"],
            "manifest_sha256": digest(review),
            "decision": entry["decision"],
            "note": entry.get("review_note", ""),
            "resolved_warnings": entry.get("resolved_warnings", []),
        }
        # A changed approval/scope gets a new identity; never reuse cached citations.
        item["chunk_id"] = str(uuid5(UUID(original["chunk_id"]), digest(item)))
        result.append(item)
    validate_chunks(result)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare/apply an offline human review manifest")
    parser.add_argument("operation", choices=["template", "apply"])
    parser.add_argument("--chunks", type=Path, required=True)
    parser.add_argument("--review", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.output.resolve() in {p.resolve() for p in (args.chunks, args.review) if p}:
            raise ValueError("Output must not overwrite an input")
        chunks = load_chunks(args.chunks)
        if args.operation == "template":
            content = json.dumps(review_template(chunks), ensure_ascii=False, indent=2) + "\n"
        else:
            if not args.review:
                raise ValueError("--review is required for apply")
            reviewed = apply_review(chunks, json.loads(args.review.read_text(encoding="utf-8")))
            content = "".join(json.dumps(c, ensure_ascii=False) + "\n" for c in reviewed)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        write_atomic(args.output, content)
    except (ValueError, OSError, TypeError, KeyError, AttributeError):
        parser.exit(1, "Review failed: check the manifest, source hashes and required fields.\n")
    print(f"Written: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
