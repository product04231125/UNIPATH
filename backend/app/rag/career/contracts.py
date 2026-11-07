"""Internal contracts; these do not replace backend API/ownership validation."""

from dataclasses import dataclass, field
from datetime import datetime
from urllib.parse import urlsplit
from uuid import UUID

KINDS = {"course", "activity", "experience", "credential", "achievement"}


class NotConfigured(Exception):
    pass


@dataclass(frozen=True)
class SearchQuery:
    keyword: str
    region_label: str
    nationwide: bool = False
    region_codes: dict[str, str] = field(default_factory=dict)
    limit: int = 10

    def __post_init__(self):
        if not isinstance(self.keyword, str) or not 1 <= len(self.keyword.strip()) <= 80:
            raise ValueError("Select a job keyword")
        if not isinstance(self.region_label, str) or not self.region_label.strip():
            raise ValueError("Select a region explicitly")
        if (
            type(self.nationwide) is not bool
            or type(self.limit) is not int
            or not 1 <= self.limit <= 20
        ):
            raise ValueError("Invalid search bounds")
        if self.nationwide and self.region_codes:
            raise ValueError("Nationwide search cannot have region codes")

    def region(self, provider):
        import re

        if self.nationwide:
            return None
        code = self.region_codes.get(provider)
        if not isinstance(code, str) or not re.fullmatch(r"\d{2,6}", code):
            raise ValueError("Provider region mapping required; never silently search nationwide")
        return code


@dataclass(frozen=True)
class Posting:
    source: str
    source_id: str
    title: str
    company: str
    location: str
    url: str
    text: str
    fetched_at: str
    closing_label: str = "확인 필요"
    expires_at: str | None = None
    active: bool | None = None
    text_scope: str = "metadata_only"

    def __post_init__(self):
        if self.source not in {"saramin", "work24", "jobkorea", "manual"}:
            raise ValueError("Unknown posting source")
        if (
            not self.source_id
            or not self.title
            or not self.company
            or not 1 <= len(self.text) <= 20000
        ):
            raise ValueError("Invalid posting")
        url = urlsplit(self.url)
        if url.scheme not in {"http", "https"} or not url.hostname or url.username or url.password:
            raise ValueError("Invalid posting link")
        allowed = {
            "saramin": "saramin.co.kr",
            "work24": "work24.go.kr",
            "jobkorea": "jobkorea.co.kr",
        }
        if self.source in allowed:
            hosts = [allowed[self.source]] + (["work.go.kr"] if self.source == "work24" else [])
            if not any(url.hostname == host or url.hostname.endswith("." + host) for host in hosts):
                raise ValueError("Unexpected posting link host")
        if self.text_scope not in {"metadata_only", "full_text"}:
            raise ValueError("Invalid text scope")
        for value in (self.fetched_at, self.expires_at):
            if value is not None and datetime.fromisoformat(value).tzinfo is None:
                raise ValueError("Use timezone-aware posting dates")
        if self.active is not None and type(self.active) is not bool:
            raise ValueError("Invalid active flag")


def selected_records(context):
    data = context.model_dump(mode="json") if hasattr(context, "model_dump") else context
    values = data["records"]
    if not isinstance(values, list) or not 1 <= len(values) <= 20:
        raise ValueError("Select 1..20 records")
    records, seen = [], set()
    for value in values:
        key = (value["kind"], str(UUID(value["record_id"])))
        if key in seen or key[0] not in KINDS:
            raise ValueError("Invalid or duplicate personal record")
        if type(value["version"]) is not int or value["version"] < 1:
            raise ValueError("Invalid record version")
        if not isinstance(value["text"], str) or not 1 <= len(value["text"]) <= 8000:
            raise ValueError("Invalid record text")
        seen.add(key)
        records.append(
            {
                "kind": key[0],
                "record_id": key[1],
                "version": value["version"],
                "text": value["text"],
                "truncated": value.get("truncated", False),
            }
        )
    return records
