"""Collected guidance bundles. The edition is a content hash, so any data refresh changes it."""

import json
from functools import lru_cache
from hashlib import sha256
from pathlib import Path

from app.rag.guidance.service import catalog

DATA = Path(__file__).resolve().parent / "data"
BUNDLE_ID = "kduniv-academic-guidance"


@lru_cache(maxsize=1)
def bundles():
    digest, fetched = sha256(), []
    for path in sorted(DATA.glob("*.json")):
        raw = path.read_bytes()
        digest.update(path.name.encode() + b"\0" + raw)
        value = json.loads(raw).get("fetched_at")
        if value:
            fetched.append(value)
    return {
        BUNDLE_ID: {
            "bundle_id": BUNDLE_ID,
            "name": "경동대학교 학사 안내 수집 자료",
            "source_school": "경동대학교",
            "official_url": "https://www.kduniv.ac.kr",
            "schema_version": catalog()["schema_version"],
            "edition": digest.hexdigest()[:16],
            "fetched_at": max(fetched),
            "availability": "available",
        }
    }
