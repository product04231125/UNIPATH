"""Compile human-authored QA worksheets into saved-answer regression cases, offline."""

import argparse
import json
import re
from pathlib import Path

from ..school.contracts import SchoolContext
from ..school.retriever import load_chunks, validate_chunks
from .answers import indexed
from .evidence import check_evidence


def literal_pattern(value: str) -> str:
    """Ignore spacing, but don't accept 36 as part of 136 or 36.5."""
    if not isinstance(value, str) or not value.strip():
        raise ValueError("Expected a nonempty QA phrase")
    tokens = re.findall(r"\d+(?:\.\d+)?|[^\d\s]", value)
    return r"\s*".join(
        r"(?<![\d.])" + re.escape(token) + r"(?![\d.])" if token[0].isdigit() else re.escape(token)
        for token in tokens
    )


def compile_cases(rows: list[dict], chunks: list[dict]) -> list[dict]:
    validate_chunks(chunks)
    indexed(rows)
    cases = []
    for row in rows:
        if row.get("reviewed") is not True or row.get("suite") not in ("development", "holdout"):
            raise ValueError("Explicit QA review and suite are required")
        for key in ("question", "author", "reviewer", "expected_reason"):
            if not isinstance(row.get(key), str) or not row[key].strip():
                raise ValueError("Missing QA question, author, reviewer or reason")
        if row["suite"] == "holdout" and row["author"].strip() == row["reviewer"].strip():
            raise ValueError("Holdout QA requires a separate reviewer")
        SchoolContext(**row["context"])
        status = row["expected_status"]
        if status not in ("grounded", "insufficient_evidence", "needs_user_input", "failed"):
            raise ValueError("Invalid expected status")
        evidence = row.get("evidence", [])
        if not isinstance(evidence, list) or (status == "grounded" and not evidence):
            raise ValueError("Grounded QA requires reference evidence")
        versions = row.get("source_versions", {})
        for ref in evidence:
            selected = [c for c in chunks if c["document_id"] == ref["document_id"]]
            if (
                not isinstance(ref.get("quote"), str)
                or not ref["quote"].strip()
                or type(ref.get("page")) is not int
                or not selected
                or any(c["document_hash"] != versions.get(c["document_id"]) for c in selected)
                or not check_evidence(selected, [ref], [])["passed"]
            ):
                raise ValueError("QA source version/page/quote does not match corpus")
        missing = row.get("missing_fields", [])
        if not isinstance(missing, list) or any(not isinstance(v, str) for v in missing):
            raise ValueError("Invalid missing fields")
        patterns = {}
        for key, target in [
            ("required_phrases", "required_patterns"),
            ("forbidden_phrases", "forbidden_patterns"),
        ]:
            values = row.get(key, [])
            if not isinstance(values, list):
                raise ValueError("QA phrases must be lists")
            patterns[target] = [literal_pattern(v) for v in values]
        if status == "grounded" and not patterns["required_patterns"]:
            raise ValueError("Record the expected answer conditions before evaluation")
        cases.append(
            {
                "id": row["id"],
                "question": row["question"],
                "context": row["context"],
                "expected_status": status,
                "expected_reason": row["expected_reason"],
                "missing_fields": missing,
                "source_versions": versions,
                "evidence": evidence,
                "qa_provenance": {k: row[k] for k in ("suite", "author", "reviewer", "reviewed")},
                **patterns,
            }
        )
    return cases


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worksheet", type=Path, required=True)
    parser.add_argument("--chunks", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        rows = json.loads(args.worksheet.read_text(encoding="utf-8"))
        cases = compile_cases(rows, load_chunks(args.chunks))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("x", encoding="utf-8") as stream:
            for case in cases:
                stream.write(json.dumps(case, ensure_ascii=False) + "\n")
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        parser.exit(2, "Invalid QA worksheet/corpus or existing output; no model was called.\n")


if __name__ == "__main__":
    main()
