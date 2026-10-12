"""Offline BM25 baseline with Korean character n-grams and explicit scope filters."""

import hashlib
import json
import math
import re
import unicodedata
from collections import Counter
from pathlib import Path
from typing import Protocol
from urllib.parse import urlsplit
from uuid import UUID

from .contracts import SchoolContext, SearchHit

STOP_WORDS = {"알려줘", "알려주세요", "무엇인가요", "뭔가요", "어떻게", "몇", "인가요"}


def tokenize(text: str) -> list[str]:
    text = unicodedata.normalize("NFKC", text).lower()
    tokens = []
    for word in re.findall(r"[가-힣]+|[a-z]+|\d+", text):
        if word in STOP_WORDS:
            continue
        tokens.append(word)
        if re.fullmatch(r"[가-힣]+", word):
            for width in (2, 3):
                tokens.extend(word[i : i + width] for i in range(len(word) - width + 1))
    return tokens


def validate_chunks(chunks: list[dict]) -> None:
    ids = set()
    page_keys = {}
    document_versions = {}
    for chunk in chunks:
        for key in ("chunk_id", "document_id"):
            UUID(chunk[key])
        for key in ("title", "source_file", "institution", "department", "content"):
            if not isinstance(chunk[key], str) or not chunk[key].strip():
                raise ValueError(f"Invalid {key}")
        if type(chunk["page"]) is not int or chunk["page"] < 1:
            raise ValueError("Invalid page")
        page_count = chunk.get("document_page_count")
        if type(page_count) is not int or page_count < chunk["page"]:
            raise ValueError("Invalid document_page_count")
        document_hash = chunk.get("document_hash")
        if not isinstance(document_hash, str) or not re.fullmatch(r"[0-9a-f]{64}", document_hash):
            raise ValueError("Invalid document_hash")
        version = (document_hash, page_count, chunk["institution"], chunk["department"])
        previous = document_versions.setdefault(chunk["document_id"], version)
        if previous != version:
            raise ValueError("Mixed document versions or identities; rebuild the corpus")
        if chunk["chunk_id"] in ids:
            raise ValueError("Duplicate chunk_id")
        page_key = (chunk["document_id"], chunk["page"])
        page_keys.setdefault(page_key, []).append(chunk)
        ids.add(chunk["chunk_id"])
        expected = hashlib.sha256(chunk["content"].encode("utf-8")).hexdigest()
        if expected != chunk.get("content_hash"):
            raise ValueError("Chunk content hash mismatch")
        if chunk.get("source_url") is not None and not isinstance(chunk["source_url"], str):
            raise ValueError("Invalid source_url")
        years = chunk.get("admission_years")
        if years is not None and (
            not isinstance(years, list)
            or any(type(year) is not int or not 1000 <= year <= 9999 for year in years)
        ):
            raise ValueError("Invalid admission_years")

        tracks = chunk.get("tracks")
        if tracks is not None and (
            not isinstance(tracks, list)
            or not tracks
            or any(not isinstance(track, str) or not track.strip() for track in tracks)
            or chunk.get("track") is not None
        ):
            raise ValueError("Invalid or ambiguous tracks")
        if not isinstance(chunk.get("warnings", []), list) or any(
            not isinstance(warning, str) for warning in chunk.get("warnings", [])
        ):
            raise ValueError("Invalid warnings")
    for group in page_keys.values():
        if all(c.get("schema_version", "1.0") == "1.0" for c in group):
            if len(group) != 1:
                raise ValueError("This page index expects one chunk per document page")
            continue
        if any(c.get("schema_version") != "2.0" for c in group):
            raise ValueError("Unknown or mixed chunk schema")
        expected_parts = group[0].get("page_part_count")
        if type(expected_parts) is not int or expected_parts < 1:
            raise ValueError("Invalid page part count")
        if any(type(c.get("page_part_index")) is not int for c in group):
            raise ValueError("Invalid page part index")
        ordered = sorted(group, key=lambda c: c["page_part_index"])
        if [c["page_part_index"] for c in ordered] != list(range(expected_parts)):
            raise ValueError("Missing or duplicate page parts")
        offset = 0
        for part in ordered:
            if (
                part.get("page_part_count") != expected_parts
                or type(part.get("source_character_start")) is not int
                or type(part.get("source_character_end")) is not int
                or part["source_character_start"] != offset
                or part["source_character_end"] != offset + len(part["content"])
            ):
                raise ValueError("Page part offsets do not cover the original page")
            offset = part["source_character_end"]
        digest = hashlib.sha256("".join(c["content"] for c in ordered).encode()).hexdigest()
        if any(c.get("page_content_hash") != digest for c in ordered):
            raise ValueError("Page reconstruction hash mismatch")


def valid_source_url(value: object) -> bool:
    if not isinstance(value, str) or any(char.isspace() for char in value):
        return False
    try:
        url = urlsplit(value)
        _ = url.port  # Reject malformed/out-of-range ports before API citation validation.
        return bool(
            url.scheme in ("http", "https")
            and url.hostname
            and not url.username
            and not url.password
        )
    except ValueError:
        return False


def load_chunks(path: Path) -> list[dict]:
    try:
        chunks = [
            json.loads(line)
            for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        validate_chunks(chunks)
        return chunks
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as exc:
        raise ValueError(f"Cannot load chunk corpus: {exc}") from exc


def approved(chunk: dict) -> bool:
    return (
        chunk.get("eligible_for_official_answers") is True
        and chunk.get("review_status") == "approved"
        and chunk.get("applicability_status") == "verified"
        and valid_source_url(chunk.get("source_url"))
        and not set(chunk.get("warnings", [])).intersection(
            {
                "table_structure_requires_review",
                "table_extraction_failed",
                "possible_text_encoding_error",
                "no_text_layer_needs_review_or_ocr",
            }
        )
    )


def matches_scope(chunk: dict, context: SchoolContext, *, preview: bool) -> bool:
    for key in ("institution", "department"):
        requested = getattr(context, key)
        if requested is not None and chunk.get(key) != requested:
            return False
    if not preview and not approved(chunk):
        return False
    if context.admission_year is not None:
        years = chunk.get("admission_years")
        if years is not None:
            if context.admission_year not in years:
                return False
        elif not preview:
            return False
        else:
            # These are observed headings, not approved applicability metadata.
            observed = {
                int(year) for year in re.findall(r"(\d{4})학년도\s*입학자", chunk["content"])
            }
            if observed and context.admission_year not in observed:
                return False
    if context.track is not None:
        track = chunk.get("track")
        tracks = chunk.get("tracks")
        if tracks is not None:
            if context.track not in tracks:
                return False
        elif track is None and not preview:
            return False
        elif track is not None and track != context.track:
            return False
    return True


class Ranker(Protocol):
    def score(self, question: str, indices: list[int]) -> dict[int, float]: ...


class BM25Ranker:
    """A lexical baseline, not a learned semantic embedding model."""

    def __init__(self, chunks: list[dict]):
        self.counts = [Counter(tokenize(c["title"] + " " + c["content"])) for c in chunks]
        self.lengths = [sum(counts.values()) for counts in self.counts]
        self.average_length = max(1.0, sum(self.lengths) / max(1, len(self.lengths)))
        frequency = Counter(term for counts in self.counts for term in counts)
        total = len(chunks)
        self.idf = {
            term: math.log(1 + (total - count + 0.5) / (count + 0.5))
            for term, count in frequency.items()
        }

    def score(self, question: str, indices: list[int]) -> dict[int, float]:
        terms = set(tokenize(question))
        scores = {}
        for index in indices:
            total = 0.0
            for term in terms:
                frequency = self.counts[index].get(term, 0)
                denominator = frequency + 1.5 * (
                    0.25 + 0.75 * self.lengths[index] / self.average_length
                )
                total += self.idf.get(term, 0) * frequency * 2.5 / denominator
            scores[index] = total
        return scores


class SchoolRetriever:
    def __init__(self, chunks: list[dict], ranker: Ranker | None = None):
        validate_chunks(chunks)
        self.chunks = chunks
        self.ranker = ranker or BM25Ranker(chunks)

    def _hit(self, index: int, score: float) -> SearchHit:
        chunk = self.chunks[index]
        return SearchHit(
            chunk_id=chunk["chunk_id"],
            document_id=chunk["document_id"],
            title=chunk["title"],
            source_file=chunk["source_file"],
            source_url=chunk.get("source_url"),
            page=chunk["page"],
            content=chunk["content"],
            score=round(score, 6),
            review_status=chunk.get("review_status", "needs_review"),
            applicability_status=chunk.get("applicability_status", "unverified"),
            related_pages=sorted(
                {
                    c["page"]
                    for c in self.chunks
                    if c["document_id"] == chunk["document_id"] and c["page"] != chunk["page"]
                }
            ),
        )

    def search(
        self, question: str, context: SchoolContext, *, top_k: int = 3, preview: bool = False
    ) -> list[SearchHit]:
        if not question.strip():
            raise ValueError("Question must not be empty")
        if type(top_k) is not int or not 1 <= top_k <= 20:
            raise ValueError("top_k must be between 1 and 20")
        indices = [
            i
            for i, chunk in enumerate(self.chunks)
            if matches_scope(chunk, context, preview=preview)
        ]
        if not indices:
            return []
        scores = self.ranker.score(question, indices)
        ranked = sorted(
            (i for i in indices if math.isfinite(scores.get(i, 0)) and scores.get(i, 0) > 0),
            key=lambda i: (
                -scores[i],
                self.chunks[i]["document_id"],
                self.chunks[i]["page"],
                self.chunks[i].get("page_part_index", 0),
            ),
        )
        return [self._hit(i, scores[i]) for i in ranked[:top_k]]

    def approved_context(self, hits: list[SearchHit], context: SchoolContext) -> list[SearchHit]:
        """Include document-wide qualifications; never silently drop an unapproved context page."""
        documents = {hit.document_id for hit in hits}
        indices = [i for i, chunk in enumerate(self.chunks) if chunk["document_id"] in documents]
        if any(not approved(self.chunks[i]) for i in indices):
            return []
        # An unknown scope page might contain an applicable exception: do not omit it.
        if any(
            (context.admission_year is not None and not self.chunks[i].get("admission_years"))
            or (
                context.track is not None
                and not (self.chunks[i].get("track") or self.chunks[i].get("tracks"))
            )
            for i in indices
        ):
            return []
        indices = [i for i in indices if matches_scope(self.chunks[i], context, preview=False)]
        # Incomplete source extraction cannot supply document-wide conditions reliably.
        for document_id in documents:
            group = [c for c in self.chunks if c["document_id"] == document_id]
            expected = {c.get("document_page_count") for c in group}
            if expected != {len({c["page"] for c in group})}:
                return []
        scores = {hit.chunk_id: hit.score for hit in hits}
        return [self._hit(i, scores.get(self.chunks[i]["chunk_id"], 0)) for i in indices]
