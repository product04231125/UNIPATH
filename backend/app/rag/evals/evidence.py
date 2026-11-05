"""Exact evidence-fragment checks, independent of ranking/model providers."""

import re


def compact(text: str) -> str:
    return re.sub(r"\s+", "", text)


def contains_reference(item: dict, reference: dict) -> bool:
    return (
        item.get("document_id") == reference["document_id"]
        and item.get("page") == reference["page"]
        and compact(reference["quote"]) in compact(item.get("content", item.get("excerpt", "")))
    )


def check_evidence(items: list[dict], references: list[dict], forbidden: list[dict]) -> dict:
    missing = [
        i
        for i, ref in enumerate(references)
        if not any(contains_reference(item, ref) for item in items)
    ]
    leaked = [
        i for i, ref in enumerate(forbidden) if any(contains_reference(item, ref) for item in items)
    ]
    return {
        "passed": not missing and not leaked,
        "missing_reference_indices": missing,
        "forbidden_reference_indices": leaked,
    }
