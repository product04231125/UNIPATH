"""Opt-in, lossless year-heading splits. Observations are never approved scope."""

import hashlib
import json
import re
from uuid import UUID, uuid5

from .chunker import chunk_document
from .types import ExtractedDocument

PIPELINE_VERSION = "year-sections-v2"
HEADING = re.compile(r"(?m)^[ \t]*(\d{4})학년도[ \t]+입학자[ \t]*$")


def chunk_sections(document: ExtractedDocument) -> tuple[list[dict], dict]:
    pages, report = chunk_document(document)
    chunks = []
    for page in pages:
        content = page["content"]
        headings = list(HEADING.finditer(content))
        # Keep the preamble as its own context part, not attached to one arbitrary year.
        starts = sorted({0, *(match.start() for match in headings)})
        ends = starts[1:] + [len(content)]
        parts = [(start, end) for start, end in zip(starts, ends, strict=True)]
        for part_index, (start, end) in enumerate(parts):
            item = dict(page)
            item.pop("chunk_id")
            item.update(
                schema_version="2.0",
                pipeline_version=PIPELINE_VERSION,
                chunk_type="year_section" if headings else "page",
                chunk_index=len(chunks),
                page_part_index=part_index,
                page_part_count=len(parts),
                page_content_hash=page["content_hash"],
                source_character_start=start,
                source_character_end=end,
                content=content[start:end],
                content_hash=hashlib.sha256(content[start:end].encode()).hexdigest(),
                observed_admission_years=[
                    int(match.group(1)) for match in headings if start <= match.start() < end
                ],
                # Table coordinates belong to the original page, never to an inferred row.
                table_metadata_scope="original_page",
            )
            item["chunk_id"] = str(
                uuid5(
                    UUID(item["document_id"]), json.dumps(item, ensure_ascii=False, sort_keys=True)
                )
            )
            chunks.append(item)
        page_report = next(p for p in report["pages"] if p["page"] == page["page"])
        page_report.pop("chunk_id")
        page_report["chunk_ids"] = [c["chunk_id"] for c in chunks if c["page"] == page["page"]]
    report["chunk_count"] = len(chunks)
    return chunks, report
