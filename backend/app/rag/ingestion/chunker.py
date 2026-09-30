"""Conservative page chunks: keep complete tables and surrounding headings together."""

import hashlib
import json
from dataclasses import asdict
from uuid import UUID, uuid5

from .types import ExtractedDocument

PIPELINE_VERSION = "page-layout-v1"


def chunk_document(document: ExtractedDocument) -> tuple[list[dict], dict]:
    source = document.source
    chunks = []
    page_reports = []
    for page in document.pages:
        warnings = list(page.warnings)
        if len(page.content) > 12000:
            warnings.append("large_page_not_split")
        page_report = {
            "page": page.page,
            "status": "extracted" if page.content.strip() else "needs_review",
            "character_count": len(page.content),
            "table_count": len(page.tables),
            "warnings": warnings,
            "chunk_id": None,
        }
        if page.content.strip():
            chunk = {
                "schema_version": "1.0",
                "pipeline_version": PIPELINE_VERSION,
                "document_id": source.document_id,
                "document_hash": document.content_hash,
                "title": source.title,
                "source_file": source.source_file,
                "source_url": source.source_url,
                "page": page.page,
                "document_page_count": len(document.pages),
                "chunk_index": len(chunks),
                "chunk_type": "page",
                "content": page.content,
                "content_hash": hashlib.sha256(page.content.encode("utf-8")).hexdigest(),
                "tables": [asdict(table) for table in page.tables],
                "institution": source.institution,
                "department": source.department,
                # The manifest identifies the source, not an approved rule scope.
                "admission_years": None,
                "curriculum_year": None,
                "track": None,
                "review_status": "needs_review",
                "applicability_status": "unverified",
                "eligible_for_official_answers": False,
                "context_policy": "review_document_wide_conditions_before_use",
                "extraction_method": "pdfplumber_text_layer_layout",
                "extractor_version": document.extractor_version,
                "warnings": warnings,
            }
            # Include metadata and extraction output so corrected provenance gets a new identity.
            signature = json.dumps(chunk, ensure_ascii=False, sort_keys=True)
            chunk_id = str(uuid5(UUID(source.document_id), signature))
            chunk["chunk_id"] = chunk_id
            page_report["chunk_id"] = chunk_id
            chunks.append(chunk)
        page_reports.append(page_report)
    warnings = ["applicability_unverified", "document_requires_review"]
    if source.source_url is None:
        warnings.append("source_url_missing")
    report = {
        "document_id": source.document_id,
        "source_file": source.source_file,
        "document_hash": document.content_hash,
        "page_count": len(document.pages),
        "chunk_count": len(chunks),
        "warnings": warnings,
        "pages": page_reports,
    }
    return chunks, report
