"""Run with: python -m app.rag.ingestion --help (from backend/)."""

import argparse
import json
import os
import re
import sys
import tempfile
from pathlib import Path
from uuid import UUID

from .chunker import PIPELINE_VERSION, chunk_document
from .pdf_loader import IngestionError, load_pdf
from .types import DocumentSource

REPOSITORY_ROOT = Path(__file__).resolve().parents[4]
DEFAULT_MANIFEST = Path(__file__).resolve().parents[1] / "sources.json"


def read_manifest(path: Path) -> list[DocumentSource]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        if payload["schema_version"] != "1.0":
            raise ValueError("Unsupported manifest version")
        entries = payload["documents"]
        if not isinstance(entries, list) or not entries:
            raise ValueError("Manifest needs documents")
        sources = []
        for entry in entries:
            source = DocumentSource(**entry)
            if str(UUID(source.document_id)) != source.document_id:
                raise ValueError("document_id must be a canonical UUID")
            for value in (source.source_file, source.title, source.institution, source.department):
                if not isinstance(value, str) or not value.strip():
                    raise ValueError("Source identity fields must be nonempty strings")
            if not re.fullmatch(r"[0-9a-fA-F]{64}", source.expected_sha256):
                raise ValueError("expected_sha256 must be a SHA-256 digest")
            if source.source_url is not None and (
                not isinstance(source.source_url, str)
                or not source.source_url.startswith(("https://", "http://"))
            ):
                raise ValueError("source_url must be an HTTP(S) URL or null")
            sources.append(source)
        if len({source.document_id for source in sources}) != len(sources):
            raise ValueError("Duplicate document_id")
        if len({source.source_file for source in sources}) != len(sources):
            raise ValueError("Duplicate source_file")
        return sources
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as exc:
        raise IngestionError(f"Invalid manifest: {exc}") from exc


def write_atomic(path: Path, content: str) -> None:
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=path.parent, delete=False, newline="\n"
        ) as handle:
            temporary = Path(handle.name)
            handle.write(content)
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def run(manifest: Path, source_root: Path, output_dir: Path) -> dict:
    sources = read_manifest(manifest)
    chunks = []
    reports = []
    # Finish extraction before touching existing outputs. A broken input fails the whole run.
    for source in sources:
        document_chunks, report = chunk_document(load_pdf(source, source_root))
        chunks.extend(document_chunks)
        reports.append(report)
    result = {
        "schema_version": "1.0",
        "pipeline_version": PIPELINE_VERSION,
        "document_count": len(reports),
        "page_count": sum(report["page_count"] for report in reports),
        "chunk_count": len(chunks),
        "empty_page_count": sum(
            page["status"] == "needs_review" for report in reports for page in report["pages"]
        ),
        "review_status": "needs_review",
        "documents": reports,
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    # Replace, never append: rerunning the same manifest does not accumulate duplicates.
    write_atomic(
        output_dir / "chunks.jsonl",
        "".join(json.dumps(chunk, ensure_ascii=False, sort_keys=True) + "\n" for chunk in chunks),
    )
    write_atomic(
        output_dir / "report.json",
        json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
    )
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract review-only PDF page chunks, offline.")
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--source-root", type=Path, default=REPOSITORY_ROOT)
    parser.add_argument(
        "--output-dir", type=Path, default=Path(__file__).resolve().parents[1] / "output"
    )
    args = parser.parse_args()
    try:
        result = run(args.manifest, args.source_root, args.output_dir)
    except (IngestionError, OSError) as exc:
        print(f"Ingestion failed: {exc}", file=sys.stderr)
        return 1
    print(
        f"{result['document_count']} documents, {result['page_count']} pages, "
        f"{result['chunk_count']} chunks; {result['empty_page_count']} pages without text. "
        f"Review required. Output: {args.output_dir.resolve()}"
    )
    # Image-only pages must not look like a fully successful extraction in scripts.
    return 2 if result["empty_page_count"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
