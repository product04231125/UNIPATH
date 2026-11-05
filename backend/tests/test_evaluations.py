from uuid import uuid4

import pytest
from pydantic import ValidationError
from sqlalchemy import select
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register
from test_personal import post, samples

from app.models.evaluations import PersonalEvaluation
from app.schemas.evaluations import PersonalEvaluationCreate
from app.services.evaluations import replay


def saved_rule(client, headers, curriculum, title="합성 개인 기준", **extra):
    return post(
        client,
        headers,
        "personal-graduation-rules",
        {
            "title": title,
            "curriculum_id": curriculum["id"],
            "rule_type": "직접 기록한 설명",
            "scope": "curriculum",
            "condition": "이 문장은 계산 코드가 아닙니다.",
            "current_value": "99999",
            **extra,
        },
    )


def criterion(rule, **condition):
    return {"rule_id": rule["id"], "expected_version": rule["version"], "condition": condition}


def calculate(client, headers, curriculum, calculations=(), expected=201, **extra):
    body = {
        "curriculum_id": curriculum["id"],
        "expected_curriculum_version": curriculum["version"],
        "as_of": "2026-10-19",
        "calculations": list(calculations),
        **extra,
    }
    response = client.post("/api/v1/me/personal-evaluations", headers=headers, json=body)
    assert response.status_code == expected, response.text
    return response.json()


def test_calculation_contract_forbids_official_owner_and_conflicting_observations():
    curriculum, record = str(uuid4()), str(uuid4())
    base = {"curriculum_id": curriculum, "expected_curriculum_version": 1}
    for extra in (
        {"official": True},
        {"owner_id": str(uuid4())},
        {"expected_curriculum_version": True},
    ):
        with pytest.raises(ValidationError):
            PersonalEvaluationCreate.model_validate({**base, **extra})
    cases = [
        criterion(
            {"id": str(uuid4()), "version": 1},
            kind="required_courses",
            courses=[{"curriculum_course_id": str(uuid4())}],
            grades=[{"course_record_id": record, "points": points, "scale": "4.5"}],
        )
        for points in ["3", "4"]
    ]
    with pytest.raises(ValidationError):
        PersonalEvaluationCreate.model_validate({**base, "calculations": cases})


integration = pytest.mark.integration


@integration
def test_saved_values_do_not_execute_and_missing_conditions_are_not_omitted(auth_client):
    c = auth_client
    h = authorization(register(c))
    course, curriculum, link, _, _ = samples(c, h)
    credit = saved_rule(c, h, curriculum, "합성 학점 기준")
    required = saved_rule(c, h, curriculum, "합성 필수 기준")
    manual = saved_rule(c, h, curriculum, "합성 직접 검토", condition="return True")
    response = calculate(
        c,
        h,
        curriculum,
        [
            criterion(credit, kind="minimum_credits", minimum="4"),
            criterion(
                required,
                kind="required_courses",
                courses=[
                    {
                        "curriculum_course_id": link["id"],
                        "minimum_grade_points": "3",
                        "comparison_grade_scale": "4.5",
                    }
                ],
            ),
        ],
    )
    assert response["official"] is False and response["status"] == "not_satisfied"
    by_id = {item["rule_id"]: item for item in response["results"]}
    assert by_id[credit["id"]]["current"] == "3.500"
    assert by_id[required["id"]]["status"] == "needs_review"  # Raw A+ is not a numeric grade.
    assert by_id[required["id"]]["uncertain_course_ids"] == [link["id"]]
    assert by_id[manual["id"]]["reason"] == "explicit_condition_required"
    assert by_id[manual["id"]]["current"] is None
    assert response["label"] == "개인 기준 계산 · 학교 공식 판정 아님"
    assert not {"input_snapshot_json", "result_json", "password_hash"} & response.keys()
    calculate(
        c,
        h,
        curriculum,
        [criterion(credit, kind="minimum_credits", minimum="3")],
        expected=409,
        expected_source_versions=[
            {"kind": "course-records", "record_id": course["id"], "version": 99}
        ],
    )


@integration
def test_five_typed_condition_kinds_can_use_personal_observations(auth_client):
    c = auth_client
    h = authorization(register(c))
    course, curriculum, link, achievement, _ = samples(c, h)
    activity = post(
        c,
        h,
        "activity-records",
        {
            "title": "합성 봉사",
            "reported_hours": "9999",
            "approved_hours": "12",
            "approval": "approved",
            "observed_on": "2026-10-18",
        },
    )
    credential = post(
        c,
        h,
        "credential-records",
        {
            "title": "합성 자격",
            "earned_on": "2026-01-01",
            "expires_on": "2027-01-01",
            "status_label": "보유",
        },
    )
    patched = c.patch(
        "/api/v1/me/achievement-records/" + achievement["id"],
        headers=h,
        json={
            "expected_version": 1,
            "thesis_type": "capstone",
            "thesis_grade": "A",
            "thesis_approved_on": "2026-10-18",
        },
    )
    assert patched.status_code == 200
    conditions = [
        {"kind": "minimum_credits", "minimum": "3.5"},
        {
            "kind": "required_courses",
            "courses": [
                {
                    "curriculum_course_id": link["id"],
                    "minimum_credits": "3.5",
                    "minimum_grade_points": "3",
                    "comparison_grade_scale": "4.5",
                }
            ],
            "grades": [{"course_record_id": course["id"], "points": "3.2", "scale": "4.5"}],
        },
        {"kind": "minimum_volunteer_hours", "minimum": "10", "activity_ids": [activity["id"]]},
        {
            "kind": "any_certificate",
            "certificates": [
                {"credential_id": credential["id"], "possession": "held", "validity_known": True}
            ],
        },
        {
            "kind": "thesis",
            "thesis_type": "capstone",
            "accepted_grades": ["A"],
            "records": [
                {
                    "achievement_id": achievement["id"],
                    "completion": "completed",
                    "approval": "approved",
                }
            ],
        },
    ]
    calculations = [
        criterion(saved_rule(c, h, curriculum, f"합성 기준 {n}"), **condition)
        for n, condition in enumerate(conditions)
    ]
    response = calculate(c, h, curriculum, calculations)
    assert response["status"] == "satisfied" and response["official"] is False
    assert len(response["results"]) == 5 and all(
        item["status"] == "satisfied" for item in response["results"]
    )
    result = {item["condition"]["kind"]: item for item in response["results"]}
    assert result["minimum_volunteer_hours"]["current"] == "12.000"
    assert result["any_certificate"]["evidence_record_ids"] == [credential["id"]]
    assert result["thesis"]["evidence_record_ids"] == [achievement["id"]]
    conditions[3]["certificates"][0]["possession"] = "unknown"
    calculations[3]["condition"] = conditions[3]
    assert calculate(c, h, curriculum, calculations)["status"] == "needs_review"


@integration
def test_personal_history_is_frozen_replayable_and_retry_cannot_resurrect_deleted_result(
    auth_client, auth_db
):
    c = auth_client
    h = authorization(register(c))
    course, curriculum, link, _, _ = samples(c, h)
    rule = saved_rule(c, h, curriculum)
    inputs = [criterion(rule, kind="minimum_credits", minimum="4")]
    key = str(uuid4())
    first = calculate(c, h, curriculum, inputs, client_id=key)
    assert calculate(c, h, curriculum, inputs, client_id=key)["id"] == first["id"]
    response = c.patch(
        "/api/v1/me/course-records/" + course["id"],
        headers=h,
        json={"expected_version": 1, "credits": "10"},
    )
    assert response.status_code == 200
    assert calculate(c, h, curriculum, inputs, client_id=key)["results"][0]["current"] == "3.500"
    second = calculate(c, h, curriculum, inputs, client_id=str(uuid4()))
    assert second["status"] == "satisfied" and second["results"][0]["current"] == "10.000"
    page = c.get("/api/v1/me/personal-evaluations", headers=h, params={"limit": 1}).json()
    assert page["items"][0]["id"] == second["id"]
    assert "results" not in page["items"][0] and "source_versions" not in page["items"][0]
    older = c.get(
        "/api/v1/me/personal-evaluations", headers=h, params={"cursor": page["next_cursor"]}
    ).json()
    assert older["items"][0]["id"] == first["id"]
    with auth_db() as db:
        row = db.scalar(select(PersonalEvaluation).where(PersonalEvaluation.id == first["id"]))
        assert replay(row).model_dump(mode="json") == row.result_json
    for path, record, version in [
        ("personal-graduation-rules", rule, 1),
        ("personal-curriculum-courses", link, 1),
        ("course-records", course, 2),
        ("personal-curricula", curriculum, 1),
    ]:
        assert (
            c.delete(
                "/api/v1/me/" + path + "/" + record["id"] + "?expected_version=" + str(version),
                headers=h,
            ).status_code
            == 204
        )
    saved = c.get("/api/v1/me/personal-evaluations/" + first["id"], headers=h)
    assert saved.status_code == 200 and saved.json()["results"][0]["current"] == "3.500"
    assert (
        c.patch("/api/v1/me/personal-evaluations/" + first["id"], headers=h, json={}).status_code
        == 405
    )
    assert (
        c.delete(
            "/api/v1/me/personal-evaluations/" + first["id"] + "?expected_version=1", headers=h
        ).status_code
        == 204
    )
    calculate(c, h, curriculum, inputs, client_id=key, expected=409)


@integration
def test_other_accounts_and_administrators_cannot_read_or_use_private_inputs(auth_client, auth_db):
    from test_academic import operator

    c = auth_client
    first = authorization(register(c))
    course, curriculum, _, _, _ = samples(c, first)
    rule = saved_rule(c, first, curriculum)
    created = calculate(
        c, first, curriculum, [criterion(rule, kind="minimum_credits", minimum="3")]
    )
    for headers in (
        authorization(register(c, "other-evaluation@example.test")),
        operator(c, auth_db),
    ):
        assert c.get("/api/v1/me/personal-evaluations", headers=headers).json()["items"] == []
        assert (
            c.get("/api/v1/me/personal-evaluations/" + created["id"], headers=headers).status_code
            == 404
        )
        calculate(c, headers, curriculum, [], expected=404)
        assert (
            c.delete(
                "/api/v1/me/personal-evaluations/" + created["id"] + "?expected_version=1",
                headers=headers,
            ).status_code
            == 404
        )
    assert c.get("/api/v1/me/personal-evaluations").status_code == 401


@integration
def test_duplicate_plan_links_do_not_double_count_or_satisfy_two_course_requirements(auth_client):
    c = auth_client
    h = authorization(register(c))
    course, curriculum, link, _, _ = samples(c, h)
    other_link = post(
        c,
        h,
        "personal-curriculum-courses",
        {
            "title": "합성 중복 연결",
            "curriculum_id": curriculum["id"],
            "course_record_id": course["id"],
            "category": "전공",
            "credits": "3.5",
            "required": True,
        },
    )
    credit = saved_rule(c, h, curriculum, "합성 합계")
    required = saved_rule(c, h, curriculum, "합성 두 과목")
    response = calculate(
        c,
        h,
        curriculum,
        [
            criterion(credit, kind="minimum_credits", minimum="6"),
            criterion(
                required,
                kind="required_courses",
                courses=[
                    {"curriculum_course_id": link["id"]},
                    {"curriculum_course_id": other_link["id"]},
                ],
            ),
        ],
    )
    results = {item["rule_id"]: item for item in response["results"]}
    assert results[credit["id"]]["current"] == "3.500"
    assert results[required["id"]]["reason"] == "ambiguous_personal_course_mapping"


@integration
def test_future_observed_hours_and_unknown_credential_labels_are_not_confirmed(auth_client):
    c = auth_client
    h = authorization(register(c))
    _, curriculum, _, _, _ = samples(c, h)
    activity = post(
        c,
        h,
        "activity-records",
        {
            "title": "합성 미래 관찰",
            "approved_hours": "100",
            "approval": "approved",
            "observed_on": "2027-01-01",
        },
    )
    credential = post(
        c, h, "credential-records", {"title": "합성 보유 설명", "status_label": "취득·검증 완료"}
    )
    volunteer = saved_rule(c, h, curriculum, "합성 봉사 기준")
    certificate = saved_rule(c, h, curriculum, "합성 자격 기준")
    response = calculate(
        c,
        h,
        curriculum,
        [
            criterion(
                volunteer,
                kind="minimum_volunteer_hours",
                minimum="10",
                activity_ids=[activity["id"]],
            ),
            criterion(
                certificate,
                kind="any_certificate",
                certificates=[{"credential_id": credential["id"]}],
            ),
        ],
    )
    assert response["status"] == "needs_review"
    assert all(item["status"] == "needs_review" for item in response["results"])


@integration
def test_curriculum_rule_and_source_boundaries_are_checked_before_saving(auth_client, auth_db):
    c = auth_client
    h = authorization(register(c))
    course, curriculum, link, _, _ = samples(c, h)
    rule = saved_rule(c, h, curriculum)
    conditions = [criterion(rule, kind="minimum_credits", minimum="3")]
    calculate(c, h, curriculum, conditions, expected_curriculum_version=99, expected=409)
    stale = [{**conditions[0], "expected_version": 99}]
    calculate(c, h, curriculum, stale, expected=409)
    other = authorization(register(c, "foreign-source@example.test"))
    foreign = post(
        c,
        other,
        "course-records",
        {"title": "합성 타인 과목", "credits": "3", "term": "합성 학기", "category": "전공"},
    )
    for identifier in [foreign["id"], str(uuid4())]:
        calculate(
            c,
            h,
            curriculum,
            [criterion(rule, kind="minimum_credits", minimum="3", course_record_ids=[identifier])],
            expected=404,
        )
        calculate(
            c,
            h,
            curriculum,
            conditions,
            expected_source_versions=[
                {"kind": "course-records", "record_id": identifier, "version": 1}
            ],
            expected=404,
        )
    unlinked = post(
        c,
        h,
        "course-records",
        {"title": "합성 다른 과정 과목", "credits": "3", "term": "합성 학기", "category": "전공"},
    )
    calculate(
        c,
        h,
        curriculum,
        [criterion(rule, kind="minimum_credits", minimum="3", course_record_ids=[unlinked["id"]])],
        expected=404,
    )
    with auth_db() as db:
        assert db.scalar(select(PersonalEvaluation)) is None
    accepted = calculate(
        c,
        h,
        curriculum,
        conditions,
        expected_source_versions=[
            {"kind": "course-records", "record_id": course["id"], "version": 1}
        ],
    )
    assert {v["record_id"] for v in accepted["source_versions"]} == {
        course["id"],
        curriculum["id"],
        link["id"],
        rule["id"],
    }


@integration
def test_rule_periods_and_certificate_expiration_include_the_boundary_day(auth_client):
    c = auth_client
    h = authorization(register(c))
    _, curriculum, _, _, _ = samples(c, h)
    active = saved_rule(c, h, curriculum, effective_from="2026-10-19", effective_to="2026-10-19")
    future = saved_rule(c, h, curriculum, "합성 미래 기준", effective_from="2026-10-20")
    credential = post(
        c,
        h,
        "credential-records",
        {"title": "합성 당일 만료 자격", "earned_on": "2026-01-01", "expires_on": "2026-10-19"},
    )
    conditions = [
        criterion(
            active,
            kind="any_certificate",
            certificates=[
                {"credential_id": credential["id"], "possession": "held", "validity_known": True}
            ],
        )
    ]
    current = calculate(c, h, curriculum, conditions)
    assert current["status"] == "satisfied" and len(current["results"]) == 1
    calculate(
        c, h, curriculum, [criterion(future, kind="minimum_credits", minimum="0")], expected=422
    )
    # Once the one-day rule ends it is excluded, rather than falsely retained as satisfied.
    later = calculate(c, h, curriculum, as_of="2026-10-20")
    assert len(later["results"]) == 1 and later["results"][0]["rule_id"] == future["id"]
    assert later["status"] == "needs_review"
    # A new active rule cannot make yesterday's expired certificate valid.
    expired = calculate(
        c, h, curriculum, [criterion(future, **conditions[0]["condition"])], as_of="2026-10-20"
    )
    assert expired["status"] == "not_satisfied"
