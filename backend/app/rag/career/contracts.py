"""Internal contracts; these do not replace backend API/ownership validation."""

import re
from dataclasses import dataclass, field
from datetime import date, datetime
from urllib.parse import urlsplit
from uuid import UUID
from zoneinfo import ZoneInfo

KINDS = {"course", "activity", "experience", "credential", "achievement"}

# Appended to every instruction that reads the student's records, with "today" in the payload.
# Status fields are free text the student typed, so the model reads them; code never guesses
# from their wording.
RECORD_STATUS_RULE = """
Records describe plans as well as finished work; today is given as YYYY-MM-DD. A record is not yet
done when a status line (status_label, thesis_status_label, completion) says it is planned, applied
for, in progress, being prepared or only partly passed (for example 참여 예정, 지원 예정, 진행 중,
준비 중, 수강 중, 작성 중, 필기 합격·실기 준비 중), or when its started_on or earned_on is after
today. Never present such a record as finished work, a held credential or a completed course, and
never cite it as evidence that a requirement is met (supported). Cite it only for what it says is
already done, or mention it as a plan or a step in progress."""


def local_today() -> date:
    """Today in Korea: the date records, plans and schedules are judged against."""
    return datetime.now(ZoneInfo("Asia/Seoul")).date()


def record_field(record, key):
    """One field of an assembled record text (`key: value` lines, see personalization.context)."""
    prefix = f"{key}: "
    values = [
        line[len(prefix) :].strip()
        for line in str(record.get("text") or "").splitlines()
        if line.startswith(prefix)
    ]
    return values[-1] if values else ""


class NotConfigured(Exception):
    pass


class ProviderFailure(RuntimeError):
    """A failed provider call. reason is a fixed code: never a body, URL or credential."""

    def __init__(self, message, reason):
        super().__init__(message)
        self.reason = reason


class AnalysisRejected(ValueError):
    """Model output that failed validation. reason is a fixed code, never the output."""

    def __init__(self, message, reason):
        super().__init__(message)
        self.reason = reason


# Schema keys our code looks up in model output; anything else is never echoed.
SCHEMA_KEY = re.compile(r"[a-z][a-z0-9_]{0,39}")


def failure_reason(error):
    """Safe code for logs and responses: which step failed, without any content."""
    if isinstance(error, (ProviderFailure, AnalysisRejected)):
        return error.reason
    if (
        isinstance(error, KeyError)
        and len(error.args) == 1
        and isinstance(error.args[0], str)
        and SCHEMA_KEY.fullmatch(error.args[0])
    ):
        # The model left out a field our code reads, e.g. output_missing_personal_evidence.
        return "output_missing_" + error.args[0]
    if isinstance(error, (KeyError, TypeError, IndexError, ValueError)):
        # Missing keys or wrong types in model output, or other invalid data.
        return "output_shape"
    return "unexpected_" + type(error).__name__


@dataclass(frozen=True)
class SearchQuery:
    keyword: str
    region_label: str
    nationwide: bool = False
    region_codes: dict[str, str] = field(default_factory=dict)
    limit: int = 10
    # Work24 occupation codes (categories.py). With a category the detail keyword is optional.
    occupation_codes: tuple[str, ...] = ()

    def __post_init__(self):
        from .categories import validate_codes
        from .search_terms import search_terms

        validate_codes(self.occupation_codes)
        if not isinstance(self.keyword, str) or len(self.keyword.strip()) > 80:
            raise ValueError("Select a job keyword")
        if self.keyword.strip():
            search_terms(self.keyword)
        elif not self.occupation_codes:
            raise ValueError("Select a job keyword or category")
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
        if not isinstance(code, str) or not re.fullmatch(r"\d{2,6}(,\d{2,6}){0,15}", code):
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
        if self.source not in {"saramin", "work24", "jobkorea", "greenhouse", "manual"}:
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
        # Greenhouse may return a company-owned application URL; we never fetch it.
        if self.source == "greenhouse" and url.scheme != "https":
            raise ValueError("Greenhouse posting links must use HTTPS")
        if self.source in allowed:
            hosts = [allowed[self.source]] + (["work.go.kr"] if self.source == "work24" else [])
            if not any(url.hostname == host or url.hostname.endswith("." + host) for host in hosts):
                raise ValueError("Unexpected posting link host")
        if self.text_scope not in {"metadata_only", "full_text", "excerpt"}:
            raise ValueError("Invalid text scope")
        for value in (self.fetched_at, self.expires_at):
            if value is not None and datetime.fromisoformat(value).tzinfo is None:
                raise ValueError("Use timezone-aware posting dates")
        if self.active is not None and type(self.active) is not bool:
            raise ValueError("Invalid active flag")


# Saved records (200) plus up to 20 uploaded document chunks in a recommendation request.
MAX_RECORDS = 220
# Record text sent to the model in one comparison. Typical records are a few hundred characters,
# so this keeps every record for nearly all students while bounding latency and cost.
RECORD_TEXT_BUDGET = 60_000
TERM = re.compile(r"[a-z0-9가-힣+#.]{2,}")


def fit_records(records, posting_text, budget=RECORD_TEXT_BUDGET):
    """Keep every record that fits. Past the budget, prefer records sharing more posting terms.

    Selection is local and deterministic; kept records stay in their original order.
    """
    if sum(len(record["text"]) for record in records) <= budget:
        return records
    terms = set(TERM.findall(posting_text.casefold()))

    def overlap(index):
        return len(terms & set(TERM.findall(records[index]["text"].casefold())))

    kept, used = set(), 0
    for index in sorted(range(len(records)), key=lambda i: -overlap(i)):
        size = len(records[index]["text"])
        if used + size <= budget:
            kept.add(index)
            used += size
    return [record for index, record in enumerate(records) if index in kept]


def selected_records(context):
    data = context.model_dump(mode="json") if hasattr(context, "model_dump") else context
    values = data["records"]
    if not isinstance(values, list) or not 1 <= len(values) <= MAX_RECORDS:
        raise ValueError(f"Select 1..{MAX_RECORDS} records")
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
