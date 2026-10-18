"""Optional dense ranking adapter. This module chooses no model or API provider."""

import hashlib
import json
import math
from pathlib import Path
from typing import Protocol


class EmbeddingProvider(Protocol):
    model_id: str

    def embed_documents(self, texts: list[str]) -> list[list[float]]: ...

    def embed_query(self, text: str) -> list[float]: ...


def unit_vector(vector: list[float], dimension: int | None = None) -> list[float]:
    if not vector or (dimension is not None and len(vector) != dimension):
        raise ValueError("Embedding dimension mismatch or empty vector")
    if any(type(value) not in (float, int) or not math.isfinite(value) for value in vector):
        raise ValueError("Embedding contains invalid values")
    norm = math.hypot(*vector)
    if norm == 0 or not math.isfinite(norm):
        raise ValueError("Embedding norm must be finite and nonzero")
    return [value / norm for value in vector]


class EmbeddingRanker:
    """Cosine ranking for an injected embedding provider; scope filtering remains upstream."""

    def __init__(
        self, chunks: list[dict], provider: EmbeddingProvider, *, cache_path: Path | None = None
    ):
        self.provider = provider
        self.model_id = provider.model_id
        texts = [c["title"] + "\n" + c["content"] for c in chunks]
        signature = hashlib.sha256(
            json.dumps(
                {"model_id": self.model_id, "texts": texts, "ids": [c["chunk_id"] for c in chunks]},
                ensure_ascii=False,
                sort_keys=True,
            ).encode()
        ).hexdigest()
        vectors = None
        if cache_path is not None and cache_path.exists():
            cache = json.loads(cache_path.read_text(encoding="utf-8"))
            if cache.get("signature") == signature:
                vectors = cache["vectors"]
        cached = vectors is not None
        if vectors is None:
            vectors = provider.embed_documents(texts)
        if len(vectors) != len(chunks) or not vectors:
            raise ValueError("Embedding provider returned the wrong number of vectors")
        self.dimension = len(vectors[0])
        self.vectors = [unit_vector(vector, self.dimension) for vector in vectors]
        if cache_path is not None and not cached:
            from ..ingestion.__main__ import write_atomic

            cache_path.parent.mkdir(parents=True, exist_ok=True)
            write_atomic(cache_path, json.dumps({"signature": signature, "vectors": self.vectors}))

    def score(self, question: str, indices: list[int]) -> dict[int, float]:
        if self.provider.model_id != self.model_id:
            raise ValueError("Embedding model changed; rebuild the index")
        query = unit_vector(self.provider.embed_query(question), self.dimension)
        return {i: sum(a * b for a, b in zip(query, self.vectors[i], strict=True)) for i in indices}
