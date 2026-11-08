from uuid import uuid4

import pytest
from pydantic import ValidationError
from test_academic import operator, post, school
from test_admin_academic_curricula import published_classification
from test_admin_academic_workspace import ROOT, command
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db

pytestmark = pytest.mark.integration


def test_credit_aggregate_cycles_are_rejected():
    from app.schemas.academic_requirements import CreditContent

    first, second = str(uuid4()), str(uuid4())
    with pytest.raises(ValidationError, match="acyclic"):
        CreditContent.model_validate(
            {
                "kind": "credit_table",
                "headers": [
                    {
                        "id": first,
                        "label": "소계",
                        "position": 0,
                        "role": "subtotal",
                        "aggregate_members": [second],
                    },
                    {
                        "id": second,
                        "label": "총계",
                        "position": 1,
                        "role": "total",
                        "aggregate_members": [first],
                    },
                ],
            }
        )


def test_scopes_intersect_admission_year_department_and_tracks():
    from app.schemas.academic_requirements import ChecklistContent
    from app.schemas.academic_workspace import AcademicScope
    from app.services.academic_requirements import publication_issues, scope_intersection

    department, track = uuid4(), uuid4()
    parent = AcademicScope(
        clauses=[
            {
                "department_id": department,
                "admission_from": 2026,
                "admission_to": 2029,
                "track_mode": "selected",
                "track_ids": [track],
            }
        ]
    )
    child = AcademicScope(clauses=[{"admission_from": 2025, "admission_to": 2027}])
    effective = scope_intersection(parent, child).clauses[0]
    assert (effective.admission_from, effective.admission_to) == (2026, 2027)
    assert effective.department_id == department and effective.track_ids == [track]
    outside = ChecklistContent(
        kind="checklist",
        lines=[
            {
                "text": "합성 요건",
                "scope": {"clauses": [{"department_id": uuid4()}]},
            }
        ],
    )
    assert publication_issues(outside, parent)


def create(c, h, inst, kind="checklist", **fields):
    response = c.post(
        ROOT + "/requirement-revisions",
        headers=h,
        json=command(institution_id=inst["id"], name="합성 졸업요건", kind=kind, **fields),
    )
    assert response.status_code == 201, response.text
    return response.json()


def save(c, h, revision, content, **fields):
    payload = command(
        expected_version=revision["version"],
        name=revision["name"],
        scope={"clauses": [{}]},
        content=content,
        classification_revision_id=revision["classification_revision_id"],
        curriculum_revision_id=revision["curriculum_revision_id"],
    )
    payload.update(fields)
    response = c.put(ROOT + "/requirement-revisions/" + revision["id"], headers=h, json=payload)
    assert response.status_code == 200, response.text
    return response.json(), payload


def publish(c, h, revision):
    url = ROOT + "/requirement-revisions/" + revision["id"]
    preview = c.post(
        url + "/preview-publication", headers=h, json={"expected_version": revision["version"]}
    )
    assert preview.status_code == 200, preview.text
    assert preview.json()["issues"] == []
    response = c.post(
        url + "/publish",
        headers=h,
        json=command(
            expected_version=revision["version"],
            expected_digest=preview.json()["digest"],
            review_note="합성 기준 검토",
        ),
    )
    assert response.status_code == 200, response.text
    return response.json()


def test_checklist_ids_order_revision_copy_and_withdrawal(auth_client, auth_db):
    c = auth_client
    h = operator(c, auth_db)
    inst = school(c, h)
    revision = create(c, h, inst)
    first, second = str(uuid4()), str(uuid4())
    saved, body = save(
        c,
        h,
        revision,
        {
            "kind": "checklist",
            "lines": [{"id": first, "text": "동일한 문장"}, {"id": second, "text": "동일한 문장"}],
        },
    )
    url = ROOT + "/requirement-revisions/" + revision["id"]
    assert c.put(url, headers=h, json=body).json() == saved
    reordered, _ = save(
        c,
        h,
        saved,
        {
            "kind": "checklist",
            "lines": [{"id": second, "text": "수정 문장"}, {"id": first, "text": "동일한 문장"}],
        },
    )
    assert [line["id"] for line in reordered["content"]["lines"]] == [second, first]
    published = publish(c, h, reordered)
    copied = c.post(url + "/drafts", headers=h, json=command(expected_version=published["version"]))
    assert copied.status_code == 201, copied.text
    assert copied.json()["content"] == published["content"]
    assert copied.json()["id"] != published["id"]
    assert copied.json()["lineage_id"] == published["lineage_id"]
    assert c.get(url, headers=h).json() == published
    withdrew = c.post(
        url + "/withdraw",
        headers=h,
        json=command(expected_version=published["version"], reason="합성 철회"),
    )
    assert withdrew.status_code == 200, withdrew.text
    assert withdrew.json()["status"] == "withdrawn"
    assert withdrew.json()["content"] == published["content"]


def test_certification_pick_n_counts_child_groups_and_preserves_invalid_draft(auth_client, auth_db):
    c = auth_client
    h = operator(c, auth_db)
    inst = school(c, h)
    revision = create(c, h, inst, kind="certification")
    groups = [
        {
            "label": "영역",
            "choice": "pickN",
            "pick_count": 2,
            "groups": [
                {"label": "정보화", "items": [{"label": "자격 취득", "kind": "certificate"}]},
                {"label": "봉사", "items": [{"label": "봉사시간 충족", "kind": "volunteer"}]},
            ],
        }
    ]
    saved, _ = save(
        c,
        h,
        revision,
        {
            "kind": "certification",
            "groups": groups,
            "tables": [
                {
                    "title": "시험별 점수 기준",
                    "columns": ["시험", "기준"],
                    "rows": [["시험 A", "기준 A"]],
                }
            ],
        },
    )
    url = ROOT + "/requirement-revisions/" + revision["id"]
    preview = c.post(
        url + "/preview-publication", headers=h, json={"expected_version": saved["version"]}
    )
    assert preview.status_code == 200 and preview.json()["issues"] == []
    invalid_content = saved["content"]
    invalid_content["groups"][0]["pick_count"] = 3
    invalid, _ = save(c, h, saved, invalid_content)
    assert invalid["content"]["groups"][0]["pick_count"] == 3
    preview = c.post(
        url + "/preview-publication", headers=h, json={"expected_version": invalid["version"]}
    )
    assert preview.status_code == 200 and preview.json()["issues"]


def test_multilevel_credit_table_retains_exact_values_and_shared_classification(
    auth_client, auth_db
):
    c = auth_client
    h = operator(c, auth_db)
    inst = school(c, h)
    classification, leaf = published_classification(c, h, inst)
    revision = create(
        c, h, inst, kind="credit_table", classification_revision_id=classification["id"]
    )
    outer, inner, value, total, row = [str(uuid4()) for _ in range(5)]
    content = {
        "kind": "credit_table",
        "headers": [
            {"id": outer, "label": "교양", "position": 0, "role": "group"},
            {"id": inner, "parent_id": outer, "label": "필수", "position": 0, "role": "group"},
            {
                "id": value,
                "parent_id": inner,
                "label": "기초",
                "position": 0,
                "classification_node_id": leaf["id"],
                "requirement": "required",
            },
            {"id": total, "label": "최소 졸업 학점", "position": 1, "role": "total"},
        ],
        "rows": [{"id": row, "label": "단일전공", "note": "원문 비고"}],
        "cells": [
            {"row_id": row, "header_id": value, "state": "number", "value": "0.125"},
            {"row_id": row, "header_id": total, "state": "not_applicable"},
        ],
    }
    saved, _ = save(c, h, revision, content)
    assert saved["content"]["cells"][0]["value"] == "0.125"
    assert saved["content"]["cells"][1]["value"] is None
    published = publish(c, h, saved)
    assert published["content"] == saved["content"]
    invalid = {
        **content,
        "cells": [{"row_id": row, "header_id": outer, "state": "number", "value": "1"}],
    }
    draft = create(c, h, inst, kind="credit_table", classification_revision_id=classification["id"])
    response = c.put(
        ROOT + "/requirement-revisions/" + draft["id"],
        headers=h,
        json=command(
            expected_version=1,
            name=draft["name"],
            scope={"clauses": [{}]},
            content=invalid,
            classification_revision_id=classification["id"],
        ),
    )
    assert response.status_code == 422


def test_legacy_rule_description_import_preserves_original_and_does_not_require_url(
    auth_client, auth_db
):
    c = auth_client
    h = operator(c, auth_db)
    inst = school(c, h)
    legacy = post(
        c,
        h,
        "rules",
        {
            "institution_id": inst["id"],
            "name": "기존 요건",
            "rule_type": "custom",
            "definition": "기존 규정 문장",
            "source_url": "https://example.test/original",
        },
    )
    revision = create(c, h, inst, legacy_rule_id=legacy["id"])
    assert revision["content"]["lines"][0]["text"] == legacy["definition"]
    assert "source_url" not in revision
    assert revision["legacy_rule_version"] == legacy["version"]
    assert c.get("/api/v1/admin/rules/" + legacy["id"], headers=h).json() == legacy
