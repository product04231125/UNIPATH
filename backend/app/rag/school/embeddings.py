"""Optional dense ranking adapter. This module chooses no model or API provider."""

import math
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

    def __init__(self, chunks: list[dict], provider: EmbeddingProvider):
        self.provider = provider
        self.model_id = provider.model_id
        vectors = provider.embed_documents([c["title"] + "\n" + c["content"] for c in chunks])
        if len(vectors) != len(chunks) or not vectors:
            raise ValueError("Embedding provider returned the wrong number of vectors")
        self.dimension = len(vectors[0])
        self.vectors = [unit_vector(vector, self.dimension) for vector in vectors]

    def score(self, question: str, indices: list[int]) -> dict[int, float]:
        if self.provider.model_id != self.model_id:
            raise ValueError("Embedding model changed; rebuild the index")
        query = unit_vector(self.provider.embed_query(question), self.dimension)
        return {i: sum(a * b for a, b in zip(query, self.vectors[i], strict=True)) for i in indices}
