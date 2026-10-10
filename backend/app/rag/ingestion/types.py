"""Internal ingestion records, separate from database and public API schemas."""

from dataclasses import dataclass, field


@dataclass(frozen=True)
class DocumentSource:
    document_id: str
    source_file: str
    title: str
    institution: str
    department: str
    expected_sha256: str
    source_url: str | None = None


@dataclass(frozen=True)
class ExtractedTable:
    bbox: tuple[float, float, float, float]
    rows: list[list[str | None]]


@dataclass(frozen=True)
class ExtractedPage:
    page: int
    content: str
    tables: list[ExtractedTable] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class ExtractedDocument:
    source: DocumentSource
    content_hash: str
    extractor_version: str
    pages: list[ExtractedPage]
