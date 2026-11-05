from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
from uuid import uuid4

import pytest
from pydantic import ValidationError
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register

from app.models.personal import PersonalCurriculumCourse, PlanningProfile
from app.schemas import personal as dto


def test_personal_contracts_reject_spoofed_ownership_and_untrusted_school_flags():
    for extra in ({"owner_id": str(uuid4())}, {"official": True}, {"approved": True}):
        with pytest.raises(ValidationError):
            dto.CourseRecordCreate.model_validate(
                {
                    "title": "합성 수강",
                    "term": "2026-1",
                    "category": "전공",
                    "credits": "3",
                    **extra,
                }
            )


@pytest.mark.parametrize("value", ["NaN", "Infinity", "-1", "0", "100.001", True, "1.0001"])
def test_course_credits_are_finite_positive_decimal(value):
    with pytest.raises(ValidationError):
        dto.CourseRecordCreate(title="합성", term="2026", category="전공", credits=value)


@pytest.mark.parametrize(
    "changes",
    [
        {"starts_at": "2026-10-19T09:00:00"},
        {"starts_at": 1792390000},
        {"starts_at": "1792390000"},
        {"time_zone": "unknown/test"},
        {"ends_at": "2026-10-19T08:00:00+09:00"},
    ],
)
def test_events_require_known_timezone_and_explicit_instant(changes):
    with pytest.raises(ValidationError):
        dto.EventCreate.model_validate(
            {
                "title": "합성 일정",
                "starts_at": "2026-10-19T09:00:00+09:00",
                "ends_at": "2026-10-19T10:00:00+09:00",
                "time_zone": "Asia/Seoul",
                "category": "academic",
                **changes,
            }
        )


@pytest.mark.parametrize(
    "changes",
    [
        {"started_on": "2026-02-30"},
        {"started_on": "2026-02-01T00:00:00Z"},
        {"started_on": 1234567},
        {"evidence_url": "https://user:password@example.test/file"},
    ],
)
def test_personal_dates_and_urls_are_bounded(changes):
    with pytest.raises(ValidationError):
        dto.AchievementRecordCreate.model_validate(
            {
                "title": "합성 성과",
                "achievement_type": "프로젝트",
                "role": "담당",
                "result": "합성 결과",
                **changes,
            }
        )


def post(client, headers, resource, body, expected=201):
    response = client.post("/api/v1/me/" + resource, headers=headers, json=body)
    assert response.status_code == expected, response.text
    return response.json()


def samples(client, headers):
    course = post(
        client,
        headers,
        "course-records",
        {
            "title": "합성 수강",
            "term": "2026-1",
            "category": "전공",
            "credits": "3.5",
            "completion": "recorded",
            "grade": "A+",
        },
    )
    curriculum = post(
        client,
        headers,
        "personal-curricula",
        {
            "title": "합성 개인 과정",
            "school": "합성대",
            "department": "합성학과",
            "admission_year": 2024,
            "curriculum_year": 2024,
        },
    )
    curriculum_course = post(
        client,
        headers,
        "personal-curriculum-courses",
        {
            "title": "합성 필수",
            "curriculum_id": curriculum["id"],
            "course_record_id": course["id"],
            "category": "전공",
            "credits": "3.5",
            "required": True,
        },
    )
    achievement = post(
        client,
        headers,
        "achievement-records",
        {
            "title": "합성 성과",
            "achievement_type": "프로젝트",
            "role": "담당",
            "result": "합성 결과",
        },
    )
    experience = post(
        client,
        headers,
        "experience-records",
        {
            "title": "합성 경험",
            "experience_type": "연구",
            "status_label": "진행 중",
        },
    )
    return course, curriculum, curriculum_course, achievement, experience


integration = pytest.mark.integration


@integration
def test_all_personal_collections_roundtrip_partial_patch_and_no_store(auth_client, auth_db):
    c = auth_client
    h = authorization(register(c))
    course, curriculum, link, achievement, experience = samples(c, h)
    other = {
        "events": {
            "title": "합성 일정",
            "starts_at": "2026-10-19T09:00:00+09:00",
            "ends_at": "2026-10-19T10:00:00+09:00",
            "time_zone": "Asia/Seoul",
            "category": "academic",
        },
        "activity-records": {
            "title": "합성 봉사",
            "reported_hours": "10.5",
            "approved_hours": "8.25",
            "approval": "approved",
            "observed_on": "2026-10-19",
        },
        "credential-records": {
            "title": "합성 자격",
            "earned_on": "2026-10-18",
            "evidence_url": "https://example.test/proof",
        },
        "personal-graduation-rules": {
            "title": "합성 규칙",
            "curriculum_id": curriculum["id"],
            "curriculum_course_id": link["id"],
            "rule_type": "학점",
            "scope": "curriculum",
            "condition": "개인 기준 설명",
            "related_record": {"kind": "course", "record_id": course["id"]},
        },
        "portfolio-compositions": {
            "title": "합성 구성",
            "sources": [{"kind": "achievement", "record_id": achievement["id"]}],
            "audience": "public_review",
            "reviewed": True,
        },
        "application-documents": {
            "title": "합성 지원",
            "target": "합성 지원처",
            "role": "개발",
            "document_type": "자기소개서",
            "body": "작성 내용 보존",
            "sources": [
                {"kind": "experience", "record_id": experience["id"]},
                {"kind": "achievement", "record_id": achievement["id"]},
            ],
        },
    }
    for path, body in other.items():
        item = post(c, h, path, body)
        assert item["official"] is False and item["origin"] == "personal"
        response = c.get("/api/v1/me/" + path + "/" + item["id"], headers=h)
        assert response.status_code == 200 and response.headers["Cache-Control"] == "no-store"
        assert "creation_digest" not in response.json()
        changed = c.patch(
            "/api/v1/me/" + path + "/" + item["id"],
            headers=h,
            json={"expected_version": 1, "detail": "부분 수정"},
        )
        assert changed.status_code == 200, changed.text
        assert changed.json()["version"] == 2 and changed.json()["title"] == body["title"]
        if "sources" in body:
            assert changed.json()["sources"] == body["sources"]
        if path == "portfolio-compositions":
            assert changed.json()["reviewed"] is False
        assert (
            c.patch(
                "/api/v1/me/" + path + "/" + item["id"],
                headers=h,
                json={"expected_version": 1, "detail": "충돌"},
            ).status_code
            == 409
        )
    assert (
        c.patch(
            "/api/v1/me/course-records/" + course["id"],
            headers=h,
            json={"expected_version": 1, "credits": None},
        ).status_code
        == 422
    )


@integration
def test_owner_isolation_including_superadmin_and_cross_owner_references(auth_client, auth_db):
    from test_academic import operator

    c = auth_client
    first = authorization(register(c))
    second = authorization(register(c, "other@example.test"))
    operator_headers = operator(c, auth_db)
    course, curriculum, _, achievement, _ = samples(c, first)
    for h in (second, operator_headers):
        assert c.get("/api/v1/me/course-records", headers=h).json()["items"] == []
        for suffix in ("", "/references"):
            assert (
                c.get("/api/v1/me/course-records/" + course["id"] + suffix, headers=h).status_code
                == 404
            )
        assert (
            c.patch(
                "/api/v1/me/course-records/" + course["id"],
                headers=h,
                json={"expected_version": 1, "title": "다른 계정"},
            ).status_code
            == 404
        )
        assert (
            c.delete(
                "/api/v1/me/course-records/" + course["id"] + "?expected_version=1", headers=h
            ).status_code
            == 404
        )
    post(
        c,
        second,
        "personal-curriculum-courses",
        {
            "title": "다른 계정 참조",
            "curriculum_id": curriculum["id"],
            "category": "전공",
            "credits": "3",
            "required": True,
        },
        404,
    )
    post(
        c,
        second,
        "portfolio-compositions",
        {
            "title": "다른 계정 참조",
            "sources": [{"kind": "achievement", "record_id": achievement["id"]}],
        },
        404,
    )
    assert c.get("/api/v1/me/course-records").status_code == 401


@integration
def test_retry_receipts_pagination_and_deleted_record_cannot_be_resurrected(auth_client):
    c = auth_client
    h = authorization(register(c))
    client_id = str(uuid4())
    body = {"title": "합성 자격 %_", "client_id": client_id}
    first = post(c, h, "credential-records", body)
    assert post(c, h, "credential-records", body)["id"] == first["id"]
    post(c, h, "credential-records", {**body, "title": "다른 요청"}, 409)
    for n in range(3):
        post(c, h, "credential-records", {"title": f"합성 자격 {n}"})
    ids = []
    cursor = None
    while True:
        response = c.get(
            "/api/v1/me/credential-records",
            headers=h,
            params={"limit": 2, **({"cursor": cursor} if cursor else {})},
        ).json()
        ids += [item["id"] for item in response["items"]]
        cursor = response["next_cursor"]
        if not cursor:
            break
    assert len(set(ids)) == 4
    result = c.get("/api/v1/me/credential-records", headers=h, params={"query": "%_"}).json()
    assert [x["id"] for x in result["items"]] == [first["id"]]
    assert (
        c.delete(
            "/api/v1/me/credential-records/" + first["id"] + "?expected_version=1", headers=h
        ).status_code
        == 204
    )
    post(c, h, "credential-records", body, 409)
    other = authorization(register(c, "other@example.test"))
    assert post(c, other, "credential-records", body)["id"] != first["id"]


@integration
def test_profile_creation_version_partial_updates_and_calendar_window(auth_client, auth_db):
    c = auth_client
    h = authorization(register(c))
    initial = c.get("/api/v1/me/planning-profile", headers=h).json()
    assert initial["version"] == 0
    with auth_db() as db:
        assert db.scalar(select(func.count()).select_from(PlanningProfile)) == 0
    response = c.patch(
        "/api/v1/me/planning-profile",
        headers=h,
        json={"expected_version": 0, "school": "개인 학교명", "admission_year": 2024},
    )
    assert response.status_code == 200, response.text
    response = c.patch(
        "/api/v1/me/planning-profile",
        headers=h,
        json={"expected_version": 1, "week_starts_on": "monday"},
    )
    assert response.json()["school"] == "개인 학교명" and response.json()["version"] == 2
    assert (
        c.patch(
            "/api/v1/me/planning-profile",
            headers=h,
            json={"expected_version": 0, "school": "덮어쓰기"},
        ).status_code
        == 409
    )
    event = post(
        c,
        h,
        "events",
        {
            "title": "합성 일정",
            "starts_at": "2026-10-19T00:00:00+09:00",
            "ends_at": "2026-10-19T01:00:00+09:00",
            "time_zone": "Asia/Seoul",
            "category": "deadline",
        },
    )
    window = c.get(
        "/api/v1/me/events",
        headers=h,
        params={
            "ends_after": "2026-10-18T14:59:00Z",
            "starts_before": "2026-10-18T16:00:00Z",
        },
    )
    assert [x["id"] for x in window.json()["items"]] == [event["id"]]
    assert datetime.fromisoformat(event["starts_at"]).astimezone(UTC).hour == 15
    assert event["time_zone"] == "Asia/Seoul"


@integration
def test_reference_constraints_source_order_and_review_invalidation(auth_client, auth_db):
    c = auth_client
    h = authorization(register(c))
    course, curriculum, link, achievement, experience = samples(c, h)
    composition = post(
        c,
        h,
        "portfolio-compositions",
        {
            "title": "합성 구성",
            "reviewed": True,
            "sources": [{"kind": "achievement", "record_id": achievement["id"]}],
        },
    )
    doc = post(
        c,
        h,
        "application-documents",
        {
            "title": "합성 지원",
            "target": "합성",
            "role": "개발",
            "document_type": "초안",
            "body": "원본 본문 유지",
            "sources": [
                {"kind": "achievement", "record_id": achievement["id"]},
                {"kind": "experience", "record_id": experience["id"]},
            ],
        },
    )
    assert (
        c.delete(
            "/api/v1/me/achievement-records/" + achievement["id"] + "?expected_version=1", headers=h
        ).status_code
        == 409
    )
    response = c.patch(
        "/api/v1/me/achievement-records/" + achievement["id"],
        headers=h,
        json={"expected_version": 1, "result": "수정한 합성 결과"},
    )
    assert response.status_code == 200
    current = c.get("/api/v1/me/portfolio-compositions/" + composition["id"], headers=h).json()
    assert current["reviewed"] is False and current["version"] == 2
    current_doc = c.get("/api/v1/me/application-documents/" + doc["id"], headers=h).json()
    assert current_doc["body"] == "원본 본문 유지"
    changed = c.patch(
        "/api/v1/me/application-documents/" + doc["id"],
        headers=h,
        json={"expected_version": 1, "sources": list(reversed(current_doc["sources"]))},
    )
    assert changed.status_code == 200, changed.text
    assert changed.json()["sources"] == list(reversed(current_doc["sources"]))
    # Removing containers removes membership rows, never the original records.
    assert (
        c.delete(
            "/api/v1/me/application-documents/" + doc["id"] + "?expected_version=2", headers=h
        ).status_code
        == 204
    )
    assert (
        c.delete(
            "/api/v1/me/portfolio-compositions/" + composition["id"] + "?expected_version=2",
            headers=h,
        ).status_code
        == 204
    )
    assert (
        c.delete(
            "/api/v1/me/achievement-records/" + achievement["id"] + "?expected_version=2", headers=h
        ).status_code
        == 204
    )
    assert (
        c.delete(
            "/api/v1/me/personal-curricula/" + curriculum["id"] + "?expected_version=1", headers=h
        ).status_code
        == 409
    )
    other = register(c, "other@example.test").json()["user"]["id"]
    with auth_db() as db:
        db.add(
            PersonalCurriculumCourse(
                title="다른 소유자 FK",
                owner_id=other,
                curriculum_id=curriculum["id"],
                credits=3,
                category="전공",
                required=True,
            )
        )
        with pytest.raises(IntegrityError):
            db.commit()
        db.rollback()


@integration
def test_simultaneous_retries_create_one_record_and_partial_nulls_are_validated(auth_client):
    c = auth_client
    h = authorization(register(c))
    body = {"title": "동시 생성", "client_id": str(uuid4()), "earned_on": "2026-01-01"}
    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(
            executor.map(
                lambda _: c.post("/api/v1/me/credential-records", headers=h, json=body), range(2)
            )
        )
    assert [r.status_code for r in results] == [201, 201]
    assert len({r.json()["id"] for r in results}) == 1
    record_id = results[0].json()["id"]
    response = c.patch(
        "/api/v1/me/credential-records/" + record_id,
        headers=h,
        json={"expected_version": 1, "earned_on": None},
    )
    assert response.status_code == 200 and response.json()["earned_on"] is None
    response = c.patch(
        "/api/v1/me/credential-records/" + record_id,
        headers=h,
        json={
            "expected_version": 2,
            "evidence_url": "https://private-user:private-password@example.test",
        },
    )
    assert response.status_code == 422 and "private-password" not in response.text
    assert response.json()["error"]["request_id"] == response.headers["X-Request-ID"]
