from uuid import uuid4

import pytest
from test_academic import department, operator, school
from test_admin_academic_curricula import curriculum, published_classification
from test_admin_academic_requirements import create, publish, save
from test_admin_academic_workspace import ROOT, command
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register

ME = "/api/v1/me/"
pytestmark = pytest.mark.integration


@pytest.fixture
def academic_student(auth_client, auth_db):
    c = auth_client
    admin = operator(c, auth_db)
    inst = school(c, admin)
    dep = department(c, admin, inst)
    classification, leaf = published_classification(c, admin, inst)
    track = c.post(
        ROOT + "/study-tracks",
        headers=admin,
        json=command(institution_id=inst["id"], name="주전공 경로"),
    ).json()
    cur = curriculum(c, admin, inst, classification)
    url = ROOT + "/curriculum-revisions/" + cur["id"]
    added = c.post(
        url + "/course-entries",
        headers=admin,
        json=command(
            expected_version=cur["version"],
            new_course={"name": "합성 설계", "code": "SHARED", "credits": "3.5"},
            classification_node_id=leaf["id"],
            requirement="required",
            recognized_credits="3.125",
        ),
    )
    assert added.status_code == 200, added.text
    cur = added.json()
    entry = cur["courses"][0]
    saved = c.put(
        url,
        headers=admin,
        json=command(
            expected_version=cur["version"],
            name=cur["name"],
            curriculum_year=2026,
            classification_revision_id=classification["id"],
            scope={"clauses": [{}]},
            courses=[
                {
                    "id": entry["id"],
                    "course_id": entry["course_id"],
                    "expected_course_version": entry["course_version"],
                    "classification_node_id": leaf["id"],
                    "requirement": "required",
                    "recognized_credits": "3.125",
                    "position": 0,
                }
            ],
        ),
    )
    assert saved.status_code == 200, saved.text
    cur = saved.json()
    preview = c.post(
        url + "/preview-publication", headers=admin, json={"expected_version": cur["version"]}
    ).json()
    published = c.post(
        url + "/publish",
        headers=admin,
        json=command(
            expected_version=cur["version"],
            expected_digest=preview["digest"],
            review_note="합성 검토",
        ),
    )
    assert published.status_code == 200, published.text
    cur = published.json()
    account = register(c)
    student = authorization(account)
    response = c.patch(
        ME + "planning-profile",
        headers=student,
        json={
            "expected_version": 0,
            "institution_id": inst["id"],
            "department_id": dep["id"],
            "school": inst["name"],
            "department": dep["name"],
            "admission_year": 2026,
            "track": "보존할 자유 입력",
        },
    )
    assert response.status_code == 200, response.text
    payload = command(
        expected_version=0,
        contexts=[
            {
                "department_id": dep["id"],
                "track_id": track["id"],
                "curriculum_revision_id": cur["id"],
                "admission_year": 2026,
                "primary": True,
            }
        ],
    )
    response = c.put(ME + "academic-contexts", headers=student, json=payload)
    assert response.status_code == 200, response.text
    assert c.put(ME + "academic-contexts", headers=student, json=payload).json() == response.json()
    return {
        "c": c,
        "admin": admin,
        "student": student,
        "inst": inst,
        "dep": dep,
        "track": track,
        "classification": classification,
        "leaf": leaf,
        "cur": cur,
        "context": response.json()["contexts"][0],
    }


def activation(env):
    c, h = env["c"], env["student"]
    preview = c.get(ME + "academic-requirements/preview", headers=h)
    assert preview.status_code == 200, preview.text
    data = preview.json()
    assert data["issues"] == [], data
    payload = command(expected_version=data["workspace_version"], expected_digest=data["digest"])
    response = c.post(ME + "academic-requirements/activate", headers=h, json=payload)
    assert response.status_code == 200, response.text
    assert (
        c.post(ME + "academic-requirements/activate", headers=h, json=payload).json()
        == response.json()
    )
    return response.json()


def requirement(env, content):
    draft = create(
        env["c"],
        env["admin"],
        env["inst"],
        kind=content["kind"],
        classification_revision_id=env["classification"]["id"],
    )
    saved, _ = save(env["c"], env["admin"], draft, content)
    return publish(env["c"], env["admin"], saved)


def respond(env, active, doc, item, value, records=None, expected=0):
    return env["c"].put(
        ME + f"academic-requirements/{doc['id']}/responses/{item}",
        headers=env["student"],
        json=command(
            expected_version=expected,
            activation_id=active["activation_id"],
            value=value,
            records=records or [],
        ),
    )


def test_checklist_owner_isolation_reset_replay_and_profile_preservation(academic_student):
    e = academic_student
    first, second = str(uuid4()), str(uuid4())
    doc = requirement(
        e,
        {
            "kind": "checklist",
            "lines": [{"id": first, "text": "같은 문장"}, {"id": second, "text": "같은 문장"}],
        },
    )
    active = activation(e)
    saved = respond(e, active, doc, first, True)
    assert saved.status_code == 200, saved.text
    assert saved.json()["documents"][0]["responses"][0]["value"] is True
    assert respond(e, active, doc, first, False).status_code == 409
    reset = respond(e, active, doc, first, None, expected=1)
    assert (
        reset.status_code == 200 and reset.json()["documents"][0]["responses"][0]["value"] is None
    )
    other = authorization(register(e["c"], "other@example.test"))
    assert e["c"].get(ME + "academic-requirements", headers=other).json()["documents"] == []
    denied = e["c"].put(
        ME + f"academic-requirements/{doc['id']}/responses/{second}",
        headers=other,
        json=command(expected_version=0, activation_id=active["activation_id"], value=True),
    )
    assert denied.status_code in (404, 409, 422)
    assert (
        e["c"].get(ME + "planning-profile", headers=e["student"]).json()["track"]
        == "보존할 자유 입력"
    )


def test_revision_requires_activation_and_carries_only_unchanged_items(academic_student):
    e = academic_student
    a, b = str(uuid4()), str(uuid4())
    doc = requirement(
        e, {"kind": "checklist", "lines": [{"id": a, "text": "동일"}, {"id": b, "text": "이전"}]}
    )
    active = activation(e)
    assert respond(e, active, doc, a, True).status_code == 200
    assert respond(e, active, doc, b, True).status_code == 200
    url = ROOT + "/requirement-revisions/" + doc["id"]
    copied = (
        e["c"]
        .post(url + "/drafts", headers=e["admin"], json=command(expected_version=doc["version"]))
        .json()
    )
    saved, _ = save(
        e["c"],
        e["admin"],
        copied,
        {"kind": "checklist", "lines": [{"id": a, "text": "동일"}, {"id": b, "text": "변경"}]},
    )
    revised = publish(e["c"], e["admin"], saved)
    unchanged = e["c"].get(ME + "academic-requirements", headers=e["student"]).json()
    assert unchanged["documents"][0]["id"] == doc["id"]
    switched = activation(e)
    assert switched["documents"][0]["id"] == revised["id"]
    responses = {r["item_id"]: r for r in switched["documents"][0]["responses"]}
    assert responses[a]["value"] is True and not responses[a]["stale"]
    history = e["c"].get(ME + "academic-requirements/history", headers=e["student"])
    assert history.status_code == 200 and len(history.json()["items"]) == 2
    past = e["c"].get(
        ME + "academic-requirements/history/" + active["activation_id"], headers=e["student"]
    )
    assert past.status_code == 200 and past.json()["documents"][0]["id"] == doc["id"]
    assert all(r["value"] is True for r in past.json()["documents"][0]["responses"])
    assert (
        responses[b]["value"] is None
        and responses[b]["previous_value"] is True
        and responses[b]["stale"]
    )
    withdrawn = e["c"].post(
        ROOT + f"/requirement-revisions/{revised['id']}/withdraw",
        headers=e["admin"],
        json=command(expected_version=revised["version"], reason="합성 철회"),
    )
    assert withdrawn.status_code == 200
    assert respond(e, switched, revised, a, False, expected=1).status_code == 422
    assert (
        "requirement_withdrawn"
        in e["c"].get(ME + "academic-requirements", headers=e["student"]).json()["issues"]
    )


def test_certification_links_are_private_and_mutation_or_deletion_requires_confirmation(
    academic_student,
):
    e = academic_student
    group, item = str(uuid4()), str(uuid4())
    doc = requirement(
        e,
        {
            "kind": "certification",
            "groups": [
                {
                    "id": group,
                    "label": "택1",
                    "choice": "pickOne",
                    "items": [{"id": item, "label": "자격 취득"}],
                }
            ],
        },
    )
    active = activation(e)
    record = (
        e["c"]
        .post(ME + "credential-records", headers=e["student"], json={"title": "내 자격"})
        .json()
    )
    refs = [
        {"kind": "credential", "record_id": record["id"], "expected_version": record["version"]}
    ]
    saved = respond(e, active, doc, item, True, refs)
    assert saved.status_code == 200, saved.text
    assert saved.json()["documents"][0]["group_results"][group] == "satisfied"
    other = authorization(register(e["c"], "other@example.test"))
    foreign = (
        e["c"].post(ME + "credential-records", headers=other, json={"title": "타인 자격"}).json()
    )
    assert (
        respond(
            e,
            active,
            doc,
            item,
            True,
            [{"kind": "credential", "record_id": foreign["id"], "expected_version": 1}],
            expected=1,
        ).status_code
        == 404
    )
    changed = e["c"].patch(
        ME + f"credential-records/{record['id']}",
        headers=e["student"],
        json={"expected_version": 1, "title": "변경 자격"},
    )
    assert changed.status_code == 200
    read = e["c"].get(ME + "academic-requirements", headers=e["student"]).json()["documents"][0]
    assert read["responses"][0]["stale"] and read["group_results"][group] == "needs_review"
    deleted = e["c"].delete(
        ME + f"credential-records/{record['id']}?expected_version=2", headers=e["student"]
    )
    assert deleted.status_code == 204, deleted.text
    read = e["c"].get(ME + "academic-requirements", headers=e["student"]).json()["documents"][0]
    assert not read["responses"][0]["records"][0]["available"]


def test_credit_progress_exact_caps_retakes_and_mapping(academic_student):
    e = academic_student
    outer, inner, col, total, empty, na, row = [str(uuid4()) for _ in range(7)]
    requirement(
        e,
        {
            "kind": "credit_table",
            "headers": [
                {"id": outer, "label": "교양", "role": "group", "position": 0},
                {"id": inner, "label": "필수", "role": "group", "parent_id": outer, "position": 0},
                {
                    "id": col,
                    "label": "기초",
                    "parent_id": inner,
                    "position": 0,
                    "classification_node_id": e["leaf"]["id"],
                },
                {
                    "id": total,
                    "label": "소계",
                    "role": "subtotal",
                    "aggregate_members": [col],
                    "position": 1,
                },
                {"id": empty, "label": "공란", "position": 2},
                {"id": na, "label": "해당 없음", "position": 3},
            ],
            "rows": [{"id": row, "label": "주전공"}],
            "cells": [
                {"row_id": row, "header_id": col, "state": "number", "value": "3.25"},
                {"row_id": row, "header_id": total, "state": "number", "value": "0"},
                {"row_id": row, "header_id": na, "state": "not_applicable"},
            ],
        },
    )
    activation(e)

    def link_record(term):
        record = (
            e["c"]
            .post(
                ME + "course-records",
                headers=e["student"],
                json={
                    "title": "수강 설계",
                    "term": term,
                    "category": "보존 분류",
                    "credits": "3.5",
                    "completion": "recorded",
                },
            )
            .json()
        )
        body = command(
            expected_version=0,
            expected_record_version=record["version"],
            context_id=e["context"]["id"],
            entry_id=e["cur"]["courses"][0]["id"],
            result="completed",
            earned_credits="3.25",
        )
        response = e["c"].put(
            ME + f"course-records/{record['id']}/academic-link", headers=e["student"], json=body
        )
        assert response.status_code == 200, response.text
        assert (
            e["c"]
            .put(
                ME + f"course-records/{record['id']}/academic-link", headers=e["student"], json=body
            )
            .json()
            == response.json()
        )
        return record, body

    first, _ = link_record("2026-1")
    view = e["c"].get(ME + "academic-credit-progress", headers=e["student"])
    assert view.status_code == 200, view.text
    cells = {r["header_id"]: r for r in view.json()["tables"][0]["cells"]}
    assert cells[col]["earned"] == "3.125" and cells[col]["remaining"] == "0.125"
    assert cells[total]["target"] == "0" and cells[total]["earned"] == "3.125"
    assert cells[empty]["target"] is None and cells[empty]["remaining"] is None
    assert cells[na]["status"] == "not_applicable"
    second, body = link_record("2026-2")
    retake = (
        e["c"]
        .get(ME + "academic-credit-progress", headers=e["student"])
        .json()["tables"][0]["cells"][0]
    )
    assert retake["earned"] == "0" and retake["status"] == "needs_review"
    body.update(client_id=str(uuid4()), expected_version=1, included=False)
    assert (
        e["c"]
        .put(ME + f"course-records/{second['id']}/academic-link", headers=e["student"], json=body)
        .status_code
        == 200
    )
    resolved = (
        e["c"]
        .get(ME + "academic-credit-progress", headers=e["student"])
        .json()["tables"][0]["cells"][0]
    )
    assert resolved["earned"] == "3.125"
    assert (
        e["c"].get(ME + f"course-records/{first['id']}", headers=e["student"]).json()["category"]
        == "보존 분류"
    )
    # The same source course in a second major needs a school recognition policy.
    extra = department(e["c"], e["admin"], e["inst"], code="EXTRA")
    workspace = e["c"].get(ME + "academic-contexts", headers=e["student"]).json()
    primary = {
        key: workspace["contexts"][0][key]
        for key in (
            "id",
            "department_id",
            "track_id",
            "curriculum_revision_id",
            "admission_year",
            "primary",
        )
    }
    saved = e["c"].put(
        ME + "academic-contexts",
        headers=e["student"],
        json=command(
            expected_version=workspace["version"],
            contexts=[
                primary,
                {
                    **{key: value for key, value in primary.items() if key != "id"},
                    "department_id": extra["id"],
                    "primary": False,
                },
            ],
        ),
    )
    assert saved.status_code == 200
    extra_context = next(c for c in saved.json()["contexts"] if not c["primary"])
    activation(e)
    linked = e["c"].put(
        ME + f"course-records/{first['id']}/academic-link",
        headers=e["student"],
        json=command(
            expected_version=0,
            expected_record_version=first["version"],
            context_id=extra_context["id"],
            entry_id=e["cur"]["courses"][0]["id"],
            result="completed",
            earned_credits="3.25",
        ),
    )
    assert linked.status_code == 200, linked.text
    ambiguous = (
        e["c"]
        .get(ME + "academic-credit-progress", headers=e["student"])
        .json()["tables"][0]["cells"][0]
    )
    assert ambiguous["earned"] == "0" and ambiguous["status"] == "needs_review"
    assert any(
        v["reason"] == "multiple_major_policy_required" and v["credits"] == "3.125"
        for v in ambiguous["evidence"]
    )


def test_scope_filtering_profile_invalidation_and_stale_preview(academic_student):
    e = academic_student
    included, excluded = str(uuid4()), str(uuid4())
    requirement(
        e,
        {
            "kind": "checklist",
            "lines": [
                {
                    "id": included,
                    "text": "해당",
                    "scope": {"clauses": [{"admission_from": 2026, "admission_to": 2026}]},
                },
                {
                    "id": excluded,
                    "text": "제외",
                    "scope": {"clauses": [{"admission_from": 2027, "admission_to": 2027}]},
                },
            ],
        },
    )
    preview = e["c"].get(ME + "academic-requirements/preview", headers=e["student"]).json()
    assert [line["id"] for line in preview["documents"][0]["content"]["lines"]] == [included]
    changed = e["c"].patch(
        ME + "planning-profile",
        headers=e["student"],
        json={"expected_version": 1, "admission_year": 2025},
    )
    assert changed.status_code == 200
    response = e["c"].post(
        ME + "academic-requirements/activate",
        headers=e["student"],
        json=command(
            expected_version=preview["workspace_version"], expected_digest=preview["digest"]
        ),
    )
    assert response.status_code == 409


def test_additional_contexts_share_common_items_and_choose_revisions_per_context(academic_student):
    e = academic_student
    extra = department(e["c"], e["admin"], e["inst"], code="EXTRA")
    current = e["c"].get(ME + "academic-contexts", headers=e["student"]).json()
    primary = {
        key: current["contexts"][0][key]
        for key in (
            "id",
            "department_id",
            "track_id",
            "curriculum_revision_id",
            "admission_year",
            "primary",
        )
    }
    response = e["c"].put(
        ME + "academic-contexts",
        headers=e["student"],
        json=command(
            expected_version=current["version"],
            contexts=[
                primary,
                {
                    **{key: value for key, value in primary.items() if key != "id"},
                    "department_id": extra["id"],
                    "primary": False,
                },
            ],
        ),
    )
    assert response.status_code == 200, response.text
    item = str(uuid4())
    old = requirement(e, {"kind": "checklist", "lines": [{"id": item, "text": "공통 문장"}]})
    initial = activation(e)
    assert len(initial["documents"]) == 1
    assert len(initial["documents"][0]["node_contexts"][item]) == 2
    url = ROOT + "/requirement-revisions/" + old["id"]
    copied = (
        e["c"]
        .post(url + "/drafts", headers=e["admin"], json=command(expected_version=old["version"]))
        .json()
    )
    saved, _ = save(
        e["c"],
        e["admin"],
        copied,
        {"kind": "checklist", "lines": [{"id": item, "text": "추가 전공 개정"}]},
        scope={"clauses": [{"department_id": extra["id"]}]},
    )
    revised = publish(e["c"], e["admin"], saved)
    changed = activation(e)
    assert {d["id"] for d in changed["documents"]} == {old["id"], revised["id"]}
    assert all(len(d["context_ids"]) == 1 for d in changed["documents"])


def test_inactive_track_keeps_existing_student_binding_but_cannot_be_newly_selected(
    academic_student,
):
    e = academic_student
    result = e["c"].patch(
        ROOT + "/study-tracks/" + e["track"]["id"],
        headers=e["admin"],
        json=command(
            expected_version=e["track"]["version"], name=e["track"]["name"], inactive=True
        ),
    )
    assert result.status_code == 200
    assert e["c"].get(ME + "academic-contexts", headers=e["student"]).json()["issues"] == []
    options = (
        e["c"]
        .get(
            "/api/v1/catalog/academic/options",
            headers=e["student"],
            params={"institution_id": e["inst"]["id"]},
        )
        .json()
    )
    assert options["tracks"] == []


def test_new_curriculum_is_announced_without_rebinding_student(academic_student):
    e = academic_student
    url = ROOT + "/curriculum-revisions/" + e["cur"]["id"]
    draft = e["c"].post(
        url + "/drafts", headers=e["admin"], json=command(expected_version=e["cur"]["version"])
    )
    assert draft.status_code == 201, draft.text
    new = draft.json()
    new_url = ROOT + "/curriculum-revisions/" + new["id"]
    preview = (
        e["c"]
        .post(
            new_url + "/preview-publication",
            headers=e["admin"],
            json={"expected_version": new["version"]},
        )
        .json()
    )
    result = e["c"].post(
        new_url + "/publish",
        headers=e["admin"],
        json=command(
            expected_version=new["version"],
            expected_digest=preview["digest"],
            review_note="개정 안내",
        ),
    )
    assert result.status_code == 200, result.text
    shown = e["c"].get(ME + "academic-requirements/preview", headers=e["student"]).json()
    assert shown["curriculum_updates"][0]["new_revision_id"] == new["id"]
    current = e["c"].get(ME + "academic-contexts", headers=e["student"]).json()
    assert current["contexts"][0]["curriculum_revision_id"] == e["cur"]["id"]
