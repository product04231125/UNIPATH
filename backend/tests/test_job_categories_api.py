"""The category list is public Work24 data, served to signed-in students like the search."""

import pytest
from test_auth import auth_client as auth_client
from test_auth import auth_db as auth_db
from test_auth import authorization, register


def test_category_list_requires_login(client):
    assert client.get("/api/v1/me/job-categories").status_code == 401


@pytest.mark.integration
def test_signed_in_student_gets_the_work24_tree(auth_client):
    owner = authorization(register(auth_client))
    response = auth_client.get("/api/v1/me/job-categories", headers=owner)
    assert response.status_code == 200
    value = response.json()
    assert value["checked_on"] == "2026-11-22"
    assert [c["code"] for c in value["categories"]][:2] == ["01", "02"]
