"""Extract page layouts and raw table cells without interpreting academic rules."""

import hashlib
from io import BytesIO
from pathlib import Path

from .types import DocumentSource, ExtractedDocument, ExtractedPage, ExtractedTable


class IngestionError(ValueError):
    """The source cannot be processed reliably."""


def normalize_layout(text: str) -> str:
    # Keep horizontal spacing: collapsing it can detach table values from headings.
    lines = [line.rstrip() for line in text.replace("\r\n", "\n").splitlines()]
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    return "\n".join(lines)


def load_pdf(source: DocumentSource, source_root: Path) -> ExtractedDocument:
    try:
        import pdfplumber
    except ImportError as exc:
        raise IngestionError(
            "Install backend/app/rag/requirements-ingestion.txt in an isolated environment."
        ) from exc

    root = source_root.resolve()
    path = (root / source.source_file).resolve()
    if not path.is_relative_to(root) or path.suffix.lower() != ".pdf":
        raise IngestionError("source_file must be a PDF inside source_root")
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise IngestionError(f"Cannot read source: {source.source_file}") from exc
    digest = hashlib.sha256(raw).hexdigest()
    if digest != source.expected_sha256.lower():
        raise IngestionError(
            f"Source hash mismatch: {source.source_file}; review the new PDF first"
        )
    if not raw.startswith(b"%PDF-"):
        raise IngestionError(f"Not a PDF: {source.source_file}")

    pages = []
    try:
        # Extract the exact bytes that were hashed, even if the original file changes.
        with pdfplumber.open(BytesIO(raw)) as pdf:
            if not pdf.pages:
                raise IngestionError("PDF contains no pages")
            for number, page in enumerate(pdf.pages, start=1):
                content = normalize_layout(page.extract_text(layout=True) or "")
                tables = []
                warnings = []
                if not content.strip():
                    warnings.append("no_text_layer_needs_review_or_ocr")
                if "\ufffd" in content or "(cid:" in content:
                    warnings.append("possible_text_encoding_error")
                try:
                    for table in page.find_tables():
                        # None and empty cells are preserved; never infer merged values or zeroes.
                        tables.append(ExtractedTable(tuple(table.bbox), table.extract()))
                except Exception:
                    warnings.append("table_extraction_failed")
                if tables:
                    warnings.append("table_structure_requires_review")
                pages.append(ExtractedPage(number, content, tables, warnings))
    except IngestionError:
        raise
    except Exception as exc:
        raise IngestionError(f"Cannot extract PDF: {source.source_file}") from exc
    return ExtractedDocument(source, digest, pdfplumber.__version__, pages)
