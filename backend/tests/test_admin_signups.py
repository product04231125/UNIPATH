from concurrent.futures import ThreadPoolExecutor
from uuid import UUID, uuid4

import pytest
from pydantic import ValidationError
from sqlalchemy import event, func, select
from sqlalchemy.orm import Session
from test_academic import operator, school
from test_auth import PASSWORD, authorization, register
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db

from app.models.admin_signups import SchoolAdminSignup
from app.models.identity import AdminScope, AuthSession, Institution, User
from app.schemas.admin_signups import SchoolAdminSignupApprove, SchoolAdminSignupRegister
from app.services import auth

PUBLIC = "/api/v1/auth/school-admin-signups"
OWN = "/api/v1/me/school-admin-signups"
ADMIN = "/api/v1/admin/school-admin-signups"
integration = pytest.mark.integration


def payload(**extra):
    return {
        "email": "new-staff@example.test",
        "display_name": "합성 담당자",
        "password": PASSWORD,
        "session_mode": "bearer",
        "client_id": str(uuid4()),
        "school_name": "합성 미등록 대학교",
        "official_url": "https://school.example.test",
        "position": "합성 학과 담당자",
        "contact_email": "contact@example.test",
        "reason": "합성 학교 관리자 접수",
        **extra,
    }


def initial(c, **extra):
    response = c.post(PUBLIC, json=payload(**extra))
    assert response.status_code == 201, response.text
    return response.json(), authorization(response)


def decision(c, root, row, **extra):
    current = c.get(ADMIN + "/" + row["id"], headers=root).json()
    return {
        "expected_version": row["version"],
        "expected_user_version": current["applicant"]["version"],
        "identity_verified": True,
        "affiliation_verified": True,
        "review_note": "합성 신원·담당자 자격 확인",
        **extra,
    }


def test_registration_contract_and_explicit_school_choice_are_strict():
    value = SchoolAdminSignupRegister.model_validate(
        payload(email=" NEW-STAFF@EXAMPLE.TEST ", contact_email=" CONTACT@EXAMPLE.TEST ")
    )
    assert value.email == "new-staff@example.test"
    assert value.contact_email == "contact@example.test"
    for changes in (
        {"role": "school_admin"},
        {"applicant_id": str(uuid4())},
        {"institution_id": str(uuid4())},
        {"password": "short"},
        {"school_name": "bad\x00name"},
        {"official_url": "https://u:p@example.test"},
    ):
        with pytest.raises(ValidationError):
            SchoolAdminSignupRegister.model_validate(payload(**changes))
    base = {
        "expected_version": 1,
        "expected_user_version": 1,
        "identity_verified": True,
        "affiliation_verified": True,
        "review_note": "확인",
    }
    for changes in (
        {},
        {"institution_id": str(uuid4())},
        {
            "new_institution": {"name": "합성"},
            "institution_id": str(uuid4()),
            "expected_institution_version": 1,
        },
    ):
        with pytest.raises(ValidationError):
            SchoolAdminSignupApprove.model_validate({**base, **changes})


@integration
def test_initial_signup_is_atomic_unprivileged_and_replays_one_receipt(auth_client, auth_db):
    c = auth_client
    body = payload()
    response = c.post(PUBLIC, json=body)
    assert response.status_code == 201, response.text
    first = response.json()
    h = authorization(response)
    assert first["user"]["role"] == "user" and first["admin_scopes"] == []
    row = first["signup"]
    assert row["status"] == "pending" and row["institution_id"] is None
    assert c.get("/api/v1/admin/institutions", headers=h).status_code == 403
    assert c.get(OWN, headers=h).json()["items"][0]["id"] == row["id"]
    second = c.post(PUBLIC, json=body)
    assert second.status_code == 201
    assert second.json()["signup"]["id"] == row["id"]
    assert second.json()["user"]["id"] == first["user"]["id"]
    assert c.post(PUBLIC, json={**body, "reason": "다른 요청"}).status_code == 409
    with auth_db() as db:
        assert db.scalar(select(func.count()).select_from(User)) == 1
        assert db.scalar(select(func.count()).select_from(SchoolAdminSignup)) == 1
        assert db.scalar(select(func.count()).select_from(Institution)) == 0
        assert db.scalar(select(func.count()).select_from(AuthSession)) == 2
        assert PASSWORD not in db.scalar(select(User.password_hash))


@integration
def test_failed_session_issuance_leaves_neither_account_nor_receipt(
    auth_client, auth_db, monkeypatch
):
    body = payload()
    with monkeypatch.context() as patch:

        def fail(*args, **kwargs):
            raise RuntimeError("synthetic failure before transaction commit")

        patch.setattr(auth, "establish", fail)
        assert auth_client.post(PUBLIC, json=body).status_code == 500
    with auth_db() as db:
        assert db.scalar(select(func.count()).select_from(User)) == 0
        assert db.scalar(select(func.count()).select_from(SchoolAdminSignup)) == 0
    assert auth_client.post(PUBLIC, json=body).status_code == 201


@integration
def test_verified_approval_registers_school_role_and_scope_together(auth_client, auth_db):
    c = auth_client
    result, owner = initial(c)
    row = result["signup"]
    root = operator(c, auth_db)
    body = decision(
        c,
        root,
        row,
        new_institution={"name": "검토한 합성대", "official_url": "https://school.example.test"},
    )
    endpoint = ADMIN + "/" + row["id"] + "/approve"
    assert c.post(endpoint, headers=owner, json=body).status_code == 403
    assert (
        c.post(endpoint, headers=root, json={**body, "expected_user_version": 99}).status_code
        == 409
    )
    response = c.post(endpoint, headers=root, json=body)
    assert response.status_code == 200, response.text
    approved = response.json()
    assert approved["status"] == "approved" and approved["institution_name"] == "검토한 합성대"
    assert approved["school_name"] == row["school_name"]
    me = c.get("/api/v1/auth/me", headers=owner).json()
    assert me["user"]["role"] == "school_admin" and me["permission_version"] == 2
    assert len(me["admin_scopes"]) == 1
    assert me["admin_scopes"][0]["institution_id"] == approved["institution_id"]
    assert c.post(endpoint, headers=root, json=body).status_code == 409
    with auth_db() as db:
        assert db.scalar(select(func.count()).select_from(Institution)) == 1
        assert db.scalar(select(func.count()).select_from(AdminScope)) == 1


@integration
def test_existing_school_selection_and_name_conflict_preserve_pending_request(auth_client, auth_db):
    c = auth_client
    result, owner = initial(c)
    row = result["signup"]
    root = operator(c, auth_db)
    existing = school(c, root)
    endpoint = ADMIN + "/" + row["id"] + "/approve"
    duplicate = decision(c, root, row, new_institution={"name": existing["name"]})
    assert c.post(endpoint, headers=root, json=duplicate).status_code == 409
    assert c.get(OWN + "/" + row["id"], headers=owner).json()["status"] == "pending"
    body = decision(c, root, row, institution_id=existing["id"], expected_institution_version=99)
    assert c.post(endpoint, headers=root, json=body).status_code == 409
    body["expected_institution_version"] = existing["version"]
    assert c.post(endpoint, headers=root, json=body).status_code == 200
    with auth_db() as db:
        assert db.scalar(select(func.count()).select_from(Institution)) == 1


@integration
def test_owner_isolation_rejection_resubmission_and_concurrent_decisions(auth_client, auth_db):
    c = auth_client
    result, owner = initial(c)
    row = result["signup"]
    other = authorization(register(c))
    assert c.get(OWN + "/" + row["id"], headers=other).status_code == 404
    root = operator(c, auth_db)
    response = c.post(
        ADMIN + "/" + row["id"] + "/reject",
        headers=root,
        json={"expected_version": 1, "review_note": "자격 자료 보완 필요"},
    )
    assert response.status_code == 200
    new = {
        key: value
        for key, value in payload().items()
        if key not in {"email", "display_name", "password", "session_mode"}
    }
    response = c.post(OWN, headers=owner, json=new)
    assert response.status_code == 201, response.text
    second = response.json()
    body = decision(c, root, second, new_institution={"name": "동시 검토 합성대"})
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(
            pool.map(
                lambda _: (
                    c.post(
                        ADMIN + "/" + second["id"] + "/approve", headers=root, json=body
                    ).status_code
                ),
                range(2),
            )
        )
    assert sorted(results) == [200, 409]


@integration
def test_public_replay_requires_password_and_cookie_origin(auth_client, auth_db):
    c = auth_client
    body = payload(session_mode="cookie")
    assert c.post(PUBLIC, json=body).status_code == 403
    headers = {"Origin": "http://localhost:3000"}
    response = c.post(PUBLIC, headers=headers, json=body)
    assert response.status_code == 201, response.text
    assert response.json()["access_token"] is None
    assert "httponly" in response.headers["set-cookie"].lower()
    assert (
        c.post(
            PUBLIC, headers=headers, json={**body, "password": "invalid password 2026"}
        ).status_code
        == 401
    )
    assert c.get(OWN).status_code == 200


@integration
def test_existing_registration_cannot_be_claimed_as_a_new_school_signup(auth_client):
    register(auth_client, "new-staff@example.test")
    assert auth_client.post(PUBLIC, json=payload()).status_code == 409


@integration
def test_school_creation_rolls_back_when_scope_write_fails(auth_client, auth_db):
    c = auth_client
    result, _ = initial(c)
    row = result["signup"]
    root = operator(c, auth_db)
    body = decision(c, root, row, new_institution={"name": "롤백 확인 합성대"})

    def fail_scope(session, *args):
        if any(isinstance(value, AdminScope) for value in session.new):
            raise RuntimeError("synthetic scope failure")

    event.listen(Session, "before_flush", fail_scope)
    try:
        assert (
            c.post(ADMIN + "/" + row["id"] + "/approve", headers=root, json=body).status_code == 500
        )
    finally:
        event.remove(Session, "before_flush", fail_scope)
    with auth_db() as db:
        assert db.scalar(select(func.count()).select_from(Institution)) == 0
        assert db.scalar(select(func.count()).select_from(AdminScope)) == 0
        assert db.get(SchoolAdminSignup, UUID(row["id"])).status == "pending"
        assert db.get(User, UUID(row["applicant_id"])).role == "user"


@integration
def test_concurrent_initial_replays_create_one_account_and_receipt(auth_client, auth_db):
    body = payload()
    with ThreadPoolExecutor(max_workers=2) as pool:
        responses = list(pool.map(lambda _: auth_client.post(PUBLIC, json=body), range(2)))
    assert [value.status_code for value in responses] == [201, 201]
    assert len({value.json()["signup"]["id"] for value in responses}) == 1
    with auth_db() as db:
        assert db.scalar(select(func.count()).select_from(User)) == 1
        assert db.scalar(select(func.count()).select_from(SchoolAdminSignup)) == 1
