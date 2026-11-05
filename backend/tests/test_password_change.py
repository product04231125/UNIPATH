import pytest
from pydantic import ValidationError
from sqlalchemy import select
from test_auth import PASSWORD, authorization, login, register
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db

from app.models.identity import AuthSession, IdentityAudit, User
from app.schemas.auth import PasswordChangeRequest
from app.services.auth import PASSWORDS

NEW_PASSWORD = "synthetic changed password 2026"


def test_password_change_contract_is_bounded_and_forbids_target_account():
    for values in ({"new_password": "short"}, {"new_password": "x" * 129}, {"user_id": "other"}):
        with pytest.raises(ValidationError):
            PasswordChangeRequest.model_validate(
                {
                    "old_password": PASSWORD,
                    "new_password": NEW_PASSWORD,
                    **values,
                }
            )
    assert PASSWORD not in str(
        PasswordChangeRequest(old_password=PASSWORD, new_password=NEW_PASSWORD)
    )


@pytest.mark.integration
def test_password_change_revokes_all_sessions_and_preserves_personal_records(auth_client, auth_db):
    c = auth_client
    h = authorization(register(c))
    other_session = authorization(login(c))
    item = c.post("/api/v1/me/credential-records", headers=h, json={"title": "합성 자격"}).json()
    response = c.post(
        "/api/v1/auth/change-password",
        headers=h,
        json={"old_password": PASSWORD, "new_password": NEW_PASSWORD},
    )
    assert response.status_code == 204, response.text
    assert response.headers["Cache-Control"] == "no-store"
    for token in (h, other_session):
        assert c.get("/api/v1/auth/me", headers=token).status_code == 401
        assert c.get("/api/v1/me/credential-records", headers=token).status_code == 401
    assert login(c).status_code == 401
    fresh = authorization(login(c, password=NEW_PASSWORD))
    assert c.get("/api/v1/me/credential-records/" + item["id"], headers=fresh).status_code == 200
    with auth_db() as db:
        user = db.scalar(select(User))
        assert PASSWORDS.verify(user.password_hash, NEW_PASSWORD)
        assert user.version == 2
        events = list(
            db.scalars(select(IdentityAudit).where(IdentityAudit.action == "password_changed"))
        )
        assert len(events) == 1 and events[0].actor_id == user.id and events[0].target_id == user.id
        assert db.scalar(select(AuthSession).where(AuthSession.revoked_at.is_(None))) is not None


@pytest.mark.integration
def test_wrong_old_password_is_not_session_expiration_and_is_rate_limited(auth_client):
    c = auth_client
    h = authorization(register(c))
    body = {"old_password": "synthetic wrong password", "new_password": NEW_PASSWORD}
    for _ in range(5):
        response = c.post("/api/v1/auth/change-password", headers=h, json=body)
        assert response.status_code == 422
        assert PASSWORD not in response.text and body["old_password"] not in response.text
    assert c.get("/api/v1/auth/me", headers=h).status_code == 200
    response = c.post("/api/v1/auth/change-password", headers=h, json=body)
    assert response.status_code == 429 and response.headers["Retry-After"] == "900"
    assert c.post("/api/v1/auth/change-password", json=body).status_code == 401


@pytest.mark.integration
def test_cookie_password_change_requires_origin_and_deletes_cookie(auth_client):
    c = auth_client
    register(c, mode="cookie")
    body = {"old_password": PASSWORD, "new_password": NEW_PASSWORD}
    assert c.post("/api/v1/auth/change-password", json=body).status_code == 403
    assert (
        c.post(
            "/api/v1/auth/change-password", headers={"Origin": "https://other.test"}, json=body
        ).status_code
        == 403
    )
    response = c.post(
        "/api/v1/auth/change-password", headers={"Origin": "http://localhost:3000"}, json=body
    )
    assert response.status_code == 204
    assert "Max-Age=0" in response.headers["set-cookie"]
    assert c.get("/api/v1/auth/me").status_code == 401
