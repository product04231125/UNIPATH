"""Local search/query CLI; does not start or modify the shared FastAPI application."""

import argparse
import json
import sys
from pathlib import Path

from .contracts import SchoolContext
from .retriever import SchoolRetriever, load_chunks
from .service import SchoolRagService

DEFAULT_CHUNKS = Path(__file__).resolve().parents[1] / "output/chunks.jsonl"


def main() -> int:
    parser = argparse.ArgumentParser(description="School RAG local evidence search")
    parser.add_argument("operation", choices=["search", "ask"])
    parser.add_argument("question")
    parser.add_argument("--chunks", type=Path, default=DEFAULT_CHUNKS)
    parser.add_argument("--institution")
    parser.add_argument("--department")
    parser.add_argument("--admission-year", type=int)
    parser.add_argument("--track")
    parser.add_argument("--top-k", type=int, default=3)
    parser.add_argument("--preview", action="store_true", help="Include unapproved draft sources")
    args = parser.parse_args()
    try:
        retriever = SchoolRetriever(load_chunks(args.chunks))
        context = SchoolContext(args.institution, args.department, args.admission_year, args.track)
        if args.operation == "search":
            hits = retriever.search(args.question, context, top_k=args.top_k, preview=args.preview)
            result = {
                "mode": "preview" if args.preview else "approved_only",
                "ranking": "bm25_korean_ngrams",
                "warning": "검색 후보이며 답변의 충분성이나 공식 판정을 뜻하지 않습니다.",
                "hits": [hit.as_dict() for hit in hits],
            }
        else:
            result = (
                SchoolRagService(retriever)
                .query(args.question, context, preview=args.preview)
                .as_dict()
            )
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 1 if result.get("status") == "failed" else 0
    except (ValueError, OSError) as exc:
        print(f"RAG input error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
