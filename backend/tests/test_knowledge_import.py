import hashlib
import json
from datetime import UTC, datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
from threading import Thread
from uuid import uuid4

import pytest
from sqlalchemy import select
from test_academic import department, operator, school
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_knowledge import ROOT, applied_document

from app.models.knowledge import KnowledgeDocument
from app.rag.school.retriever import validate_chunks
from scripts.import_school_knowledge import Client, ImportFailure, prepare, upload


def extraction(tmp_path, *, pages=2):
    original = tmp_path / "synthetic.pdf"
    original.write_bytes(b"%PDF-1.7 synthetic test source; not a real university document")
    content = "합성 봉사 규정"
    identifier = uuid4()
    row = {
        "chunk_id": str(uuid4()),
        "document_id": str(identifier),
        "title": "합성 규정",
        "source_file": "synthetic.pdf",
        "source_url": "https://source.example.invalid/rules",
        "document_hash": hashlib.sha256(original.read_bytes()).hexdigest(),
        "page": 1,
        "document_page_count": pages,
        "content": content,
        "content_hash": hashlib.sha256(content.encode()).hexdigest(),
        "institution": "합성대",
        "department": "합성학과",
        "admission_years": [2026, 2025],
        "tracks": ["single_major", "minor"],
        "warnings": ["table_structure_requires_review"],
        "extractor_version": "synthetic-extractor",
        "eligible_for_official_answers": True,
        "review_status": "approved",
        "applicability_status": "verified",
    }
    corpus = tmp_path / "chunks.jsonl"
    corpus.write_text(json.dumps(row, ensure_ascii=False) + "\n")
    return corpus, identifier, original, row


def test_import_checks_original_hash_and_explicit_complete_page_coverage(tmp_path):
    corpus, identifier, original, _ = extraction(tmp_path)
    with pytest.raises(ImportFailure, match="missing"):
        prepare(corpus, identifier, original)
    plan = prepare(corpus, identifier, original, [2])
    assert plan.pages[2] == []
    part = plan.pages[1][0]
    assert part["admission_years"] == [2025, 2026]
    assert part["tracks"] == ["minor", "single_major"]
    assert part["warnings"] == ["table_structure_requires_review"]
    assert set(part) == {"content", "admission_years", "tracks", "warnings"}
    original.write_bytes(b"modified synthetic original")
    with pytest.raises(ImportFailure, match="hash"):
        prepare(corpus, identifier, original, [2])


def test_blank_metadata_cannot_hide_a_text_page_or_an_invalid_source_page(tmp_path):
    _, _, _, row = extraction(tmp_path)
    for pages in [[1], [3], [True], [2, 2]]:
        with pytest.raises(ValueError):
            validate_chunks([{**row, "reviewed_blank_pages": pages}])


def test_api_redirect_does_not_forward_operator_credentials_or_bearer(tmp_path):
    requests = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_POST(self):
            requests.append(self.path)
            self.rfile.read(int(self.headers.get("Content-Length", "0")))
            if self.path.endswith("/login"):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'{"access_token":"synthetic-token"}')
            else:
                self.send_response(204)
                self.end_headers()

        def do_GET(self):
            requests.append(self.path)
            self.send_response(301)
            self.send_header("Location", "/redirect-target")
            self.end_headers()

    credentials = tmp_path / "credentials.json"
    credentials.write_text(
        json.dumps(
            {"email": "synthetic@example.invalid", "password": "synthetic operator password 2026"}
        )
    )
    credentials.chmod(0o600)
    server = HTTPServer(("127.0.0.1", 0), Handler)
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    client = None
    try:
        client = Client(f"http://127.0.0.1:{server.server_port}", credentials)
        with pytest.raises(ImportFailure, match="HTTP 301"):
            client.request("GET", "admin/knowledge-revisions")
        assert requests == ["/api/v1/auth/login", "/api/v1/admin/knowledge-revisions"]
    finally:
        if client:
            client.close()
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


@pytest.mark.integration
def test_import_resumes_only_matching_drafts_and_never_approves_or_overwrites_corrections(
    auth_client, auth_db, tmp_path
):
    c, headers = auth_client, operator(auth_client, auth_db)
    institution = school(c, headers)
    dep = department(c, headers, institution)
    source = applied_document(c, headers, institution, dep)
    corpus, identifier, original, _ = extraction(tmp_path)
    plan = prepare(corpus, identifier, original, [2])

    class Adapter:
        def request(self, method, path, body=None, *, missing=False):
            response = c.request(
                method,
                "/api/v1/" + path,
                headers=headers,
                **({"json": body} if body is not None else {}),
            )
            if missing and response.status_code == 404:
                return None
            assert response.status_code in (200, 201, 204), response.text
            return response.json() if response.status_code != 204 else None

    checked = datetime.now(UTC).date()
    first, uploaded, skipped = upload(Adapter(), plan, source["id"], source["version"], checked)
    assert (uploaded, skipped) == (2, 0)
    second, uploaded, skipped = upload(Adapter(), plan, source["id"], source["version"], checked)
    assert second == first and (uploaded, skipped) == (0, 2)
    with auth_db() as db:
        document = db.scalar(select(KnowledgeDocument))
        assert document.status == "draft" and document.approved_at is None
    current = c.get(ROOT + "/" + first, headers=headers).json()
    response = c.put(
        ROOT + "/" + first + "/pages/1",
        headers=headers,
        json={
            "expected_version": current["version"],
            "parts": [{"content": "검토자가 바로잡은 합성 본문"}],
        },
    )
    assert response.status_code == 200
    with pytest.raises(ImportFailure, match="saved page differs"):
        upload(Adapter(), plan, source["id"], source["version"], checked)
    saved = c.get(ROOT + "/" + first + "/pages/1", headers=headers).json()
    assert saved["parts"][0]["content"] == "검토자가 바로잡은 합성 본문"
