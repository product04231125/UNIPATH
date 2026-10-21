from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.schemas.graduation import CatalogReviewCreate, GraduationAuditCreate


def context():
    return {
        "institution_id": str(uuid4()),
        "department_id": str(uuid4()),
        "curriculum_id": str(uuid4()),
        "admission_year": 2026,
        "track": "single_major",
    }


@pytest.mark.parametrize("value", [False, 1, "true", None])
def test_catalogue_attestation_requires_real_explicit_true_flags(value):
    payload = {
        "context": context(),
        "as_of": "2026-10-21",
        "client_id": str(uuid4()),
        "expected_catalog_digest": "a" * 64,
        "all_requirements_reviewed": True,
        "all_levels_reviewed": True,
        "sources_reviewed": True,
        "review_note": "합성 검토",
    }
    for flag in ("all_requirements_reviewed", "all_levels_reviewed", "sources_reviewed"):
        with pytest.raises(ValidationError):
            CatalogReviewCreate.model_validate({**payload, flag: value})


@pytest.mark.parametrize("as_of", [0, 1760000000, "2026-10-21T00:00:00Z", "2026-1-1"])
def test_audit_calendar_date_does_not_accept_implicit_timezone_or_numeric_dates(as_of):
    with pytest.raises(ValidationError):
        GraduationAuditCreate.model_validate(
            {"context": context(), "as_of": as_of, "client_id": str(uuid4())}
        )


def test_audit_context_and_replacement_require_explicit_complete_fields():
    base = {"context": context(), "as_of": "2026-10-21", "client_id": str(uuid4())}
    for key in base["context"]:
        partial = {k: v for k, v in base["context"].items() if k != key}
        with pytest.raises(ValidationError):
            GraduationAuditCreate.model_validate({**base, "context": partial})
    review = {
        **base,
        "expected_catalog_digest": "a" * 64,
        "all_requirements_reviewed": True,
        "all_levels_reviewed": True,
        "sources_reviewed": True,
        "review_note": "합성 검토",
    }
    with pytest.raises(ValidationError):
        CatalogReviewCreate.model_validate({**review, "replaces_review_id": str(uuid4())})
    with pytest.raises(ValidationError):
        CatalogReviewCreate.model_validate({**review, "review_note": "합성\x00검토"})
