from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
from uuid import UUID, uuid4

import pytest
from pydantic import ValidationError
from sqlalchemy import func, select
from test_academic import operator, school
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register

from app.models.admin_applications import SchoolAdminApplication
from app.models.identity import AdminScope, IdentityAudit, Institution, User
from app.schemas.admin_applications import (
    SchoolAdminApplicationApprove,
    SchoolAdminApplicationCreate,
)

OWN = "/api/v1/me/school-admin-applications"
ADMIN = "/api/v1/admin/school-admin-applications"
integration = pytest.mark.integration


def payload(institution, **extra):
    return {
        "institution_id": institution["id"],
        "client_id": str(uuid4()),
        "position": "합성 학과 담당자",
        "contact_email": "staff@example.test",
        "reason": "합성 학교 담당자 검토 요청",
        **extra,
    }


def submit(c, h, institution, **extra):
    response = c.post(OWN, headers=h, json=payload(institution, **extra))
    assert response.status_code == 201, response.text
    return response.json()


def approve_payload(c, h, application, **extra):
    current = c.get(ADMIN + "/" + application["id"], headers=h).json()
    return {
        "expected_version": application["version"],
        "expected_user_version": current["applicant"]["version"],
        "identity_verified": True,
        "affiliation_verified": True,
        "review_note": "합성 담당자와 학교 소속을 별도 확인함",
        **extra,
    }


def test_strict_request_contract_never_accepts_self_assigned_privileges():
    value = payload({"id": str(uuid4())})
    for extra in (
        {"role": "school_admin"},
        {"applicant_id": str(uuid4())},
        {"status": "approved"},
        {"identity_verified": True},
        {"reason": " "},
    ):
        with pytest.raises(ValidationError):
            SchoolAdminApplicationCreate.model_validate({**value, **extra})
    decision = {
        "expected_version": 1,
        "expected_user_version": 1,
        "identity_verified": True,
        "affiliation_verified": True,
        "review_note": "확인",
    }
    for extra in (
        {"identity_verified": False},
        {"affiliation_verified": 1},
        {"expected_version": True},
        {"review_note": " "},
    ):
        with pytest.raises(ValidationError):
            SchoolAdminApplicationApprove.model_validate({**decision, **extra})


@integration
def test_own_request_is_pending_idempotent_private_and_does_not_grant_access(auth_client, auth_db):
    c = auth_client
    root = operator(c, auth_db)
    institution = school(c, root)
    first = authorization(register(c))
    other = authorization(register(c, "other@example.test"))
    body = payload(institution)
    response = c.post(OWN, headers=first, json=body)
    assert response.status_code == 201, response.text
    assert response.headers["Cache-Control"] == "no-store"
    row = response.json()
    assert row["status"] == "pending" and row["granted_scope_id"] is None
    assert c.post(OWN, headers=first, json=body).json()["id"] == row["id"]
    assert c.post(OWN, headers=first, json={**body, "reason": "다른 요청"}).status_code == 409
    assert c.post(OWN, headers=first, json=payload(institution)).status_code == 409
    assert c.get(OWN, headers=other).json()["items"] == []
    assert c.get(OWN + "/" + row["id"], headers=other).status_code == 404
    assert (
        c.post(
            OWN + "/" + row["id"] + "/cancel", headers=other, json={"expected_version": 1}
        ).status_code
        == 404
    )
    assert c.get(ADMIN, headers=first).status_code == 403
    assert c.get("/api/v1/auth/me", headers=first).json()["user"]["role"] == "user"
    assert c.get("/api/v1/admin/institutions", headers=first).status_code == 403
    assert "applicant" not in row


@integration
def test_approval_atomically_grants_only_requested_school_and_audits_minimal_metadata(
    auth_client, auth_db
):
    c = auth_client
    root = operator(c, auth_db)
    institution = school(c, root)
    other = school(c, root, "다른 합성대")
    user = authorization(register(c))
    row = submit(c, user, institution)
    decision = approve_payload(c, root, row)
    path = ADMIN + "/" + row["id"] + "/approve"
    assert c.post(path, headers=user, json=decision).status_code == 403
    assert (
        c.post(path, headers=root, json={**decision, "expected_user_version": 99}).status_code
        == 409
    )
    assert c.post(path, headers=root, json={**decision, "expected_version": 99}).status_code == 409
    assert c.get("/api/v1/auth/me", headers=user).json()["admin_scopes"] == []
    result = c.post(path, headers=root, json=decision)
    assert result.status_code == 200, result.text
    result = result.json()
    assert result["status"] == "approved" and result["version"] == 2
    assert result["identity_verified"] and result["affiliation_verified"]
    me = c.get("/api/v1/auth/me", headers=user).json()
    assert me["user"]["role"] == "school_admin" and me["permission_version"] == 2
    assert [scope["institution_id"] for scope in me["admin_scopes"]] == [institution["id"]]
    assert c.get("/api/v1/admin/institutions/" + institution["id"], headers=user).status_code == 200
    assert c.get("/api/v1/admin/institutions/" + other["id"], headers=user).status_code == 403
    assert c.post(path, headers=root, json=decision).status_code == 409
    with auth_db() as db:
        scope = db.get(AdminScope, UUID(result["granted_scope_id"]))
        assert scope.user_id == UUID(row["applicant_id"])
        events = list(
            db.scalars(select(IdentityAudit).where(IdentityAudit.target_id == UUID(row["id"])))
        )
        assert {event.action for event in events} == {
            "admin_application_submitted",
            "admin_application_approved",
        }
        assert all(not hasattr(event, "reason") for event in events)
    # Approval is historical; later scope revocation must still remove actual access.
    c.post(
        "/api/v1/admin/scopes/" + result["granted_scope_id"] + "/revoke",
        headers=root,
        json={"expected_version": 1},
    )
    assert c.get(OWN + "/" + row["id"], headers=user).json()["status"] == "approved"
    assert c.get("/api/v1/admin/institutions/" + institution["id"], headers=user).status_code == 403


@integration
def test_rejection_cancel_resubmit_and_cursor_preserve_terminal_history(auth_client, auth_db):
    c = auth_client
    root = operator(c, auth_db)
    institution = school(c, root)
    user = authorization(register(c))
    original = payload(institution)
    first = c.post(OWN, headers=user, json=original).json()
    rejected = c.post(
        ADMIN + "/" + first["id"] + "/reject",
        headers=root,
        json={"expected_version": 1, "review_note": "담당자 확인 자료 보완 필요"},
    )
    assert rejected.status_code == 200
    assert rejected.json()["status"] == "rejected"
    assert c.post(OWN, headers=user, json=original).json()["status"] == "rejected"
    second = submit(c, user, institution)
    cancelled = c.post(
        OWN + "/" + second["id"] + "/cancel", headers=user, json={"expected_version": 1}
    )
    assert cancelled.status_code == 200 and cancelled.json()["status"] == "cancelled"
    assert (
        c.post(
            OWN + "/" + second["id"] + "/cancel", headers=user, json={"expected_version": 1}
        ).status_code
        == 409
    )
    assert (
        c.post(
            ADMIN + "/" + second["id"] + "/approve",
            headers=root,
            json=approve_payload(c, root, second),
        ).status_code
        == 409
    )
    third = submit(c, user, institution)
    items, cursor = [], None
    for _ in range(3):
        query = {"limit": 1, **({"cursor": cursor} if cursor else {})}
        page = c.get(OWN, headers=user, params=query).json()
        items.extend(item["id"] for item in page["items"])
        cursor = page["next_cursor"]
        if cursor is None:
            break
    assert set(items) == {first["id"], second["id"], third["id"]}
    assert len(c.get(ADMIN + "?status=pending", headers=root).json()["items"]) == 1
    assert c.get(OWN + "?status=unknown", headers=user).status_code == 422


@integration
def test_suspended_archived_or_externally_changed_accounts_cannot_be_approved(auth_client, auth_db):
    c = auth_client
    root = operator(c, auth_db)
    institution = school(c, root)
    user = authorization(register(c))
    row = submit(c, user, institution)
    path = ADMIN + "/" + row["id"] + "/approve"
    body = approve_payload(c, root, row)
    changed = c.patch(
        "/api/v1/admin/users/" + row["applicant_id"] + "/status",
        headers=root,
        json={"account_status": "suspended", "expected_version": 1},
    )
    assert changed.status_code == 200
    assert c.post(path, headers=root, json=body).status_code == 409
    assert c.post(OWN, headers=user, json=payload(institution)).status_code == 401
    with auth_db() as db:
        assert db.scalar(select(func.count()).select_from(AdminScope)) == 0
        assert db.get(SchoolAdminApplication, UUID(row["id"])).status == "pending"
        applicant = db.get(User, UUID(row["applicant_id"]))
        applicant.account_status = "active"
        db.get(Institution, UUID(institution["id"])).deleted_at = datetime.now(UTC)
        db.commit()
    body = approve_payload(c, root, row)
    assert c.post(path, headers=root, json=body).status_code == 409
    assert c.post(OWN, headers=user, json=payload(institution)).status_code == 401


@integration
def test_pending_limit_and_cookie_origin_protect_new_requests(auth_client, auth_db):
    c = auth_client
    root = operator(c, auth_db)
    institutions = [school(c, root, f"합성 학교 {i}") for i in range(6)]
    register(c, mode="cookie")
    assert c.post(OWN, json=payload(institutions[0])).status_code == 403
    user = {"Origin": "http://localhost:3000"}
    for institution in institutions[:5]:
        submit(c, user, institution)
    denied = c.post(OWN, headers=user, json=payload(institutions[5]))
    assert denied.status_code == 429
    assert denied.json()["error"]["code"] == "RATE_LIMITED"


@integration
def test_concurrent_decisions_never_grant_duplicate_scopes(auth_client, auth_db):
    c = auth_client
    root = operator(c, auth_db)
    institution = school(c, root)
    user = authorization(register(c))
    row = submit(c, user, institution)
    body = approve_payload(c, root, row)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(
            pool.map(
                lambda _: (
                    c.post(
                        ADMIN + "/" + row["id"] + "/approve", headers=root, json=body
                    ).status_code
                ),
                range(2),
            )
        )
    assert sorted(results) == [200, 409]
    with auth_db() as db:
        assert db.scalar(select(func.count()).select_from(AdminScope)) == 1
