from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlalchemy import create_engine, select, text
from sqlalchemy.orm import sessionmaker

from app.api.dependencies import get_session
from app.core.config import Settings
from app.main import create_app
from app.models import Base
from app.models.identity import AdminScope, AuthSession, AuthThrottle, IdentityAudit, User
from app.operations.users import bootstrap
from app.schemas.auth import RegisterRequest, normalized_email
from app.services.auth import PASSWORDS, token_hash

PASSWORD = "synthetic strong password 2026"


def test_password_hashes_are_salted_and_verifiable():
    first, second = PASSWORDS.hash(PASSWORD), PASSWORDS.hash(PASSWORD)
    assert first != second and first.startswith("$argon2id$")
    assert PASSWORDS.verify(first, PASSWORD)
    assert PASSWORD not in first


@pytest.mark.parametrize(
    "value", ["bad", "a..b@example.com", "a@-bad.test", "a@bad..test", "a@b.test\nX:Y"]
)
def test_reject_invalid_email(value):
    with pytest.raises(ValueError):
        normalized_email(value)


def test_registration_policy_has_no_role_or_owner_override():
    assert normalized_email(" Student@Example.Test ") == "student@example.test"
    for change in ({"role": "super_admin"}, {"user_id": str(uuid4())}, {"password": "short"}):
        with pytest.raises(ValidationError):
            RegisterRequest.model_validate(
                {
                    "email": "student@example.test",
                    "display_name": "합성 학생",
                    "password": PASSWORD,
                    **change,
                }
            )


@pytest.fixture
def auth_db():
    import os

    if os.getenv("RUN_DB_TESTS") != "1":
        pytest.skip("Requires isolated PostgreSQL test schema")
    engine = create_engine(Settings().sqlalchemy_url, hide_parameters=True)
    schema = "auth_test_" + uuid4().hex
    with engine.begin() as connection:
        connection.execute(text(f'CREATE SCHEMA "{schema}"'))
    isolated = engine.execution_options(schema_translate_map={None: schema})
    factory = sessionmaker(isolated, expire_on_commit=False)
    Base.metadata.create_all(isolated)
    try:
        yield factory
    finally:
        with engine.begin() as connection:
            connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        engine.dispose()


@pytest.fixture
def auth_client(auth_db):
    def session():
        with auth_db() as db:
            yield db

    app = create_app(Settings(_env_file=None, postgres_password="synthetic-test-password"))
    app.dependency_overrides[get_session] = session
    with TestClient(app, raise_server_exceptions=False) as client:
        yield client


def register(client, email="student@example.test", mode="bearer"):
    return client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "display_name": "합성 학생",
            "password": PASSWORD,
            "session_mode": mode,
        },
        headers={"Origin": "http://localhost:3000"} if mode == "cookie" else {},
    )


@pytest.mark.parametrize("mode", ["bearer", "cookie"])
def test_workspace_owner_precondition_prevents_cross_account_writes(auth_client, mode):
    first = register(auth_client, mode=mode).json()
    second = register(auth_client, email="other@example.test", mode=mode).json()
    headers = {"Origin": "http://localhost:3000"}
    if mode == "bearer":
        headers["Authorization"] = "Bearer " + second["access_token"]
    path = "/api/v1/me/planning-profile"
    # Both credentials are genuine; only the stale workspace account differs.
    for stale in (first["user"]["id"], "not-a-uuid"):
        denied = auth_client.patch(
            path,
            headers={**headers, "X-Unipath-Owner": stale},
            json={"school": "Must not be saved", "expected_version": 0},
        )
        assert denied.status_code == 403
        assert denied.json()["error"]["code"] == "FORBIDDEN"
    unchanged = auth_client.get(path, headers=headers).json()
    assert unchanged["version"] == 0 and unchanged["school"] == ""
    own_headers = {**headers, "X-Unipath-Owner": second["user"]["id"]}
    assert (
        auth_client.patch(
            path, headers=own_headers, json={"school": "Owned school", "expected_version": 0}
        ).status_code
        == 200
    )
    assert auth_client.get(path, headers=own_headers).json()["school"] == "Owned school"
    # Omitting the optional precondition keeps older clients compatible.
    assert auth_client.get(path, headers=headers).status_code == 200


def test_workspace_owner_header_is_allowed_by_browser_preflight():
    with TestClient(
        create_app(Settings(_env_file=None, postgres_password="synthetic-test-password"))
    ) as client:
        response = client.options(
            "/api/v1/me/planning-profile",
            headers={
                "Origin": "http://localhost:3000",
                "Access-Control-Request-Method": "PATCH",
                "Access-Control-Request-Headers": "content-type,x-unipath-owner",
            },
        )
    assert response.status_code == 200
    assert "x-unipath-owner" in response.headers["access-control-allow-headers"].lower()


@pytest.mark.integration
def test_admin_cookie_switch_cannot_save_another_admins_open_form(auth_client, auth_db):
    first_id, _ = super_admin(auth_client, auth_db)
    origin = {"Origin": "http://localhost:3000"}
    first = auth_client.post(
        "/api/v1/auth/login",
        headers=origin,
        json={"email": "operator@example.test", "password": PASSWORD, "session_mode": "cookie"},
    )
    assert first.status_code == 200
    second = register(auth_client, email="second-admin@example.test").json()
    second_id = second["user"]["id"]
    assert (
        auth_client.patch(
            f"/api/v1/admin/users/{second_id}/role",
            headers=origin,
            json={"role": "super_admin", "expected_version": 1},
        ).status_code
        == 200
    )
    assert (
        auth_client.post(
            "/api/v1/auth/login",
            headers=origin,
            json={
                "email": "second-admin@example.test",
                "password": PASSWORD,
                "session_mode": "cookie",
            },
        ).status_code
        == 200
    )
    denied = auth_client.post(
        "/api/v1/admin/institutions",
        headers={**origin, "X-Unipath-Owner": str(first_id)},
        json={"name": "Must not be created"},
    )
    assert denied.status_code == 403
    headers = {**origin, "X-Unipath-Owner": second_id}
    assert auth_client.get("/api/v1/admin/institutions", headers=headers).json()["items"] == []
    created = auth_client.post(
        "/api/v1/admin/institutions", headers=headers, json={"name": "Owned synthetic school"}
    )
    assert created.status_code == 201
    with auth_db() as db:
        entry = db.scalar(
            select(IdentityAudit).where(IdentityAudit.target_id == UUID(created.json()["id"]))
        )
        assert entry is not None and str(entry.actor_id) == second_id


def login(client, email="student@example.test", password=PASSWORD):
    return client.post(
        "/api/v1/auth/login",
        json={
            "email": email,
            "password": password,
            "session_mode": "bearer",
        },
    )


def authorization(response):
    assert response.status_code in (200, 201), response.text
    return {"Authorization": "Bearer " + response.json()["access_token"]}


def super_admin(client, factory):
    with factory() as db:
        user_id = bootstrap(
            db,
            RegisterRequest(
                email="operator@example.test", display_name="합성 운영자", password=PASSWORD
            ),
        )
    return user_id, authorization(login(client, "operator@example.test"))


@pytest.mark.integration
def test_register_login_me_and_database_only_contains_hashes(auth_client, auth_db):
    response = register(auth_client, "Student@Example.Test")
    headers = authorization(response)
    assert response.json()["user"]["role"] == "user"
    assert response.json()["user"]["email"] == "student@example.test"
    assert auth_client.get("/api/v1/auth/me", headers=headers).status_code == 200
    raw = response.json()["access_token"]
    with auth_db() as db:
        user = db.scalar(select(User))
        session = db.scalar(select(AuthSession))
        assert user.password_hash != PASSWORD and PASSWORDS.verify(user.password_hash, PASSWORD)
        assert session.token_hash == token_hash(raw) and raw != session.token_hash
    assert register(auth_client).status_code == 409
    assert login(auth_client, password="wrong").status_code == 401
    assert login(auth_client, "unknown@example.test", password="wrong").status_code == 401
    assert "password_hash" not in response.text and "token_hash" not in response.text


@pytest.mark.integration
def test_registration_cannot_self_assign_privileges(auth_client):
    payload = {
        "email": "attacker@example.test",
        "password": PASSWORD,
        "display_name": "합성 사용자",
        "role": "super_admin",
        "session_mode": "bearer",
    }
    response = auth_client.post("/api/v1/auth/register", json=payload)
    assert response.status_code == 422
    assert PASSWORD not in response.text
    UUID(response.json()["error"]["request_id"])
    user_headers = authorization(register(auth_client))
    assert auth_client.get("/api/v1/admin/users", headers=user_headers).status_code == 403
    assert (
        auth_client.post(
            "/api/v1/admin/institutions", json={"name": "합성대"}, headers=user_headers
        ).status_code
        == 403
    )


@pytest.mark.integration
def test_cookie_sessions_require_origin_and_cannot_be_used_as_bearer(auth_client):
    response = register(auth_client, mode="cookie")
    assert response.status_code == 201
    assert response.json()["access_token"] is None
    assert "httponly" in response.headers["set-cookie"].lower()
    assert "samesite=strict" in response.headers["set-cookie"].lower()
    cookie = auth_client.cookies.get("unipath_session")
    assert auth_client.get("/api/v1/auth/me").status_code == 200
    assert (
        auth_client.get(
            "/api/v1/auth/me", headers={"Authorization": "Bearer " + cookie}
        ).status_code
        == 401
    )
    assert auth_client.post("/api/v1/auth/logout").status_code == 403
    assert (
        auth_client.post("/api/v1/auth/logout", headers={"Origin": "https://evil.test"}).status_code
        == 403
    )
    assert (
        auth_client.post(
            "/api/v1/auth/logout", headers={"Origin": "http://localhost:3000"}
        ).status_code
        == 204
    )
    assert auth_client.get("/api/v1/auth/me").status_code == 401
    assert register(auth_client, "other@example.test", mode="cookie").status_code == 201
    assert (
        auth_client.post(
            "/api/v1/auth/login",
            json={"email": "student@example.test", "password": PASSWORD},
            headers={"Origin": "https://evil.test"},
        ).status_code
        == 403
    )


@pytest.mark.integration
def test_sessions_expire_logout_is_server_side_and_logout_all(auth_client, auth_db):
    first = authorization(register(auth_client))
    second = authorization(login(auth_client))
    assert auth_client.post("/api/v1/auth/logout", headers=first).status_code == 204
    assert auth_client.get("/api/v1/auth/me", headers=first).status_code == 401
    assert auth_client.get("/api/v1/auth/me", headers=second).status_code == 200
    third = authorization(login(auth_client))
    assert auth_client.post("/api/v1/auth/logout-all", headers=second).status_code == 204
    assert auth_client.get("/api/v1/auth/me", headers=third).status_code == 401
    fourth = authorization(login(auth_client))
    with auth_db() as db:
        session = db.get(AuthSession, token_hash(fourth["Authorization"][7:]))
        session.expires_at = datetime.now(UTC) - timedelta(seconds=1)
        db.commit()
    assert auth_client.get("/api/v1/auth/me", headers=fourth).status_code == 401


@pytest.mark.integration
def test_login_limits_survive_failed_requests_and_reset_after_window(auth_client, auth_db):
    register(auth_client)
    for _ in range(8):
        assert login(auth_client, password="wrong").status_code == 401
    response = login(auth_client)
    assert response.status_code == 429 and response.headers["Retry-After"] == "900"
    with auth_db() as db:
        bucket = db.get(AuthThrottle, token_hash("login:student@example.test"))
        bucket.window_start = datetime.now(UTC) - timedelta(minutes=16)
        db.commit()
    assert login(auth_client).status_code == 200


@pytest.mark.integration
def test_superadmin_scope_grant_revoke_and_direct_object_access(auth_client, auth_db):
    operator_id, admin = super_admin(auth_client, auth_db)
    student = register(auth_client)
    student_id, student_headers = student.json()["user"]["id"], authorization(student)
    first = auth_client.post(
        "/api/v1/admin/institutions", json={"name": "합성 대학 A"}, headers=admin
    ).json()
    second = auth_client.post(
        "/api/v1/admin/institutions", json={"name": "합성 대학 B"}, headers=admin
    ).json()
    response = auth_client.post(
        "/api/v1/admin/scopes",
        json={
            "user_id": student_id,
            "institution_id": first["id"],
            "reason": "합성 학교 담당 지정",
        },
        headers=admin,
    )
    assert response.status_code == 201, response.text
    scope = response.json()
    me = auth_client.get("/api/v1/auth/me", headers=student_headers).json()
    assert me["user"]["role"] == "school_admin" and len(me["admin_scopes"]) == 1
    assert auth_client.get("/api/v1/admin/institutions", headers=student_headers).json()[
        "items"
    ] == [first]
    assert (
        auth_client.get(
            f"/api/v1/admin/institutions/{second['id']}", headers=student_headers
        ).status_code
        == 403
    )
    assert (
        auth_client.get(
            f"/api/v1/admin/institutions/{first['id']}", headers=student_headers
        ).status_code
        == 200
    )
    assert auth_client.get("/api/v1/admin/users", headers=student_headers).status_code == 403
    assert (
        auth_client.post(
            "/api/v1/admin/scopes",
            json={"user_id": student_id, "institution_id": second["id"], "reason": "권한 우회"},
            headers=student_headers,
        ).status_code
        == 403
    )
    revoked = auth_client.post(
        f"/api/v1/admin/scopes/{scope['id']}/revoke",
        json={"expected_version": scope["version"]},
        headers=admin,
    )
    assert revoked.status_code == 200
    assert (
        auth_client.get(
            f"/api/v1/admin/institutions/{first['id']}", headers=student_headers
        ).status_code
        == 403
    )
    assert auth_client.get("/api/v1/auth/me", headers=student_headers).json()["admin_scopes"] == []
    assert (
        auth_client.patch(
            f"/api/v1/admin/users/{operator_id}/role",
            json={"role": "user", "expected_version": 1},
            headers=admin,
        ).status_code
        == 403
    )
    with auth_db() as db:
        actions = list(db.scalars(select(IdentityAudit.action)))
        assert {"scope_granted", "scope_revoked", "super_admin_bootstrapped"} <= set(actions)


@pytest.mark.integration
def test_suspension_revokes_existing_sessions_and_optimistic_versions(auth_client, auth_db):
    _, admin = super_admin(auth_client, auth_db)
    student = register(auth_client)
    student_id, headers = student.json()["user"]["id"], authorization(student)
    suspended = auth_client.patch(
        f"/api/v1/admin/users/{student_id}/status",
        json={"account_status": "suspended", "expected_version": 1},
        headers=admin,
    )
    assert suspended.status_code == 200
    assert auth_client.get("/api/v1/auth/me", headers=headers).status_code == 401
    assert login(auth_client).status_code == 401
    assert (
        auth_client.patch(
            f"/api/v1/admin/users/{student_id}/status",
            json={"account_status": "active", "expected_version": 1},
            headers=admin,
        ).status_code
        == 409
    )
    assert (
        auth_client.patch(
            f"/api/v1/admin/users/{student_id}/status",
            json={"account_status": "active", "expected_version": suspended.json()["version"]},
            headers=admin,
        ).status_code
        == 200
    )
    assert auth_client.get("/api/v1/auth/me", headers=headers).status_code == 401
    assert login(auth_client).status_code == 200


@pytest.mark.integration
def test_bootstrap_refuses_second_administrator(auth_client, auth_db):
    super_admin(auth_client, auth_db)
    with auth_db() as db, pytest.raises(ValueError):
        bootstrap(
            db,
            RegisterRequest(
                email="second@example.test", display_name="합성 운영자2", password=PASSWORD
            ),
        )


@pytest.mark.integration
def test_duplicate_active_scope_and_user_pagination(auth_client, auth_db):
    _, admin = super_admin(auth_client, auth_db)
    user_id = register(auth_client).json()["user"]["id"]
    school_id = auth_client.post(
        "/api/v1/admin/institutions", json={"name": "합성대"}, headers=admin
    ).json()["id"]
    payload = {"user_id": user_id, "institution_id": school_id, "reason": "담당 지정"}
    assert auth_client.post("/api/v1/admin/scopes", json=payload, headers=admin).status_code == 201
    assert auth_client.post("/api/v1/admin/scopes", json=payload, headers=admin).status_code == 409
    first = auth_client.get("/api/v1/admin/users?limit=1", headers=admin).json()
    second = auth_client.get(
        "/api/v1/admin/users", params={"limit": 1, "cursor": first["next_cursor"]}, headers=admin
    ).json()
    assert first["items"][0]["id"] != second["items"][0]["id"]
    assert "password_hash" not in str(first)
    with auth_db() as db:
        assert len(list(db.scalars(select(AdminScope)))) == 1


@pytest.mark.integration
def test_rate_limit_is_atomic_across_concurrent_workers(auth_db):
    from concurrent.futures import ThreadPoolExecutor

    from app.core.auth_errors import AuthError
    from app.services.auth import throttle

    def attempt(_):
        with auth_db() as db:
            try:
                throttle(db, "concurrent:synthetic@example.test", limit=8)
                return 200
            except AuthError as error:
                return error.status

    with ThreadPoolExecutor(max_workers=8) as executor:
        results = list(executor.map(attempt, range(12)))
    assert results.count(200) == 8 and results.count(429) == 4


@pytest.mark.integration
def test_staging_cookie_has_host_prefix_secure_flag_and_no_domain(auth_db):
    def session():
        with auth_db() as db:
            yield db

    app = create_app(
        Settings(
            _env_file=None,
            app_env="staging",
            postgres_password="synthetic-test-password",
            cors_origins=["https://staging.example.test"],
        )
    )
    app.dependency_overrides[get_session] = session
    with TestClient(app, base_url="https://staging.example.test") as client:
        response = client.post(
            "/api/v1/auth/register",
            json={
                "email": "secure@example.test",
                "display_name": "합성 학생",
                "password": PASSWORD,
            },
            headers={"Origin": "https://staging.example.test"},
        )
        assert response.status_code == 201
        cookie = response.headers["set-cookie"].lower()
        assert (
            cookie.startswith("__host-unipath_session=")
            and "secure" in cookie
            and "httponly" in cookie
        )
        assert "domain=" not in cookie and "path=/" in cookie and "samesite=strict" in cookie
        assert client.get("/api/v1/auth/me").status_code == 200


@pytest.mark.integration
def test_suspension_serializes_with_inflight_login(auth_client, auth_db, monkeypatch):
    from concurrent.futures import ThreadPoolExecutor
    from concurrent.futures import TimeoutError as FutureTimeout
    from threading import Event
    from types import SimpleNamespace

    from sqlalchemy import event

    from app.services import auth

    _, operator = super_admin(auth_client, auth_db)
    student_id = register(auth_client).json()["user"]["id"]
    verifying, release, updating = Event(), Event(), Event()
    original = auth.PASSWORDS

    def delayed_verify(encoded, password):
        result = original.verify(encoded, password)
        verifying.set()
        assert release.wait(10)
        return result

    monkeypatch.setattr(
        auth,
        "PASSWORDS",
        SimpleNamespace(
            verify=delayed_verify,
            hash=original.hash,
            check_needs_rehash=original.check_needs_rehash,
        ),
    )

    def before_update(conn, cursor, statement, parameters, context, executemany):
        if statement.startswith("UPDATE") and "SET account_status" in statement:
            updating.set()

    engine = auth_db.kw["bind"]
    event.listen(engine, "before_cursor_execute", before_update)
    try:
        with ThreadPoolExecutor(max_workers=2) as executor:
            signing_in = executor.submit(login, auth_client)
            assert verifying.wait(10)
            suspending = executor.submit(
                auth_client.patch,
                f"/api/v1/admin/users/{student_id}/status",
                json={"account_status": "suspended", "expected_version": 1},
                headers=operator,
            )
            try:
                assert updating.wait(10)
                with pytest.raises(FutureTimeout):
                    suspending.result(timeout=0.1)
            finally:
                release.set()
            issued = signing_in.result(timeout=10)
            suspended = suspending.result(timeout=10)
        assert issued.status_code == suspended.status_code == 200
        active = auth_client.patch(
            f"/api/v1/admin/users/{student_id}/status",
            json={"account_status": "active", "expected_version": suspended.json()["version"]},
            headers=operator,
        )
        assert active.status_code == 200
        assert auth_client.get("/api/v1/auth/me", headers=authorization(issued)).status_code == 401
    finally:
        release.set()
        event.remove(engine, "before_cursor_execute", before_update)


@pytest.mark.integration
def test_institution_cursor_continues_without_revealing_other_scopes(auth_client, auth_db):
    _, operator = super_admin(auth_client, auth_db)
    for name in ("합성 A", "합성 B", "합성 C"):
        assert (
            auth_client.post(
                "/api/v1/admin/institutions", json={"name": name}, headers=operator
            ).status_code
            == 201
        )
    first = auth_client.get("/api/v1/admin/institutions?limit=2", headers=operator).json()
    second = auth_client.get(
        "/api/v1/admin/institutions",
        params={"limit": 2, "cursor": first["next_cursor"]},
        headers=operator,
    ).json()
    assert len(first["items"]) == 2 and len(second["items"]) == 1
    assert second["next_cursor"] is None
    assert len({r["id"] for r in first["items"] + second["items"]}) == 3
