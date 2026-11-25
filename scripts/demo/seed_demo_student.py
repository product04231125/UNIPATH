#!/usr/bin/env python3
"""시연 계정에 시연용 합성 데이터를 넣는다(스테이징 공개 API만 사용).

    python3 scripts/demo/seed_demo_student.py           # 빠진 시연 데이터만 넣는다
    python3 scripts/demo/seed_demo_student.py --reset   # 리허설 흔적을 지우고 처음 상태로 되돌린다
    python3 scripts/demo/seed_demo_student.py --status  # 지금 상태만 본다
    python3 scripts/demo/seed_demo_student.py --clear   # 시연 뒤 정리(다시 넣지 않음)

계정 정보는 ~/.config/unipath-staging-demo/account.json({"base_url", "email", "password"})에서 읽고
출력하지 않는다. 처음 실행할 때 계정에 원래 있던 자료(수강 기록·자격·내 자료 등)의 id를
~/.config/unipath-staging-demo/state.json에 "원래 자료"로 기록해 두고,
--reset은 그 밖의 것만 지운다.

--reset이 지우는 것: 저장된 분석 결과 전부, 저장한 자기소개서·포트폴리오 전부, 원래 자료가 아닌
일정·활동·경험·자격·성과·내 자료(이 스크립트가 넣은 것 + 리허설 중 추가한 것). 그다음 시연 데이터를
다시 넣는다. 일정 날짜는 실행한 날(한국 시간) 기준이라 시연 당일 아침에 --reset 하면 된다.
모든 내용은 시연용 합성 데이터다.
"""

import argparse
import base64
import json
import os
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

# UNIPATH_DEMO_CONFIG: another account folder (for testing the script on a check account).
CONFIG = Path(os.environ.get("UNIPATH_DEMO_CONFIG", "~/.config/unipath-staging-demo")).expanduser()
ACCOUNT = CONFIG / "account.json"
STATE = CONFIG / "state.json"
KST = ZoneInfo("Asia/Seoul")
RECORDS = [
    "events",
    "activity-records",
    "experience-records",
    "credential-records",
    "achievement-records",
]


class Api:
    def __init__(self, account):
        self.base = account["base_url"].rstrip("/") + "/api/v1"
        self.token = self.owner = None
        status, body = self.call(
            "POST",
            "/auth/login",
            {"email": account["email"], "password": account["password"], "session_mode": "bearer"},
        )
        if status != 200:
            sys.exit(f"로그인 실패: HTTP {status} {body.get('error', {}).get('code', '')}")
        self.token, self.owner = body["access_token"], body["user"]["id"]

    def call(self, method, path, body=None, timeout=60):
        headers = {"Content-Type": "application/json", "User-Agent": "unipath-demo-seed"}
        if self.token:
            headers["Authorization"] = "Bearer " + self.token
            headers["X-Unipath-Owner"] = self.owner
        data = None if body is None else json.dumps(body, ensure_ascii=False).encode()
        request = urllib.request.Request(
            self.base + path, data=data, headers=headers, method=method
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                raw = response.read()
                return response.status, (json.loads(raw) if raw else {})
        except urllib.error.HTTPError as error:
            raw = error.read()
            try:
                return error.code, json.loads(raw or b"{}")
            except ValueError:
                return error.code, {}

    def ok(self, method, path, body=None, expect=(200, 201, 204)):
        status, value = self.call(method, path, body)
        if status not in expect:
            code = value.get("error", {}).get("code", "") if isinstance(value, dict) else ""
            sys.exit(
                f"{method} {path} 실패: HTTP {status} {code} "
                f"{json.dumps(value, ensure_ascii=False)[:300]}"
            )
        return value

    def all(self, path):
        items, cursor = [], None
        while True:
            sep = "&" if "?" in path else "?"
            value = self.ok("GET", path + (f"{sep}cursor={cursor}" if cursor else ""))
            items += value.get("items", [])
            cursor = value.get("next_cursor")
            if not cursor:
                return items


# ---- 시연 데이터 -------------------------------------------------------------------------------
# 인물: 경동대 컴퓨터공학과 4학년(2019 입학), 백엔드 개발자 지망.
# 졸업작품 UniPath와 RouteOn을 만들었다.

GOAL = {"category_codes": ["024"], "keyword": "백엔드"}

EXPERIENCES = [
    {
        "title": "졸업작품 UniPath: 학업·진로 기록 서비스",
        "experience_type": "프로젝트",
        "organization": "경동대학교 컴퓨터공학과 캡스톤",
        "role": "백엔드·통합 담당(3인 팀)",
        "started_on": "2026-03-02",
        "status_label": "진행 중",
        "detail": "학생이 수업·활동·자격 기록을 모아 졸업요건을 확인하고 "
        "채용공고와 비교하는 서비스. "
        "Flutter 웹·Windows 앱과 FastAPI 서버, PostgreSQL(pgvector), Vertex AI Gemini를 사용했다.",
        "result": "FastAPI로 인증·권한, 개인 기록, 졸업요건 계산(Rule Engine) REST API를 구현했다. "
        "SQLAlchemy와 Alembic으로 DB 구조 변경을 마이그레이션으로 관리했다. "
        "Docker Compose로 스테이징 서버를 구성하고 GitHub Actions로 테스트를 자동화했다. "
        "팀원 작업을 통합하고 배포 전 DB 백업 절차를 만들었다.",
    },
    {
        "title": "RouteOn: 화물차 경로 안내 웹 서비스",
        "experience_type": "프로젝트",
        "organization": "개인·팀 프로젝트",
        "role": "백엔드 개발",
        "started_on": "2025-09-01",
        "ended_on": "2025-12-19",
        "status_label": "완료",
        "detail": "화물차의 높이·중량 제한을 고려해 경로를 안내하는 웹 서비스.",
        "result": "FastAPI로 경로 요청 API와 차량 제원 저장 API를 만들고 "
        "외부 지도 API 응답을 가공했다. Docker로 서버를 컨테이너화해 배포했고, "
        "요청 로그를 보고 느린 구간의 원인을 찾아 응답 시간을 줄였다.",
    },
]

ACTIVITIES = [
    {
        "title": "교내 SW 학술동아리 백엔드 스터디",
        "organization": "컴퓨터공학과 학술동아리",
        "role": "스터디장",
        "started_on": "2025-09-01",
        "ended_on": "2026-06-30",
        "reported_hours": 60,
        "detail": "FastAPI·Spring으로 REST API를 만드는 스터디를 운영하고 "
        "매주 서로의 코드를 리뷰했다.",
    },
    {
        "title": "지역 아동센터 코딩 교육 봉사",
        "organization": "합성 지역아동센터",
        "role": "보조 강사",
        "started_on": "2025-07-07",
        "ended_on": "2025-08-22",
        "reported_hours": 24,
        "detail": "초등학생 대상 블록 코딩 수업을 보조하고 실습 자료를 만들었다.",
    },
]

CREDENTIALS = [
    {
        "title": "SQLD",
        "provider": "한국데이터산업진흥원",
        "earned_on": "2026-06-26",
        "status_label": "취득",
    },
    {
        "title": "리눅스마스터 2급",
        "provider": "한국정보통신진흥협회",
        "status_label": "1차 합격, 2차 준비 중",
        "detail": "2차 실기 대비로 리눅스 서버 계정·권한·서비스 관리를 공부하고 있다.",
    },
]

MATERIAL = {
    "title": "백엔드 포트폴리오 요약",
    "material_type": "portfolio",
    "description": "UniPath·RouteOn 두 프로젝트에서 맡은 백엔드 작업 요약(2쪽)",
    "filename": "backend-portfolio.pdf",
}

PORTFOLIO_HTML = """<!doctype html><html lang="ko"><head><meta charset="utf-8"><style>
@page { size: A4; margin: 22mm 20mm; }
body { font-family: 'NanumGothic', 'NanumBarunGothic', sans-serif; color: #222;
  font-size: 11pt; line-height: 1.65; }
h1 { font-size: 20pt; margin: 0 0 4mm; }
h2 { font-size: 14pt; margin: 8mm 0 2mm; border-bottom: 1px solid #bbb; }
.muted { color: #666; font-size: 10pt; } ul { margin: 1mm 0 0 5mm; padding: 0; }
.page { page-break-after: always; }
</style></head><body>
<div class="page">
<h1>백엔드 포트폴리오 요약</h1>
<div class="muted">경동대학교 컴퓨터공학과 4학년 · 시연용 합성 자료</div>
<h2>졸업작품 UniPath (2026.03 ~ 진행 중)</h2>
<div class="muted">Flutter · FastAPI · PostgreSQL(pgvector) · Vertex AI Gemini ·
Docker · GitHub Actions</div>
<ul>
<li>인증·권한, 개인 기록, 졸업요건 계산(Rule Engine) REST API 구현</li>
<li>SQLAlchemy·Alembic 마이그레이션으로 DB 구조 변경 관리</li>
<li>Docker Compose로 스테이징 서버 구성, GitHub Actions로 테스트 자동화</li>
<li>팀원 작업 통합과 배포 전 DB 백업 절차 마련</li>
</ul>
</div>
<div>
<h2>RouteOn (2025.09 ~ 2025.12)</h2>
<div class="muted">FastAPI · Docker · 외부 지도 API</div>
<ul>
<li>화물차 높이·중량 제한을 고려한 경로 요청 API와 차량 제원 저장 API 구현</li>
<li>외부 지도 API 응답을 가공해 화면에 맞는 형태로 제공</li>
<li>요청 로그로 느린 구간을 찾아 응답 시간 개선</li>
</ul>
<h2>자격</h2>
<ul><li>SQLD (2026.06 취득)</li><li>리눅스마스터 2급 (1차 합격, 2차 준비 중)</li></ul>
</div>
</body></html>"""


def events(today: date):
    """This week's plans, one already done, and an internship deadline ten days out (KST)."""

    def at(day, hour, minute=0):
        return (
            datetime.combine(day, datetime.min.time(), KST)
            .replace(hour=hour, minute=minute)
            .isoformat()
        )

    done_at = datetime.now(KST).replace(microsecond=0).isoformat()
    return [
        {
            "title": "포트폴리오 README 정리",
            "category": "personal",
            "starts_at": at(today, 10),
            "ends_at": at(today, 11),
            "completed_at": done_at,
        },
        {
            "title": "백엔드 기술 면접 스터디",
            "category": "activity",
            "starts_at": at(today + timedelta(days=1), 19),
            "ends_at": at(today + timedelta(days=1), 21),
        },
        {
            "title": "졸업작품 최종 발표 리허설",
            "category": "academic",
            "starts_at": at(today + timedelta(days=2), 14),
            "ends_at": at(today + timedelta(days=2), 16),
        },
        {
            "title": "합성 IT 백엔드 인턴 지원 마감",
            "category": "deadline",
            "starts_at": at(today + timedelta(days=10), 23, 0),
            "ends_at": at(today + timedelta(days=10), 23, 59),
        },
    ]


# ---- 실행 ---------------------------------------------------------------------------------------


def load_state():
    return json.loads(STATE.read_text()) if STATE.exists() else {}


def save_state(state):
    CONFIG.mkdir(mode=0o700, exist_ok=True)
    STATE.write_text(json.dumps(state, ensure_ascii=False, indent=2))
    os.chmod(STATE, 0o600)


def baseline(api, state):
    if "baseline" not in state:
        state["baseline"] = {r: [i["id"] for i in api.all(f"/me/{r}?limit=100")] for r in RECORDS}
        state["baseline"]["materials"] = [m["id"] for m in api.ok("GET", "/me/materials")["items"]]
        goal = api.ok("GET", "/me/career-goal")
        state["baseline"]["goal"] = {
            k: goal.get(k) or d for k, d in (("category_codes", []), ("keyword", ""))
        }
        save_state(state)
        print("원래 자료를 기록했습니다:", {k: len(v) for k, v in state["baseline"].items()})
    return state["baseline"]


def reset(api, state):
    kept = baseline(api, state)
    removed = {}
    for item in api.ok("GET", "/me/analysis-results").get("items", []):
        api.ok("DELETE", f"/me/analysis-results/{item['id']}")
        removed["분석 결과"] = removed.get("분석 결과", 0) + 1
    for item in api.ok("GET", "/me/writing-documents").get("items", []):
        api.ok("DELETE", f"/me/writing-documents/{item['id']}?expected_version={item['version']}")
        removed["저장 문서"] = removed.get("저장 문서", 0) + 1
    for resource in RECORDS:
        for item in api.all(f"/me/{resource}?limit=100"):
            if item["id"] not in kept[resource]:
                api.ok("DELETE", f"/me/{resource}/{item['id']}?expected_version={item['version']}")
                removed[resource] = removed.get(resource, 0) + 1
    for item in api.ok("GET", "/me/materials")["items"]:
        if item["id"] not in kept["materials"]:
            api.ok("DELETE", f"/me/materials/{item['id']}?expected_version={item['version']}")
            removed["materials"] = removed.get("materials", 0) + 1
    print("지운 것:", removed or "없음")


def restore_goal(api, state):
    # Accounts recorded before the goal was part of the baseline had no goal set.
    original = state["baseline"].get("goal", {"category_codes": [], "keyword": ""})
    goal = api.ok("GET", "/me/career-goal")
    if (
        goal.get("category_codes") != original["category_codes"]
        or goal.get("keyword") != original["keyword"]
    ):
        api.ok("PUT", "/me/career-goal", {**original, "expected_version": goal.get("version", 0)})
        print("목표 직무를 처음 값으로 되돌렸습니다.")


def portfolio_pdf():
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("playwright가 없어 PDF 없이 자료를 넣습니다.")
        return None
    with tempfile.TemporaryDirectory() as folder:
        out = Path(folder) / "portfolio.pdf"
        with sync_playwright() as p:
            browser = p.chromium.launch()
            page = browser.new_page()
            page.set_content(PORTFOLIO_HTML)
            page.pdf(path=str(out), format="A4", print_background=True)
            browser.close()
        return out.read_bytes()


def seed(api, state):
    baseline(api, state)
    today = datetime.now(KST).date()
    titles = {r: {i["title"] for i in api.all(f"/me/{r}?limit=100")} for r in RECORDS}
    added = []

    goal = api.ok("GET", "/me/career-goal")
    if (
        goal.get("category_codes") != GOAL["category_codes"]
        or goal.get("keyword") != GOAL["keyword"]
    ):
        api.ok("PUT", "/me/career-goal", {**GOAL, "expected_version": goal.get("version", 0)})
        added.append("목표 직무: 소프트웨어 · 백엔드")

    for resource, rows in [
        ("experience-records", EXPERIENCES),
        ("activity-records", ACTIVITIES),
        ("credential-records", CREDENTIALS),
        ("events", [{**e, "time_zone": "Asia/Seoul"} for e in events(today)]),
    ]:
        for row in rows:
            if row["title"] in titles[resource]:
                continue
            api.ok("POST", f"/me/{resource}", row)
            added.append(f"{resource}: {row['title']}")

    if MATERIAL["title"] not in {m["title"] for m in api.ok("GET", "/me/materials")["items"]}:
        body = {"id": str(uuid.uuid4()), **{k: v for k, v in MATERIAL.items() if k != "filename"}}
        pdf = portfolio_pdf()
        if pdf:
            body["file"] = {
                "filename": MATERIAL["filename"],
                "content_base64": base64.b64encode(pdf).decode(),
            }
        api.ok("POST", "/me/materials", body)
        added.append(f"내 자료: {MATERIAL['title']}" + (" (PDF)" if pdf else ""))
    print("넣은 것:", added or "없음(이미 모두 있음)")


def status(api):
    goal = api.ok("GET", "/me/career-goal")
    print("목표 직무:", goal.get("category_label"), goal.get("keyword") or "-")
    for resource in RECORDS:
        print(f"{resource}:", [i["title"] for i in api.all(f"/me/{resource}?limit=100")][:12])
    print("내 자료:", [m["title"] for m in api.ok("GET", "/me/materials")["items"]])
    print(
        "분석 결과:",
        [(r["kind"], r["title"]) for r in api.ok("GET", "/me/analysis-results").get("items", [])],
    )
    print(
        "저장 문서:", [d["title"] for d in api.ok("GET", "/me/writing-documents").get("items", [])]
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--reset", action="store_true", help="리허설 흔적을 지우고 처음 상태로")
    parser.add_argument("--status", action="store_true", help="지금 상태만 출력")
    parser.add_argument(
        "--clear", action="store_true", help="리허설·시드 데이터를 지우고 다시 넣지 않음"
    )
    args = parser.parse_args()
    if not ACCOUNT.exists():
        sys.exit(f"{ACCOUNT}에 계정 정보가 없습니다.")
    api = Api(json.loads(ACCOUNT.read_text()))
    state = load_state()
    if args.status:
        status(api)
        return
    started = time.monotonic()
    if args.reset or args.clear:
        reset(api, state)
    if args.clear:
        restore_goal(api, state)
    else:
        seed(api, state)
    print(f"완료 ({time.monotonic() - started:.1f}초)")


if __name__ == "__main__":
    main()
