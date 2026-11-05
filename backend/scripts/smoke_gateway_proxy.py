"""Exercise both real Nginx layers with an isolated, synthetic HTTP upstream."""

import argparse
import base64
import hashlib
import http.client
import json
import subprocess
import tempfile
import time
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen
from uuid import UUID, uuid4

ROOT = Path(__file__).resolve().parents[2]
NGINX_IMAGE = "nginx:1.29-alpine"
UPSTREAM = """
from http.server import BaseHTTPRequestHandler, HTTPServer
import hashlib, json
from uuid import uuid4
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b'ready')
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        request_id = str(uuid4())
        self.send_response(401)
        self.send_header('Content-Type','application/json')
        self.send_header('X-Request-ID',request_id)
        self.send_header('X-Synthetic-Body-Bytes',str(len(body)))
        self.send_header('X-Synthetic-Body-SHA256',hashlib.sha256(body).hexdigest())
        self.send_header('X-Synthetic-Metadata-SHA256',hashlib.sha256(
            self.headers.get('X-Unipath-Source-Metadata','').encode()).hexdigest())
        self.end_headers()
        self.wfile.write(json.dumps({'error':{'code':'UNAUTHENTICATED',
            'message':'synthetic upstream only','field_errors':[],
            'request_id':request_id}}).encode())
HTTPServer(('0.0.0.0',8000), Handler).serve_forever()
"""


def run(*args):
    return subprocess.check_output(["docker", *args], text=True, stderr=subprocess.STDOUT).strip()


def server_block(text, hostname):
    for block in text.split("\nserver {"):
        if f"server_name {hostname};" in block:
            start = block.find("server {")
            return block[start:] if start >= 0 else "server {" + block
    raise ValueError("Expected a dedicated server block")


def fixture_config(template):
    block = server_block(template, "staging-unipath.duckdns.org")
    lines = [line for line in block.splitlines() if "ssl_certificate" not in line]
    return (
        "\n".join(lines)
        .replace("listen 443 ssl;", "listen 80;")
        .replace("listen [::]:443 ssl;", "listen [::]:80;")
    )


def request(base, path, size, *, headers_only=False, raw_payload=None, extra_headers=None):
    # Pure synthetic bytes, never credentials, application records or real users.
    payload = raw_payload if raw_payload is not None else b'{"synthetic":"' + b"x" * size + b'"}'
    if headers_only:
        # The edge rejects excessive Content-Length before reading a body.
        # Waiting for that response avoids a client-side broken pipe masking it.
        target = urlsplit(base)
        connection = http.client.HTTPConnection(target.hostname, target.port, timeout=15)
        try:
            connection.putrequest("POST", path)
            connection.putheader("Content-Type", "application/json")
            connection.putheader("Content-Length", str(len(payload)))
            for key, value in (extra_headers or {}).items():
                connection.putheader(key, value)
            connection.endheaders()
            response = connection.getresponse()
            return response.status, response.headers, response.read(), len(payload)
        finally:
            connection.close()
    req = Request(
        base + path,
        data=payload,
        headers={"Content-Type": "application/json", **(extra_headers or {})},
    )
    try:
        response = urlopen(req, timeout=15)
    except HTTPError as error:
        response = error
    with response:
        return response.status, response.headers, response.read(), len(payload)


def verify_chain(base):
    def common_size_error(headers, body):
        error = json.loads(body)["error"]
        assert error["code"] == "HTTP_ERROR" and error["field_errors"] == []
        assert error["request_id"] == headers["X-Request-ID"]
        UUID(error["request_id"])
        assert headers["Cache-Control"] == "no-store"

    for size in [17 * 1024, 300 * 1024, 1024 * 1024 + 1024]:
        status, headers, body, expected_size = request(base, "/api/v1/me/personal-imports", size)
        assert status == 401, (size, status)
        assert int(headers["X-Synthetic-Body-Bytes"]) == expected_size
        assert json.loads(body)["error"]["code"] == "UNAUTHENTICATED"
    for path in [
        "/api/v1/admin/knowledge-revisions",
        "/api/v1/admin/rule-programs",
        "/api/v1/admin/official-record-batches",
    ]:
        status, headers, _, expected_size = request(base, path, 128 * 1024)
        assert status == 401 and int(headers["X-Synthetic-Body-Bytes"]) == expected_size
    status, headers, body, _ = request(base, "/api/v1/admin/official-record-batches", 256 * 1024)
    assert status == 413 and "X-Synthetic-Body-Bytes" not in headers
    common_size_error(headers, body)
    for path, size in [
        ("/api/v1/auth/login", 17 * 1024),
        ("/api/v1/me/events", 300 * 1024),
        ("/api/v1/me/graduation-audits", 17 * 1024),
        ("/api/v1/admin/graduation-catalog-reviews", 17 * 1024),
    ]:
        status, headers, body, _ = request(base, path, size)
        assert status == 413 and "X-Synthetic-Body-Bytes" not in headers
        common_size_error(headers, body)
    status, headers, body, _ = request(
        base, "/api/v1/me/personal-imports", 2 * 1024 * 1024, headers_only=True
    )
    assert status == 413 and "X-Synthetic-Body-Bytes" not in headers
    common_size_error(headers, body)


def verify_source_files(base):
    marker = "SYNTHETIC_SOURCE_FILENAME_NOT_FOR_LOGS.pdf"
    metadata = base64.urlsafe_b64encode(json.dumps({"filename": marker}).encode()).decode()
    for size in [300 * 1024, 2 * 1024 * 1024]:
        payload = b"%PDF-1.7\n" + b"x" * (size - 15) + b"%%EOF\n"
        assert len(payload) == size
        status, headers, _, expected_size = request(
            base,
            "/api/v1/me/official-record-sources",
            0,
            raw_payload=payload,
            extra_headers={
                "Content-Type": "application/pdf",
                "X-Unipath-Source-Metadata": metadata,
            },
        )
        assert status == 401 and int(headers["X-Synthetic-Body-Bytes"]) == expected_size
        assert headers["X-Synthetic-Body-SHA256"] == hashlib.sha256(payload).hexdigest()
        assert (
            headers["X-Synthetic-Metadata-SHA256"] == hashlib.sha256(metadata.encode()).hexdigest()
        )
    batch_marker = "SYNTHETIC_BATCH_REFERENCE_NOT_FOR_LOGS"
    status, _, _, _ = request(
        base, "/api/v1/admin/official-record-batches?source_id=" + batch_marker, 128
    )
    assert status == 401
    audit_marker = "SYNTHETIC_GRADUATION_CONTEXT_NOT_FOR_LOGS"
    status, _, _, _ = request(
        base, "/api/v1/admin/graduation-catalog-reviews/preview?institution_id=" + audit_marker, 128
    )
    assert status == 401
    return marker, metadata, batch_marker, audit_marker


def verify_rate_limit(base):
    statuses = []
    for _ in range(12):
        status, _, body, _ = request(base, "/api/v1/auth/login", 16)
        assert status in (401, 429)
        if status == 429:
            assert json.loads(body)["error"]["code"] == "RATE_LIMITED"
        statuses.append(status)
    assert 401 in statuses and 429 in statuses
    print("PASS: login rate limiting still returns the original common 429", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--python-image", default="unipath-backend:local")
    args = parser.parse_args()
    identity = uuid4().hex
    prefix = "unipath-gateway-smoke-" + identity
    containers, created_network = [], False
    label = "unipath.gateway_smoke=" + identity
    with tempfile.TemporaryDirectory(prefix=prefix) as temporary:
        try:
            run("network", "create", "--label", label, prefix)
            created_network = True

            def start(suffix, image, *extra):
                name = prefix + "-" + suffix
                run("create", "--name", name, "--label", label, "--network", prefix, *extra, image)
                containers.append(name)
                run("start", name)
                return name

            # Create explicitly to place the command after the image name.
            upstream = prefix + "-api"
            run(
                "create",
                "--name",
                upstream,
                "--label",
                label,
                "--network",
                prefix,
                "--network-alias",
                "api",
                args.python_image,
                "python",
                "-u",
                "-c",
                UPSTREAM,
            )
            containers.append(upstream)
            run("start", upstream)
            start(
                "inner",
                NGINX_IMAGE,
                "--network-alias",
                "unipath-staging-web",
                "-v",
                str(ROOT / "deploy/preview/nginx.conf") + ":/etc/nginx/conf.d/default.conf:ro",
            )
            for index, template in enumerate(["unipath-https.conf", "unipath-http.conf"]):
                config = Path(temporary) / (template + ".conf")
                config.write_text(fixture_config((ROOT / "deploy/gateway" / template).read_text()))
                outer = start(
                    "outer-" + str(index),
                    NGINX_IMAGE,
                    "-p",
                    "127.0.0.1::80",
                    "-v",
                    str(config) + ":/etc/nginx/conf.d/default.conf:ro",
                )
                ports = json.loads(
                    run("inspect", outer, "--format", "{{json .NetworkSettings.Ports}}")
                )
                base = "http://127.0.0.1:" + ports["80/tcp"][0]["HostPort"]
                deadline = time.monotonic() + 30
                while True:
                    try:
                        with urlopen(base + "/api/v1/health/ready", timeout=1) as response:
                            if response.status == 200:
                                break
                    except OSError:
                        if time.monotonic() >= deadline:
                            raise RuntimeError(
                                "Owned synthetic gateway did not become ready"
                            ) from None
                        time.sleep(0.2)
                run("exec", outer, "nginx", "-t")
                verify_chain(base)
                markers = verify_source_files(base)
                for container in [outer, prefix + "-inner"]:
                    logs = run("logs", container)
                    assert all(marker not in logs for marker in markers), (
                        "Private metadata leaked into proxy logs"
                    )
                print(
                    "PASS: two real proxy layers:",
                    template,
                    "large imports/knowledge/rules, unchanged login/event limits, common 413",
                    flush=True,
                )
            verify_rate_limit(base)
        finally:
            for container in reversed(containers):
                actual = json.loads(
                    run("inspect", container, "--format", "{{json .Config.Labels}}")
                )
                assert actual.get("unipath.gateway_smoke") == identity
                run("rm", "-f", "-v", container)
            if created_network:
                actual = json.loads(
                    run("network", "inspect", prefix, "--format", "{{json .Labels}}")
                )
                assert actual.get("unipath.gateway_smoke") == identity
                run("network", "rm", prefix)


if __name__ == "__main__":
    main()
