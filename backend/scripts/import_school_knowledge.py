"""Import the team's validated JSONL as an unapproved, resumable server draft.

No PDF download, automatic approval, provider configuration or local-data migration.
Run with --dry-run first; credentials remain in an untracked private JSON file.
"""

import argparse
import hashlib
import json
import os
import sys
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
from uuid import UUID

from pydantic import TypeAdapter, ValidationError

from app.rag.school.retriever import validate_chunks
from app.schemas.auth import LoginRequest
from app.schemas.knowledge import ChunkPart, PageReplace
from app.schemas.personal import Day

ROOT = "admin/knowledge-revisions"


class ImportFailure(Exception):
    """Fixed safe diagnostics, without source text, passwords or server bodies."""


@dataclass(frozen=True)
class ImportPlan:
    document_hash: str
    page_count: int
    extractor_version: str
    pages: dict[int, list[dict]]


def prepare(corpus: Path, document_id: UUID, source_file: Path, blank_pages=()) -> ImportPlan:
    if corpus.stat().st_size > 32 * 1024 * 1024 or source_file.stat().st_size > 128 * 1024 * 1024:
        raise ImportFailure("The local corpus or source exceeds the import size limit.")
    with source_file.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    selected = []
    for line in corpus.read_text(encoding="utf-8").splitlines():
        if line.strip():
            value = json.loads(line)
            if UUID(value["document_id"]) == document_id:
                selected.append(value)
    if not selected:
        raise ImportFailure("The requested extraction document is absent from the corpus.")
    validate_chunks(selected)
    counts = {row["document_page_count"] for row in selected}
    versions = {row.get("extractor_version") for row in selected}
    if len(counts) != 1 or len(versions) != 1 or not 1 <= next(iter(counts)) <= 200:
        raise ImportFailure("Document page count or extractor version is inconsistent.")
    version = next(iter(versions))
    if not isinstance(version, str) or not 1 <= len(version.strip()) <= 128:
        raise ImportFailure("The extraction must declare a bounded extractor version.")
    if any(row["document_hash"] != digest for row in selected):
        raise ImportFailure("The local original does not match the extraction document hash.")
    count = next(iter(counts))
    blank = set(blank_pages)
    if len(blank) != len(blank_pages) or any(
        type(page) is not int or not 1 <= page <= count for page in blank
    ):
        raise ImportFailure("Reviewed blank page numbers are invalid.")
    by_page = {}
    for row in selected:
        by_page.setdefault(row["page"], []).append(row)
    if set(by_page) & blank or set(by_page) | blank != set(range(1, count + 1)):
        raise ImportFailure("Source pages are missing or overlap explicitly reviewed blank pages.")
    pages = {}
    for page in range(1, count + 1):
        parts = []
        for row in sorted(by_page.get(page, []), key=lambda item: item.get("page_part_index", 0)):
            # Untrusted source review flags and source URLs are deliberately omitted.
            tracks = row.get("tracks")
            if tracks is None and row.get("track"):
                tracks = [row["track"]]
            part = ChunkPart(
                content=row["content"],
                admission_years=row.get("admission_years"),
                tracks=tracks,
                warnings=row.get("warnings", []),
            )
            parts.append(
                part.model_copy(
                    update={
                        "admission_years": sorted(part.admission_years)
                        if part.admission_years
                        else None,
                        "tracks": sorted(part.tracks) if part.tracks else None,
                    }
                )
            )
        body = PageReplace(expected_version=1, is_blank=page in blank, parts=parts)
        pages[page] = [part.model_dump(mode="json") for part in body.parts]
    return ImportPlan(digest, count, version.strip(), pages)


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # An API redirect must not forward a password or privileged bearer token.
        return None


class Client:
    def __init__(self, base_url, credentials):
        parsed = urlsplit(base_url)
        _ = parsed.port
        if (
            parsed.scheme not in ("https", "http")
            or not parsed.hostname
            or parsed.username
            or parsed.password
            or parsed.query
            or parsed.fragment
            or parsed.path not in ("", "/")
            or parsed.scheme == "http"
            and parsed.hostname not in ("localhost", "127.0.0.1", "::1")
        ):
            raise ImportFailure(
                "Use an HTTPS API origin, or HTTP on loopback for local development."
            )
        if (
            credentials.is_symlink()
            or not credentials.is_file()
            or credentials.stat().st_size > 16384
        ):
            raise ImportFailure("Credentials must be a small private JSON file, not a symlink.")
        if os.name == "posix" and credentials.stat().st_mode & 0o077:
            raise ImportFailure("The credentials file must have mode 0600.")
        raw = json.loads(credentials.read_text())
        login = LoginRequest(email=raw["email"], password=raw["password"], session_mode="bearer")
        self.base, self.token = base_url.rstrip("/") + "/api/v1/", None
        self._opener = build_opener(NoRedirect())
        result = self.request(
            "POST",
            "auth/login",
            {
                "email": login.email,
                "password": login.password.get_secret_value(),
                "session_mode": "bearer",
            },
        )
        self.token = result["access_token"]

    def request(self, method, path, body=None, *, missing=False):
        headers = {"Content-Type": "application/json"}
        if self.token:
            headers["Authorization"] = "Bearer " + self.token
        request = Request(
            self.base + path,
            method=method,
            headers=headers,
            data=json.dumps(body, ensure_ascii=False).encode() if body is not None else None,
        )
        try:
            response = self._opener.open(request, timeout=30)
        except HTTPError as error:
            if missing and error.code == 404:
                error.close()
                return None
            status = error.code
            error.close()
            raise ImportFailure(
                f"The server rejected the request (HTTP {status}); "
                "inspect the existing draft before retrying."
            ) from None
        except (URLError, TimeoutError):
            raise ImportFailure(
                "The server request was not confirmed; rerun to inspect and resume the draft."
            ) from None
        with response:
            if response.status == 204:
                return None
            content = response.read(1024 * 1024 + 1)
            if len(content) > 1024 * 1024:
                raise ImportFailure("The server response exceeds the import limit.")
            return json.loads(content)

    def close(self):
        if self.token:
            try:
                self.request("POST", "auth/logout", {})
            finally:
                self.token = None


def upload(client, plan, source_document_id, expected_source_version, source_checked_on):
    if expected_source_version < 1:
        raise ImportFailure("An expected source version of at least one is required.")
    query = urlencode({"source_document_id": str(source_document_id), "limit": 100})
    existing = client.request("GET", ROOT + "?" + query)["items"]
    expected = {
        "source_document_id": str(source_document_id),
        "source_document_version": expected_source_version,
        "document_hash": plan.document_hash,
        "page_count": plan.page_count,
        "extractor_version": plan.extractor_version,
        "source_checked_on": source_checked_on.isoformat(),
    }
    if existing:
        if len(existing) != 1 or any(
            existing[0].get(key) != value for key, value in expected.items()
        ):
            raise ImportFailure(
                "An existing extraction differs; do not overwrite a reviewed draft."
            )
        document = existing[0]
    else:
        document = client.request(
            "POST",
            ROOT,
            {
                "source_document_id": str(source_document_id),
                "expected_source_version": expected_source_version,
                "document_hash": plan.document_hash,
                "page_count": plan.page_count,
                "extractor_version": plan.extractor_version,
                "source_checked_on": source_checked_on.isoformat(),
            },
        )
    if document["status"] != "draft":
        raise ImportFailure(
            "Approved or revoked extractions cannot be replaced; review a new source version."
        )
    identifier = str(UUID(document["id"]))
    uploaded = skipped = 0
    for page, parts in sorted(plan.pages.items()):
        path = ROOT + "/" + identifier + "/pages/" + str(page)
        previous = client.request("GET", path, missing=True)
        if previous is not None:
            before = [
                {key: part[key] for key in ("content", "admission_years", "tracks", "warnings")}
                for part in previous["parts"]
            ]
            if previous["is_blank"] != (len(parts) == 0) or before != parts:
                raise ImportFailure(
                    "A saved page differs; preserve the administrator's corrections "
                    "and inspect the draft."
                )
            document["version"] = previous["version"]
            skipped += 1
        else:
            response = client.request(
                "PUT",
                path,
                {"expected_version": document["version"], "is_blank": not parts, "parts": parts},
            )
            document["version"] = response["version"]
            uploaded += 1
    return identifier, uploaded, skipped


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument(
        "--document-id", type=UUID, required=True, help="Document UUID in the extraction JSONL"
    )
    parser.add_argument(
        "--source-file",
        type=Path,
        required=True,
        help="Original local file for SHA-256 verification",
    )
    parser.add_argument(
        "--source-document-id",
        type=UUID,
        required=True,
        help="Applied official_documents server UUID",
    )
    parser.add_argument("--expected-source-version", type=int, required=True)
    parser.add_argument(
        "--source-checked-on", required=True, help="Actual human source check date, YYYY-MM-DD"
    )
    parser.add_argument("--reviewed-blank-page", type=int, action="append", default=[])
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--base-url", default="http://127.0.0.1:8010")
    parser.add_argument("--credentials-file", type=Path)
    args = parser.parse_args()
    client = None
    try:
        plan = prepare(args.corpus, args.document_id, args.source_file, args.reviewed_blank_page)
        checked = TypeAdapter(Day).validate_python(args.source_checked_on)
        if checked > datetime.now(UTC).date():
            raise ImportFailure("The source check date cannot be in the future.")
        if args.dry_run:
            print(
                f"Local validation passed: {plan.page_count} pages. "
                "No server request or approval performed."
            )
            return
        if args.credentials_file is None:
            raise ImportFailure(
                "Specify an untracked private credentials JSON file for the upload."
            )
        client = Client(args.base_url, args.credentials_file)
        identifier, uploaded, skipped = upload(
            client, plan, args.source_document_id, args.expected_source_version, checked
        )
        print(
            f"Draft {identifier}: uploaded {uploaded}, unchanged {skipped}. "
            "Separate human approval is required."
        )
    except ImportFailure as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1) from None
    except (OSError, ValueError, KeyError, TypeError, ValidationError):
        print(
            "Import rejected: check local files, extraction integrity and the API contract.",
            file=sys.stderr,
        )
        raise SystemExit(1) from None
    finally:
        if client is not None:
            try:
                client.close()
            except ImportFailure:
                pass


if __name__ == "__main__":
    main()
