"""Local search/query CLI; does not start or modify the shared FastAPI application."""

import argparse
import json
import os
import sys
from pathlib import Path

from .contracts import SchoolContext
from .embeddings import EmbeddingRanker
from .hybrid import HybridRanker
from .providers import HttpAnswerGenerator, HttpEmbeddingProvider, HttpJsonTransport
from .retriever import BM25Ranker, SchoolRetriever, load_chunks
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
    parser.add_argument("--provider", choices=["ollama", "openai-compatible"])
    parser.add_argument("--base-url", help="Explicit server URL; include /v1 for compatible APIs")
    parser.add_argument("--chat-model")
    parser.add_argument("--embedding-model")
    parser.add_argument(
        "--api-key-env", default="RAG_API_KEY", help="Environment variable name only"
    )
    parser.add_argument("--allow-network", action="store_true")
    parser.add_argument("--embedding-cache", type=Path)
    args = parser.parse_args()
    try:
        chunks = load_chunks(args.chunks)
        generator = None
        ranker = None
        if args.provider:
            if not args.base_url or not (args.chat_model or args.embedding_model):
                raise ValueError("Provider requires --base-url and an explicit model")
            transport = HttpJsonTransport(
                args.base_url,
                api_key=os.environ.get(args.api_key_env),
                allow_network=args.allow_network,
            )
            if args.chat_model:
                generator = HttpAnswerGenerator(
                    transport, dialect=args.provider, model=args.chat_model
                )
            if args.embedding_model and chunks:
                provider = HttpEmbeddingProvider(
                    transport, dialect=args.provider, model=args.embedding_model
                )
                ranker = HybridRanker(
                    BM25Ranker(chunks),
                    EmbeddingRanker(chunks, provider, cache_path=args.embedding_cache),
                )
        elif any(
            (
                args.base_url,
                args.chat_model,
                args.embedding_model,
                args.allow_network,
                args.embedding_cache,
            )
        ):
            raise ValueError("Model/network options require --provider")
        retriever = SchoolRetriever(chunks, ranker=ranker)
        context = SchoolContext(args.institution, args.department, args.admission_year, args.track)
        if args.operation == "search":
            hits = retriever.search(args.question, context, top_k=args.top_k, preview=args.preview)
            result = {
                "mode": "preview" if args.preview else "approved_only",
                "ranking": "hybrid_rrf" if ranker else "bm25_korean_ngrams",
                "warning": "검색 후보이며 답변의 충분성이나 공식 판정을 뜻하지 않습니다.",
                "hits": [hit.as_dict() for hit in hits],
            }
        else:
            result = (
                SchoolRagService(retriever, generator)
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
