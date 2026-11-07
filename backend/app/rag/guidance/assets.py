"""Internal resolver for collected public PDFs/page images; not an HTTP endpoint."""

import hashlib
import json
import re
from functools import lru_cache
from pathlib import Path

from .collect import DATA


@lru_cache(maxsize=1)
def asset_index():
    data = json.loads((DATA / "university.json").read_text(encoding="utf-8"))
    items = {}
    attachments = [a for r in data["regulations"] for a in r["attachments"]]
    attachments += [a for p in data["scholarships"] for a in p["attachments"]]
    for attachment in attachments:
        items[attachment["sha256"]] = attachment["source_file"]
        for page in attachment["pages"]:
            if page.get("image"):
                items[page["image"]["sha256"]] = page["image"]["source_file"]
    return items


def resolve_asset(asset_id: str) -> Path:
    """Adapter may serve this verified file; never accepts client file paths or source URLs."""
    if not isinstance(asset_id, str) or not re.fullmatch(r"[0-9a-f]{64}", asset_id):
        raise ValueError("Invalid asset ID")
    relative = asset_index().get(asset_id)
    if relative is None:
        raise ValueError("Unknown asset")
    path = (DATA / relative).resolve()
    if not path.is_relative_to(DATA.resolve()) or path.suffix not in {".pdf", ".jpg"}:
        raise ValueError("Invalid asset path")
    if hashlib.sha256(path.read_bytes()).hexdigest() != asset_id:
        raise ValueError("Asset integrity mismatch")
    return path
