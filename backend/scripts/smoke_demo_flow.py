"""Walk the demo path on a running API with a new synthetic student and report timings.

    python3 backend/scripts/smoke_demo_flow.py --base-url http://127.0.0.1:8012

Creates one synthetic account and one synthetic record. It contains no real student data
and sends external_processing_consent=false, so it never calls a paid model by itself.
"""

import argparse
import json
import statistics
import sys
import time
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen
from uuid import uuid4

POSTING = "합성소프트 백엔드 인턴\n필수: Python 서버 개발 경험\n우대: Docker 사용 경험"
NODES = (
    "home",
    "calendar",
    "calendar:2026:11",
    "regulations",
    "regulations:2-0-1",
    "university",
    "scholarship",
    "scholarship:MN150",
    "departments:DE0013:contact",
    "graduation",
    "credits",
    "career",
    "career:posting",
)


class Client:
    def __init__(self, base_url):
        self.base_url = base_url.rstrip("/") + "/api/v1"
        self.token = None
        self.timings = {}

    def call(self, label, method, path, body=None, *, expected=(200,), raw=False):
        headers = {"Accept": "application/json"}
        data = None
        if body is not None:
            data = json.dumps(body, ensure_ascii=False).encode()
            headers["Content-Type"] = "application/json"
        if self.token:
            headers["Authorization"] = "Bearer " + self.token
        request = Request(self.base_url + path, data=data, headers=headers, method=method)
        started = time.perf_counter()
        try:
            with urlopen(request, timeout=60) as response:
                status, payload = response.status, response.read()
        except HTTPError as error:
            status, payload = error.code, error.read()
        self.timings.setdefault(label, []).append((time.perf_counter() - started) * 1000)
        if status not in expected:
            raise SystemExit(f"{label}: HTTP {status}: {payload[:200].decode(errors='replace')}")
        return payload if raw else json.loads(payload)


def require(condition, message):
    if not condition:
        raise SystemExit("FAILED: " + message)


def run(client):
    email = f"demo-{uuid4().hex[:12]}@example.test"
    account = client.call(
        "register",
        "POST",
        "/auth/register",
        {
            "email": email,
            "display_name": "합성 시연 학생",
            "password": "synthetic demo password " + uuid4().hex,
            "session_mode": "bearer",
        },
        expected=(201,),
    )
    client.token = account["access_token"]
    print("1. 학생 가입: ok")

    seen = {}
    for node in NODES:
        seen[node] = client.call(
            "guidance node", "GET", "/me/academic-guidance/nodes/" + quote(node)
        )
    require(seen["calendar:2026:11"]["cards"], "학사일정 본문이 없습니다")
    require(seen["credits"]["reason"] == "verified_audit_required", "감사 없이 판정이 표시됐습니다")
    print(f"2. 정형 학사 안내 {len(NODES)}개 노드: ok")

    page = client.call("guidance node", "GET", "/me/academic-guidance/nodes/university:CDE_000275")
    attachment = next(
        (b["node_id"] for b in page["buttons"] if ":attachment:" in b["node_id"]), None
    )
    if attachment:
        menu = client.call(
            "guidance node", "GET", "/me/academic-guidance/nodes/" + quote(attachment)
        )
        target = next(b["node_id"] for b in menu["buttons"] if ":page:" in b["node_id"])
        body = client.call("guidance node", "GET", "/me/academic-guidance/nodes/" + quote(target))
        sources = body["cards"][0]["sources"]
        asset = next(s["asset_id"] for s in sources if s.get("asset_id"))
        pdf = client.call(
            "document asset", "GET", "/me/academic-guidance/assets/" + asset, raw=True
        )
        require(pdf.startswith(b"%PDF"), "원문 PDF가 아닙니다")
        print(f"3. 규정 원문 PDF {len(pdf) // 1024}KB: ok")

    record = client.call(
        "personal record",
        "POST",
        "/me/experience-records",
        {
            "title": "합성 수강신청 도우미 프로젝트",
            "experience_type": "프로젝트",
            "role": "백엔드",
            "result": "Python으로 REST API 구현, 연락 010-0000-0000",
        },
        expected=(200, 201),
    )
    selection = {
        "kind": "experience",
        "record_id": record["id"],
        "expected_version": record["version"],
    }
    context = client.call(
        "personal context", "POST", "/me/personalization-contexts", {"records": [selection]}
    )
    require(context["official"] is False, "개인 기록이 공식 자료로 표시됐습니다")
    print("4. 개인 기록 문맥 분리: ok")

    analysis = client.call(
        "job analysis",
        "POST",
        "/me/job-analyses",
        {"posting_text": POSTING, "records": [selection], "external_processing_consent": False},
    )
    require(
        analysis["reason"] in ("analyzer_not_configured", "external_processing_consent_required"),
        "동의 없이 분석이 실행됐습니다: " + analysis["reason"],
    )
    print("5. 채용 분석 차단 상태 " + analysis["reason"] + ": ok")


def report(client):
    print("\n구간별 응답 시간(ms)")
    for label, values in client.timings.items():
        ordered = sorted(values)
        p95 = ordered[min(len(ordered) - 1, int(len(ordered) * 0.95))]
        print(
            f"  {label:18} n={len(values):3} "
            f"p50={statistics.median(values):7.1f} p95={p95:7.1f} max={ordered[-1]:7.1f}"
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--repeat", type=int, default=20)
    args = parser.parse_args()
    client = Client(args.base_url)
    run(client)
    for _ in range(args.repeat):
        for node in NODES:
            client.call("guidance node", "GET", "/me/academic-guidance/nodes/" + quote(node))
    report(client)
    return 0


if __name__ == "__main__":
    sys.exit(main())
