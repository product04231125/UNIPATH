#!/usr/bin/env python3
"""시연 학생 계정에 시연용 합성 데이터를 넣고, 시연 학교 관리자 계정을 준비한다.

    python3 scripts/demo/seed_demo_student.py           # 빠진 시연 데이터만 넣는다
    python3 scripts/demo/seed_demo_student.py --reset   # 리허설 흔적을 지우고 처음 상태로 되돌린다
    python3 scripts/demo/seed_demo_student.py --status  # 지금 상태만 본다
    python3 scripts/demo/seed_demo_student.py --pin     # 최신 분석 결과·저장 문서를 시연용으로 고정
    python3 scripts/demo/seed_demo_student.py --clear   # 시연 뒤 정리(다시 넣지 않음)

기본은 스테이징 서버(staging-unipath.duckdns.org)이고, --live를 붙이면 라이브 서버
(unipath.duckdns.org)에서 같은 일을 한다.

    python3 scripts/demo/seed_demo_student.py --live --reset

계정 정보는 서버별 폴더에서 읽고 출력하지 않는다. 스테이징은 ~/.config/unipath-staging-demo/,
라이브는 ~/.config/unipath-live-demo/.
- account.json({"base_url", "email", "password"}): 시연 학생. 역할이 학생(user)이 아니면 멈춘다.
  base_url은 생략할 수 있고, 적었다면 고른 서버 주소와 같아야 한다(다른 서버 계정 파일이면 멈춘다).
- admin.json({"email", "display_name", "institution", "password"?}): 시연 학교 관리자(선택).
  password는 계정을 새로 만들 때만 쓴다.

학생 데이터는 그 서버의 공개 API로만 다룬다. 처음 실행할 때 계정에 원래 있던 자료(수강 기록·자격·
내 자료 등)의 id를 state.json에 "원래 자료"로 기록해 두고, --reset은 그 밖의 것만 지운다.
--reset이 지우는 것: 시연 학생의 저장된 분석 결과 전부, 저장한 자기소개서·포트폴리오 전부, 원래
자료가 아닌 일정·활동·경험·자격·성과·내 자료(이 스크립트가 넣은 것 + 리허설 중 추가한 것). 그다음
시연 데이터를 다시 넣는다. 일정 날짜는 실행한 날(한국 시간) 기준이라
시연 당일 아침에 --reset 하면 된다. 학업 프로필 학년은 졸업예정으로 맞춘다(인물이 졸업예정이고,
공고 찾기·활동 추천·자격증 추천의 현재 학년이 이 값으로 채워진다). --clear는 자동 계산으로 되돌린다.

--pin은 앱에서 실행해 저장한 최신 목표 직무 분석·공고 찾기 결과와 최신 자기소개서·포트폴리오
문서를 시연에서 열 결과로 고정한다. 분석 결과에는 별표(즐겨찾기)를 붙이고, 결과와 문서가 인용하는
지금의 경험·활동·자격·성과·내 자료도 함께 남겨 --reset 뒤에도 인용이 그대로 맞는다(일정은 실행한
날 기준으로 다시 만든다). --clear는 고정한 결과·문서와 기록까지 지우고 고정을 푼다.

학교 관리자는 초기화하지 않는다. 이 컴퓨터에 있는 그 서버의 API 컨테이너 안에서 admin.json의
계정이 그 학교의 학교 관리자인지만 확인하고(로그인하지 않음), 없을 때만 승인과 같은 방식(학교
권한 + 감사 기록, 부여자는 기존 슈퍼관리자)으로 만든다(승인은 슈퍼관리자만 가능해 공개 API로는
만들 수 없다).
이미 있는 계정의 비밀번호·역할은 바꾸지 않는다(학생 역할이면 학교 관리자 권한만 부여).
어떤 모드도 계정을 지우지 않으며, 슈퍼관리자 계정은 만들거나 바꾸거나 지우지 않는다.
모든 내용은 시연용 합성 데이터다.
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

# The demo servers: address, account folder and the API container on this host.
SERVERS = {
    "staging": {
        "url": "https://staging-unipath.duckdns.org",
        "config": "~/.config/unipath-staging-demo",
        "container": "unipath-staging-api-1",
    },
    "live": {
        "url": "https://unipath.duckdns.org",
        "config": "~/.config/unipath-live-demo",
        "container": "unipath-product-api-1",
    },
}
# Set by use_server(). UNIPATH_DEMO_CONFIG / UNIPATH_DEMO_API_CONTAINER override the folder and
# container (for testing the script on a check account).
CONFIG = ACCOUNT = ADMIN = STATE = API_CONTAINER = None
KST = ZoneInfo("Asia/Seoul")
RECORDS = [
    "events",
    "activity-records",
    "experience-records",
    "credential-records",
    "achievement-records",
]


def use_server(name):
    """Point the account files and API container at one server; returns its address."""
    global CONFIG, ACCOUNT, ADMIN, STATE, API_CONTAINER
    server = SERVERS[name]
    CONFIG = Path(os.environ.get("UNIPATH_DEMO_CONFIG", server["config"])).expanduser()
    ACCOUNT, ADMIN, STATE = (CONFIG / n for n in ("account.json", "admin.json", "state.json"))
    API_CONTAINER = os.environ.get("UNIPATH_DEMO_API_CONTAINER", server["container"])
    return server["url"]


class Api:
    def __init__(self, base_url):
        self.base = base_url.rstrip("/") + "/api/v1"
        self.token = self.owner = self.role = None

    def login(self, account):
        """HTTP status of the login; on success the session and the account's role are kept."""
        status, body = self.call(
            "POST",
            "/auth/login",
            {"email": account["email"], "password": account["password"], "session_mode": "bearer"},
        )
        if status == 200:
            self.token, self.owner = body["access_token"], body["user"]["id"]
            self.role = body["user"]["role"]
        return status, body

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
# The persona is 졸업예정: 공고 찾기·활동 추천·자격증 추천 start at the profile's 학년.
ACADEMIC_STAGE = "graduating"

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


# ---- 시연 학교 관리자 ------------------------------------------------------------------------

# Runs inside the server's API container; reads one JSON line from stdin (a password never goes on
# a command line). Prints one word: ok, super (left alone), other (admin of another school: left
# alone), granted or created. Granting mirrors the super administrator's signup approval: an
# active school scope granted by the existing super administrator, its audit row, then the role.
ADMIN_SERVER_CODE = """
import json, sys
from datetime import UTC, datetime
from sqlalchemy import select
from app.core.config import Settings
from app.core.database import create_session_factory
from app.models.identity import AdminScope, Institution, Role, User
from app.services.access import audit, lock_identity
from app.services.auth import PASSWORDS

p = json.loads(sys.stdin.readline())
factory = create_session_factory(Settings())
with factory() as db:
    lock_identity(db)
    school = db.scalar(select(Institution).where(
        Institution.name == p["institution"], Institution.deleted_at.is_(None)))
    if school is None:
        sys.exit("no-school")
    user = db.scalar(select(User).where(User.email == p["email"]).with_for_update())
    if user is not None and user.role == Role.SUPER_ADMIN:
        sys.exit(print("super"))
    scoped = user is not None and db.scalar(select(AdminScope.id).where(
        AdminScope.user_id == user.id, AdminScope.institution_id == school.id,
        AdminScope.status == "active"))
    if user is not None and user.role == Role.SCHOOL_ADMIN:
        sys.exit(print("ok" if scoped else "other"))
    granter = db.scalar(select(User).where(
        User.role == Role.SUPER_ADMIN, User.account_status == "active").order_by(User.created_at))
    if granter is None:
        sys.exit("no-super-admin")
    word = "granted"
    if user is None:
        if not p.get("password"):
            sys.exit("no-account-and-no-password")
        user = User(email=p["email"], display_name=p["display_name"], role=Role.USER,
                    password_hash=PASSWORDS.hash(p["password"]))
        db.add(user)
        db.flush()
        word = "created"
    scope = AdminScope(user_id=user.id, institution_id=school.id, reason=p["reason"],
                       granted_by=granter.id)
    db.add(scope)
    db.flush()
    audit(db, granter.id, "scope_granted", scope.id, None, school.id)
    user.role = Role.SCHOOL_ADMIN
    user.version += 1
    user.updated_at = datetime.now(UTC)
    db.commit()
    print(word)
"""

ADMIN_RESULT = {
    "ok": "학교 관리자 확인",
    "super": "슈퍼관리자 계정이라 건드리지 않았습니다",
    "other": "다른 학교의 관리자라 건드리지 않았습니다",
    "granted": "학교 관리자 권한을 부여했습니다",
    "created": "학교 관리자로 만들었습니다",
}


def ensure_admin():
    """Check the demo school administrator on the server; create it only when missing."""
    if not ADMIN.exists():
        print(f"시연 관리자: {ADMIN}가 없어 건너뜁니다.")
        return
    admin = json.loads(ADMIN.read_text())
    payload = {
        "email": admin["email"],
        "display_name": admin.get("display_name", "시연 관리자"),
        "institution": admin["institution"],
        "password": admin.get("password", ""),
        "reason": "시연 전용 학교 관리자(scripts/demo/seed_demo_student.py)",
    }
    command = ["docker", "exec", "-i", "-w", "/app", "-e", "PYTHONPATH=/app", API_CONTAINER]
    result = subprocess.run(
        [*command, "python", "-c", ADMIN_SERVER_CODE],
        input=json.dumps(payload, ensure_ascii=False) + "\n",
        capture_output=True,
        text=True,
        timeout=120,
    )
    word = result.stdout.strip()
    if result.returncode != 0 and word not in ADMIN_RESULT:
        reason = (result.stderr.strip().splitlines() or ["?"])[-1]
        sys.exit(f"시연 관리자 확인 실패: {reason}")
    print(f"시연 관리자: {admin['email']} ({admin['institution']}) {ADMIN_RESULT[word]}")


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


# Saved results opened in the demo instead of running the analysis live.
PINNED_KINDS = {"gap": "목표 직무 분석", "search": "공고 찾기"}
# Records a saved analysis can cite; events are not cited and keep their run-day dates.
CITED = [r for r in RECORDS if r != "events"]


def pin(api, state):
    """Keep the newest 목표 직무 분석·공고 찾기 results, documents and the records they cite."""
    kept = baseline(api, state)
    results = api.ok("GET", "/me/analysis-results").get("items", [])
    pinned = {"analysis-results": [], "writing-documents": [], "materials": []}
    for kind, label in PINNED_KINDS.items():
        newest = max(
            (r for r in results if r["kind"] == kind), key=lambda r: r["created_at"], default=None
        )
        if newest is None:
            print(f"{label} 저장 결과가 없습니다. 앱에서 먼저 실행하세요.")
            continue
        if not newest["favorite"]:
            api.ok("PATCH", f"/me/analysis-results/{newest['id']}", {"favorite": True})
        pinned["analysis-results"].append(newest["id"])
        print(f"고정: {label} · {newest['title']} ({newest['created_at'][:16]})")
    documents = api.ok("GET", "/me/writing-documents").get("items", [])
    for kind in sorted({d["document_type"] for d in documents}):
        newest = max(
            (d for d in documents if d["document_type"] == kind), key=lambda d: d["updated_at"]
        )
        pinned["writing-documents"].append(newest["id"])
        print(f"고정: 저장 문서({kind}) · {newest['title']} ({newest['updated_at'][:16]})")
    for resource in CITED:
        pinned[resource] = [
            i["id"] for i in api.all(f"/me/{resource}?limit=100") if i["id"] not in kept[resource]
        ]
    pinned["materials"] = [
        m["id"] for m in api.ok("GET", "/me/materials")["items"] if m["id"] not in kept["materials"]
    ]
    state["pinned"] = pinned
    save_state(state)
    records = {
        k: len(v) for k, v in pinned.items() if k not in ("analysis-results", "writing-documents")
    }
    print("함께 남길 기록:", records)


def reset(api, state, keep_pinned=True):
    kept = baseline(api, state)
    pinned = state.get("pinned", {}) if keep_pinned else {}
    removed = {}
    for item in api.ok("GET", "/me/analysis-results").get("items", []):
        if item["id"] in pinned.get("analysis-results", []):
            if not item["favorite"]:
                api.ok("PATCH", f"/me/analysis-results/{item['id']}", {"favorite": True})
            continue
        api.ok("DELETE", f"/me/analysis-results/{item['id']}")
        removed["분석 결과"] = removed.get("분석 결과", 0) + 1
    for item in api.ok("GET", "/me/writing-documents").get("items", []):
        if item["id"] in pinned.get("writing-documents", []):
            continue
        api.ok("DELETE", f"/me/writing-documents/{item['id']}?expected_version={item['version']}")
        removed["저장 문서"] = removed.get("저장 문서", 0) + 1
    for resource in RECORDS:
        for item in api.all(f"/me/{resource}?limit=100"):
            if item["id"] not in kept[resource] + pinned.get(resource, []):
                api.ok("DELETE", f"/me/{resource}/{item['id']}?expected_version={item['version']}")
                removed[resource] = removed.get(resource, 0) + 1
    for item in api.ok("GET", "/me/materials")["items"]:
        if item["id"] not in kept["materials"] + pinned.get("materials", []):
            api.ok("DELETE", f"/me/materials/{item['id']}?expected_version={item['version']}")
            removed["materials"] = removed.get("materials", 0) + 1
    if not keep_pinned and state.pop("pinned", None) is not None:
        save_state(state)
        print("시연용 저장 결과 고정을 풀었습니다.")
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
    # The baseline predates the profile 학년: it was counted from the admission year.
    if set_stage(api, state["baseline"].get("academic_stage")):
        print("학업 프로필 학년을 처음 값(입학연도로 자동 계산)으로 되돌렸습니다.")


def set_stage(api, stage):
    """Set the profile's 학년; True when it changed. A server without 학년 단계 is left alone."""
    profile = api.ok("GET", "/me/planning-profile")
    if "academic_stage" not in profile or profile["academic_stage"] == stage:
        return False
    body = {"academic_stage": stage, "expected_version": profile["version"]}
    api.ok("PATCH", "/me/planning-profile", body)
    return True


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
    if set_stage(api, ACADEMIC_STAGE):
        added.append("학업 프로필 학년: 졸업예정")

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


def status(api, state):
    goal = api.ok("GET", "/me/career-goal")
    print("목표 직무:", goal.get("category_label"), goal.get("keyword") or "-")
    stage = api.ok("GET", "/me/planning-profile").get("academic_stage")
    print("학업 프로필 학년:", stage or "입학연도로 자동 계산")
    for resource in RECORDS:
        print(f"{resource}:", [i["title"] for i in api.all(f"/me/{resource}?limit=100")][:12])
    print("내 자료:", [m["title"] for m in api.ok("GET", "/me/materials")["items"]])
    pinned = set(state.get("pinned", {}).get("analysis-results", []))
    print(
        "분석 결과:",
        [
            (r["kind"], r["title"], "고정" if r["id"] in pinned else "")
            for r in api.ok("GET", "/me/analysis-results").get("items", [])
        ],
    )
    kept = set(state.get("pinned", {}).get("writing-documents", []))
    print(
        "저장 문서:",
        [
            (d["document_type"], d["title"], "고정" if d["id"] in kept else "")
            for d in api.ok("GET", "/me/writing-documents").get("items", [])
        ],
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--reset", action="store_true", help="리허설 흔적을 지우고 처음 상태로")
    parser.add_argument("--status", action="store_true", help="지금 상태만 출력")
    parser.add_argument(
        "--pin", action="store_true", help="최신 분석 결과·저장 문서를 시연용으로 고정"
    )
    parser.add_argument(
        "--clear", action="store_true", help="리허설·시드 데이터를 지우고 다시 넣지 않음"
    )
    parser.add_argument(
        "--live", action="store_true", help="라이브 서버(unipath.duckdns.org)에서 실행"
    )
    args = parser.parse_args()
    url = use_server("live" if args.live else "staging")
    print(f"서버: {url}")
    if not ACCOUNT.exists():
        sys.exit(f"{ACCOUNT}에 계정 정보가 없습니다.")
    account = json.loads(ACCOUNT.read_text())
    # An account file names its server: a staging file never runs against live, or the reverse.
    if account.get("base_url", url).rstrip("/") != url:
        sys.exit(f"{ACCOUNT}는 {url}의 계정 파일이 아닙니다. 아무것도 바꾸지 않았습니다.")
    api = Api(url)
    code, body = api.login(account)
    if code != 200:
        sys.exit(f"로그인 실패: HTTP {code} {body.get('error', {}).get('code', '')}")
    # Records are deleted only on a student account: never on an administrator's.
    if api.role != "user":
        sys.exit(
            f"{account['email']}는 학생 계정이 아닙니다(역할 {api.role}). "
            "아무것도 바꾸지 않았습니다."
        )
    state = load_state()
    if args.status:
        status(api, state)
        return
    if args.pin:
        pin(api, state)
        return
    started = time.monotonic()
    if args.reset or args.clear:
        reset(api, state, keep_pinned=not args.clear)
    if args.clear:
        restore_goal(api, state)
    else:
        seed(api, state)
        ensure_admin()
    print(f"완료 ({time.monotonic() - started:.1f}초)")


if __name__ == "__main__":
    main()
