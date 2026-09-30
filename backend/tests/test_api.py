from uuid import UUID, uuid4

import pytest
from pydantic import BaseModel
from sqlalchemy.exc import OperationalError

from app.api.dependencies import get_session


@pytest.mark.parametrize("path", ["/health", "/api/v1/health"])
def test_liveness_and_request_id(client, path):
    response = client.get(path)
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
    UUID(response.headers["x-request-id"])


def test_request_id_is_propagated_and_invalid_id_is_replaced(client):
    request_id = str(uuid4())
    assert (
        client.get("/health", headers={"X-Request-ID": request_id}).headers["x-request-id"]
        == request_id
    )
    response = client.get("/health", headers={"X-Request-ID": "invalid"})
    UUID(response.headers["x-request-id"])


@pytest.mark.parametrize(
    ("method", "path", "status", "code"),
    [
        ("GET", "/api/v1/missing", 404, "NOT_FOUND"),
        ("POST", "/api/v1/health", 405, "METHOD_NOT_ALLOWED"),
    ],
)
def test_http_errors_have_common_schema(client, method, path, status, code):
    response = client.request(method, path)
    assert response.status_code == status
    error = response.json()["error"]
    assert error["code"] == code
    assert error["field_errors"] == []
    assert error["request_id"] == response.headers["x-request-id"]


class SampleInput(BaseModel):
    credits: int


def test_validation_error_omits_input_values(client):
    @client.app.post("/api/v1/test-validation")
    def validate(payload: SampleInput):
        return payload

    response = client.post("/api/v1/test-validation", json={"credits": "private-input"})
    assert response.status_code == 422
    error = response.json()["error"]
    assert error["code"] == "VALIDATION_ERROR"
    assert error["field_errors"] == [{"field": "body.credits", "reason": "int_parsing"}]
    assert "private-input" not in response.text


def test_internal_error_does_not_expose_details(client, caplog):
    @client.app.get("/api/v1/test-error")
    def fail():
        raise RuntimeError("private-password")

    response = client.get("/api/v1/test-error")
    assert response.status_code == 500
    assert response.json()["error"]["code"] == "INTERNAL_SERVER_ERROR"
    assert "private-password" not in response.text
    assert "private-password" not in caplog.text
    assert response.json()["error"]["request_id"] == response.headers["x-request-id"]


def test_ready_requires_database_and_migration(client):
    class ReadySession:
        def scalar(self, statement):
            return "0.8.6" if "pg_extension" in str(statement) else "0001_enable_pgvector"

    client.app.dependency_overrides[get_session] = lambda: ReadySession()
    response = client.get("/api/v1/health/ready")
    assert response.status_code == 200
    assert response.json() == {
        "status": "ready",
        "database": "ok",
        "pgvector_version": "0.8.6",
        "migration_revision": "0001_enable_pgvector",
    }


@pytest.mark.parametrize("broken_connection", [True, False])
def test_unavailable_database_or_missing_extension_returns_503(client, broken_connection):
    class UnreadySession:
        def scalar(self, statement):
            if broken_connection:
                raise OperationalError("query", {}, Exception("private-db-details"))
            return None

    client.app.dependency_overrides[get_session] = lambda: UnreadySession()
    response = client.get("/api/v1/health/ready")
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "SERVICE_UNAVAILABLE"
    assert "private-db-details" not in response.text


def test_cors_only_allows_configured_origins(client):
    headers = {"Origin": "http://localhost:3000", "Access-Control-Request-Method": "GET"}
    response = client.options("/api/v1/health", headers=headers)
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "http://localhost:3000"
    headers["Origin"] = "https://untrusted.example"
    response = client.options("/api/v1/health", headers=headers)
    assert response.status_code == 400
    assert "access-control-allow-origin" not in response.headers


def test_openapi_contract(client):
    schema = client.get("/api/v1/openapi.json").json()
    assert set(schema["paths"]) == {"/api/v1/health", "/api/v1/health/ready"}
    assert "503" in schema["paths"]["/api/v1/health/ready"]["get"]["responses"]
    assert "ErrorResponse" in schema["components"]["schemas"]
