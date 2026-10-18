"""Reciprocal-rank fusion. Scope filtering is performed by SchoolRetriever first."""

import math

from .retriever import Ranker


class HybridRanker:
    def __init__(self, lexical: Ranker, dense: Ranker, *, rank_constant: int = 60):
        if type(rank_constant) is not int or rank_constant < 1:
            raise ValueError("rank_constant must be a positive integer")
        self.rankers = (lexical, dense)
        self.rank_constant = rank_constant

    def score(self, question: str, indices: list[int]) -> dict[int, float]:
        fused = {}
        for ranker in self.rankers:
            scores = ranker.score(question, indices)
            ordered = sorted(
                (i for i in indices if math.isfinite(scores.get(i, 0)) and scores.get(i, 0) > 0),
                key=lambda i: (-scores[i], i),
            )
            for rank, index in enumerate(ordered, 1):
                fused[index] = fused.get(index, 0.0) + 1 / (self.rank_constant + rank)
        return fused
