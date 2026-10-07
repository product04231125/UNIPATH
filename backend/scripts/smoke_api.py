"""Check the local development API without storing questions or exception details."""

import argparse
import json
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from uuid import UUID


def request(base_url, path, payload=None, expected_status=200):
    data = json.dumps(payload).encode() if payload is not None else None
    req = Request(base_url + path, data=data, headers={"Content-Type": "application/json"})
    try:
        response = urlopen(req, timeout=10)
    except HTTPError as error:
        response = error
    with response:
        assert response.status == expected_status, f"Unexpected HTTP status at {path}"
        UUID(response.headers["X-Request-ID"])
        body = json.load(response)
        if expected_status == 422:
            assert body["error"]["request_id"] == response.headers["X-Request-ID"]
        return body


def check(base_url):
    request(base_url, "/api/v1/health/ready")
    schema = request(base_url, "/api/v1/openapi.json")
    endpoint = "/api/v1/assistant/queries"
    assert "post" in schema["paths"][endpoint]
    context = {"institution": "경동대학교", "department": "컴퓨터공학과"}
    cases = [
        (
            {"question": "사회봉사 조건은?", "context": context},
            "insufficient_evidence",
            "no_approved_matching_evidence",
            [],
        ),
        (
            {"question": "사회봉사 조건은?"},
            "needs_user_input",
            "school_context_required",
            ["institution", "department"],
        ),
        (
            {"question": "저 졸업 가능한가요?", "context": context},
            "needs_user_input",
            "rule_engine_required",
            ["graduation_audit"],
        ),
    ]
    for payload, status, reason, missing in cases:
        body = request(base_url, endpoint, payload)
        UUID(body["query_id"])
        assert (body["status"], body["reason"], body["missing_fields"]) == (status, reason, missing)
        assert body["answer"] is None and body["citations"] == []
        assert "candidates" not in body
    invalid = request(
        base_url, endpoint, {"question": "사회봉사", "preview": True}, expected_status=422
    )
    assert invalid["error"]["code"] == "VALIDATION_ERROR"


def main():
    parser = argparse.ArgumentParser(description="Smoke check the current local API contract")
    parser.add_argument("--base-url", default="http://127.0.0.1:8010")
    args = parser.parse_args()
    try:
        check(args.base_url.rstrip("/"))
    except (AssertionError, OSError, URLError, KeyError, ValueError):
        parser.exit(1, "Local API smoke check failed. Check service readiness and configuration.\n")
    print("Local API smoke check passed: readiness, OpenAPI, school queries, validation.")


if __name__ == "__main__":
    main()
