"""Atomic append imports use synthetic account-local records only."""

from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from unittest.mock import patch
from uuid import UUID, uuid4

import pytest
from sqlalchemy import func, select
from test_academic import operator
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register

from app.core.auth_errors import conflict
from app.models.personal import PersonalCreationReceipt, PlanningProfile
from app.models.personal_imports import PersonalImportReceipt
from app.services import personal

pytestmark = pytest.mark.integration
ROOT = "/api/v1/me/personal-imports"


def graph(owner_id, *, profile=True):
    identifiers = {
        name: str(uuid4())
        for name in [
            "event",
            "course",
            "activity",
            "experience",
            "credential",
            "achievement",
            "second_achievement",
            "curriculum",
            "curriculum_course",
            "rule",
            "composition",
            "document",
        ]
    }

    def record(kind, **fields):
        return {"client_id": identifiers[kind], "title": "합성 " + kind, **fields}

    result = {
        "import_id": str(uuid4()),
        "source_owner_id": owner_id,
        "consent_confirmed": True,
        "profile": {
            "school": "합성 개인 학교",
            "department": "합성 개인 학과",
            "admission_year": 2026,
        }
        if profile
        else None,
        "events": [
            record(
                "event",
                starts_at="2026-10-19T10:00:00+09:00",
                ends_at="2026-10-19T11:00:00+09:00",
                time_zone="Asia/Seoul",
                category="personal",
            )
        ],
        "course_records": [
            record("course", term="2026-1", category="전공", credits="3.5", grade="개인 관찰값")
        ],
        "activity_records": [record("activity", organization="합성 기관", reported_hours="10")],
        "experience_records": [record("experience", experience_type="개인 경험")],
        "credential_records": [
            record("credential", provider="합성 기관", status_label="개인 입력")
        ],
        "achievement_records": [
            record(key, achievement_type="개인 성과", role="참여", result="합성 결과")
            for key in ["achievement", "second_achievement"]
        ],
        "personal_curricula": [
            record(
                "curriculum",
                school="개인 학교",
                department="개인 학과",
                admission_year=2026,
                curriculum_year=2026,
            )
        ],
        "personal_curriculum_courses": [
            record(
                "curriculum_course",
                curriculum_client_id=identifiers["curriculum"],
                course_record_client_id=identifiers["course"],
                category="전공",
                credits="3.5",
                required=True,
            )
        ],
        "personal_graduation_rules": [
            record(
                "rule",
                curriculum_client_id=identifiers["curriculum"],
                curriculum_course_client_id=identifiers["curriculum_course"],
                rule_type="개인 설명",
                scope="curriculum",
                condition="실행하지 않는 메모",
                related_record={"kind": "activity", "client_id": identifiers["activity"]},
            )
        ],
        "portfolio_compositions": [
            record(
                "composition",
                sources=[
                    {"kind": "achievement", "client_id": identifiers[key]}
                    for key in ["second_achievement", "achievement"]
                ],
                audience="private",
                reviewed=True,
            )
        ],
        "application_documents": [
            record(
                "document",
                target="합성 지원처",
                role="합성 직무",
                document_type="개인 초안",
                body="합성 본문",
                sources=[
                    {"kind": kind, "client_id": identifiers[key]}
                    for kind, key in [("experience", "experience"), ("achievement", "achievement")]
                ],
            )
        ],
    }
    return result, identifiers


def account(client, email="import-student@example.test"):
    result = register(client, email)
    return authorization(result), result.json()["user"]["id"]


def submit(client, headers, body, expected=201):
    result = client.post(ROOT, headers=headers, json=body)
    assert result.status_code == expected, result.text
    assert result.headers["Cache-Control"] == "no-store"
    return result.json()


def empty_records(db):
    with db() as session:
        for model, _ in personal.RESOURCES.values():
            assert session.scalar(select(func.count()).select_from(model)) == 0
        for model in [PlanningProfile, PersonalCreationReceipt, PersonalImportReceipt]:
            assert session.scalar(select(func.count()).select_from(model)) == 0


def test_complete_graph_initializes_profile_and_preserves_relations_order_and_times(
    auth_client, auth_db
):
    c = auth_client
    h, owner = account(c)
    body, identifiers = graph(owner)
    result = submit(c, h, body)
    assert result["owner_id"] == owner and result["official"] is False
    assert result["record_count"] == 12 and result["profile_version_at_import"] == 1
    assert result["replayed"] is False
    mappings = {(m["resource"], m["client_id"]): m["record_id"] for m in result["mappings"]}

    def saved(resource, key):
        identifier = mappings[resource, identifiers[key]]
        assert identifier != identifiers[key]
        response = c.get("/api/v1/me/" + resource + "/" + identifier, headers=h)
        assert response.status_code == 200, response.text
        assert response.json()["owner_id"] == owner and response.json()["official"] is False
        return response.json()

    course = saved("course-records", "course")
    curriculum = saved("personal-curricula", "curriculum")
    link = saved("personal-curriculum-courses", "curriculum_course")
    rule = saved("personal-graduation-rules", "rule")
    assert link["curriculum_id"] == rule["curriculum_id"] == curriculum["id"]
    assert link["course_record_id"] == course["id"]
    assert rule["curriculum_course_id"] == link["id"]
    assert rule["related_record"] == {
        "kind": "activity",
        "record_id": saved("activity-records", "activity")["id"],
    }
    composition = saved("portfolio-compositions", "composition")
    assert [ref["record_id"] for ref in composition["sources"]] == [
        mappings["achievement-records", identifiers[key]]
        for key in ["second_achievement", "achievement"]
    ]
    document = saved("application-documents", "document")
    assert [ref["kind"] for ref in document["sources"]] == ["experience", "achievement"]
    event = saved("events", "event")
    assert event["starts_at"] == "2026-10-19T01:00:00Z" and event["time_zone"] == "Asia/Seoul"
    reordered = deepcopy(body)
    reordered["achievement_records"].reverse()
    assert submit(c, h, reordered)["mappings"] == result["mappings"]
    reordered["portfolio_compositions"][0]["sources"].reverse()
    submit(c, h, reordered, 409)
    with auth_db() as db:
        receipt = db.get(PersonalImportReceipt, (UUID(owner), UUID(result["import_id"])))
        assert len(receipt.digest) == 64
        assert all(
            set(row) == {"resource", "client_id", "record_id", "version_at_import", "outcome"}
            for row in receipt.mappings_json
        )
        assert "합성" not in str(receipt.mappings_json)


def test_missing_graph_aliases_consent_and_naive_times_rejected_before_writes(auth_client, auth_db):
    c = auth_client
    h, owner = account(c)
    original, _ = graph(owner)
    invalid = []
    for consent in [False, 1, "true"]:
        invalid.append({**deepcopy(original), "consent_confirmed": consent})
    body = deepcopy(original)
    body["activity_records"] = []
    invalid.append(body)
    body = deepcopy(original)
    body["events"][0]["starts_at"] = "2026-10-19T10:00:00"
    invalid.append(body)
    body = deepcopy(original)
    body["personal_curriculum_courses"][0]["curriculum_id"] = body["personal_curriculum_courses"][
        0
    ].pop("curriculum_client_id")
    invalid.append(body)
    body = deepcopy(original)
    body["course_records"].append(deepcopy(body["course_records"][0]))
    invalid.append(body)
    body = deepcopy(original)
    body["portfolio_compositions"][0]["sources"][0]["record_id"] = body["portfolio_compositions"][
        0
    ]["sources"][0].pop("client_id")
    invalid.append(body)
    invalid.append({**deepcopy(original), "owner_id": owner})
    for body in invalid:
        submit(c, h, body, 422)
        empty_records(auth_db)


def test_failure_after_last_record_rolls_back_profile_records_sources_and_receipts(
    auth_client, auth_db
):
    c = auth_client
    h, owner = account(c)
    body, _ = graph(owner)
    save_record = personal.save_record

    def failure(db, owner_id, resource, payload, record_id=None):
        result = save_record(db, owner_id, resource, payload, record_id)
        if resource == "application-documents":
            raise conflict()
        return result

    with patch.object(personal, "save_record", side_effect=failure):
        submit(c, h, body, 409)
    empty_records(auth_db)
    result = submit(c, h, body)
    assert result["record_count"] == 12 and not result["replayed"]


def test_replay_is_historical_and_never_overwrites_or_resurrects_deleted_records(
    auth_client, auth_db
):
    c = auth_client
    h, owner = account(c)
    body = {
        "import_id": str(uuid4()),
        "source_owner_id": owner,
        "consent_confirmed": True,
        "course_records": [
            {
                "client_id": str(uuid4()),
                "title": "합성 원문",
                "term": "2026-1",
                "category": "전공",
                "credits": "3",
            }
        ],
    }
    first = submit(c, h, body)
    record_id = first["mappings"][0]["record_id"]
    path = "/api/v1/me/course-records/" + record_id
    changed = c.patch(
        path, headers=h, json={"expected_version": 1, "title": "서버에서 편집한 개인 자료"}
    )
    assert changed.status_code == 200
    replayed = submit(c, h, body)
    assert replayed["replayed"] and replayed["mappings"] == first["mappings"]
    assert c.get(path, headers=h).json()["title"] == "서버에서 편집한 개인 자료"
    assert c.delete(path, headers=h, params={"expected_version": 2}).status_code == 204
    assert submit(c, h, body)["mappings"] == first["mappings"]
    assert c.get(path, headers=h).status_code == 404
    assert c.get(ROOT + "/" + body["import_id"], headers=h).json()["mappings"] == first["mappings"]
    submit(c, h, {**body, "import_id": str(uuid4())}, 409)
    changed = deepcopy(body)
    changed["course_records"][0]["title"] = "원문 변경"
    submit(c, h, changed, 409)
    with auth_db() as db:
        assert db.scalar(select(func.count()).select_from(PersonalImportReceipt)) == 1


def test_existing_profile_and_creation_conflicts_do_not_partially_append(auth_client, auth_db):
    c = auth_client
    h, owner = account(c)
    body, _ = graph(owner)
    c.patch(
        "/api/v1/me/planning-profile",
        headers=h,
        json={"expected_version": 0, "school": "기존 개인 학교"},
    )
    submit(c, h, body, 409)
    assert c.get("/api/v1/me/planning-profile", headers=h).json()["school"] == "기존 개인 학교"
    assert c.get("/api/v1/me/events", headers=h).json()["items"] == []
    body["profile"] = None
    result = submit(c, h, body)
    assert result["profile_version_at_import"] is None
    # A second batch can reuse the exact creation receipts without modifying rows.
    reused = submit(c, h, {**body, "import_id": str(uuid4())})
    assert all(
        row["outcome"] == "reused" and row["version_at_import"] == 1 for row in reused["mappings"]
    )
    assert [row["record_id"] for row in result["mappings"]] == [
        row["record_id"] for row in reused["mappings"]
    ]
    conflicting = deepcopy(body)
    conflicting["import_id"] = str(uuid4())
    conflicting["events"][0]["client_id"] = str(uuid4())
    conflicting["course_records"][0]["title"] = "이미 생성된 원문의 변경"
    submit(c, h, conflicting, 409)
    assert len(c.get("/api/v1/me/events", headers=h).json()["items"]) == 1


def test_foreign_accounts_and_super_administrators_cannot_claim_import_receipts(
    auth_client, auth_db
):
    c = auth_client
    h, owner = account(c)
    body, _ = graph(owner, profile=False)
    result = submit(c, h, body)
    other, other_owner = account(c, "other-import@example.test")
    assert c.get(ROOT + "/" + result["import_id"], headers=other).status_code == 404
    submit(c, other, body, 403)
    root = operator(c, auth_db)
    assert c.get(ROOT + "/" + result["import_id"], headers=root).status_code == 404
    submit(c, root, body, 403)
    other_result = submit(c, other, {**body, "source_owner_id": other_owner})
    assert other_result["owner_id"] == other_owner
    assert not {row["record_id"] for row in other_result["mappings"]} & {
        row["record_id"] for row in result["mappings"]
    }


def test_concurrent_identical_requests_have_one_commit_and_stable_mapping(auth_client, auth_db):
    c = auth_client
    h, owner = account(c)
    body, _ = graph(owner)
    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(lambda _: submit(c, h, body), range(2)))
    assert {result["replayed"] for result in results} == {False, True}
    assert results[0]["mappings"] == results[1]["mappings"]
    with auth_db() as db:
        assert db.scalar(select(func.count()).select_from(PersonalImportReceipt)) == 1
        assert db.scalar(select(func.count()).select_from(PersonalCreationReceipt)) == 12


def test_profile_only_import_and_oversized_batches_have_explicit_bounds(auth_client, auth_db):
    c = auth_client
    h, owner = account(c)
    base = {"import_id": str(uuid4()), "source_owner_id": owner, "consent_confirmed": True}
    submit(c, h, base, 422)
    submit(
        c,
        h,
        {
            **base,
            "application_documents": [
                {
                    "client_id": str(uuid4()),
                    "title": "합성 대형 초안",
                    "target": "합성",
                    "role": "합성",
                    "document_type": "합성",
                    "body": "x" * 32000,
                }
                for _ in range(70)
            ],
        },
        422,
    )
    submit(
        c,
        h,
        {
            **base,
            "course_records": [
                {
                    "client_id": str(uuid4()),
                    "title": "합성",
                    "term": "2026-1",
                    "category": "전공",
                    "credits": "3",
                }
                for _ in range(101)
            ],
        },
        422,
    )
    empty_records(auth_db)
    result = submit(c, h, {**base, "profile": {}})
    assert result["record_count"] == 0 and result["mappings"] == []
    assert result["profile_version_at_import"] == 1
