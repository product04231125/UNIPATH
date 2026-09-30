"""RAG-local contracts. No FastAPI, ORM, or provider dependency."""

from dataclasses import asdict, dataclass, field
from enum import StrEnum
from typing import Protocol


class AnswerStatus(StrEnum):
    GROUNDED = "grounded"
    INSUFFICIENT_EVIDENCE = "insufficient_evidence"
    NEEDS_USER_INPUT = "needs_user_input"
    FAILED = "failed"


@dataclass(frozen=True)
class SchoolContext:
    institution: str | None = None
    department: str | None = None
    admission_year: int | None = None
    track: str | None = None

    def __post_init__(self):
        for key in ("institution", "department", "track"):
            value = getattr(self, key)
            if value is not None and (not isinstance(value, str) or not value.strip()):
                raise ValueError(f"{key} must be a nonempty string or None")
        if self.admission_year is not None and (
            type(self.admission_year) is not int or not 1000 <= self.admission_year <= 9999
        ):
            raise ValueError("admission_year must be a four-digit integer or None")


@dataclass(frozen=True)
class SearchHit:
    chunk_id: str
    document_id: str
    title: str
    source_file: str
    source_url: str | None
    page: int
    content: str
    score: float
    review_status: str
    applicability_status: str
    related_pages: list[int]

    def as_dict(self) -> dict:
        return asdict(self)


@dataclass(frozen=True)
class GeneratedAnswer:
    answer: str
    citation_ids: list[str]
    insufficient_evidence: bool = False


@dataclass(frozen=True)
class GroundingRequest:
    system_instruction: str
    question: str
    evidence: list[dict]
    context: dict


class AnswerGenerator(Protocol):
    def generate(self, request: GroundingRequest) -> GeneratedAnswer:
        """Return structured output; network/PII policy belongs to the future adapter."""
        ...


@dataclass(frozen=True)
class QueryResult:
    status: AnswerStatus
    answer: str | None
    reason: str
    citations: list[dict] = field(default_factory=list)
    candidates: list[dict] = field(default_factory=list)
    missing_fields: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def as_dict(self) -> dict:
        return asdict(self)
