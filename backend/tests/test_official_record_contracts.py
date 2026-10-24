from decimal import Decimal
from uuid import uuid4

import pytest
from pydantic import TypeAdapter, ValidationError

from app.schemas import official_records as dto


def academic_data():
    return {
        "kind": "academics",
        "page_count": 2,
        "records_as_of": "2026-10-01",
        "coverage": "complete",
        "context": {},
        "records": [
            {
                "client_id": str(uuid4()),
                "source_page": 1,
                "course_id": str(uuid4()),
                "expected_course_version": 1,
                "completion_status": "completed",
                "original_grade": "A+",
            }
        ],
    }


def test_letter_grades_never_imply_numeric_points_or_credits():
    parsed = dto.AcademicData.model_validate(academic_data())
    record = parsed.records[0]
    assert record.original_grade == "A+" and record.grade_points is None
    assert record.grade_scale is None and record.earned_credits is None
    assert parsed.context.department_id is None and parsed.context.track is None


@pytest.mark.parametrize("value", [0, 1760000000, "2026-01-01T00:00:00Z", "2026-1-1"])
def test_reviewed_record_dates_require_explicit_calendar_dates(value):
    with pytest.raises(ValidationError):
        dto.AcademicData.model_validate({**academic_data(), "records_as_of": value})


@pytest.mark.parametrize("grade", [{"grade_points": "4.5"}, {"grade_scale": "GPA-4.5"}])
def test_numeric_grade_requires_its_explicit_comparison_scale(grade):
    data = academic_data()
    data["records"][0].update(grade)
    with pytest.raises(ValidationError):
        dto.AcademicData.model_validate(data)


@pytest.mark.parametrize("amount", ["NaN", "Infinity", "-1", "1000001", "0.1234567"])
def test_numeric_amounts_have_exact_and_bounded_decimal_values(amount):
    data = academic_data()
    data["records"][0]["earned_credits"] = amount
    with pytest.raises(ValidationError):
        dto.AcademicData.model_validate(data)
    data["records"][0]["earned_credits"] = "3.125"
    assert dto.AcademicData.model_validate(data).records[0].earned_credits == Decimal("3.125")


@pytest.mark.parametrize(
    "change", ["duplicate_id", "outside_page", "null_records", "control_label"]
)
def test_provenance_and_collection_state_are_explicit(change):
    data = academic_data()
    if change == "duplicate_id":
        data["records"].append(dict(data["records"][0]))
    elif change == "outside_page":
        data["records"][0]["source_page"] = 3
    elif change == "null_records":
        data["records"] = None
    else:
        data["records"][0]["original_grade"] = "A+\x00"
    with pytest.raises(ValidationError):
        dto.AcademicData.model_validate(data)


def test_four_record_kinds_preserve_unknown_fields_and_known_empty_lists():
    adapter = TypeAdapter(dto.Payload)
    for kind in ["academics", "volunteers", "certificates", "theses"]:
        data = {**academic_data(), "kind": kind, "records": []}
        assert adapter.validate_python(data).records == []
        data["coverage"] = "partial"
        assert adapter.validate_python(data).coverage == "partial"
    volunteer = adapter.validate_python(
        {
            **academic_data(),
            "kind": "volunteers",
            "records": [
                {"client_id": str(uuid4()), "source_page": 1, "approval_status": "pending"}
            ],
        }
    )
    assert volunteer.records[0].approved_hours is None
    certificate = adapter.validate_python(
        {
            **academic_data(),
            "kind": "certificates",
            "records": [
                {
                    "client_id": str(uuid4()),
                    "source_page": 1,
                    "certificate_id": str(uuid4()),
                    "expected_certificate_version": 1,
                    "approval_status": "needs_review",
                }
            ],
        }
    )
    assert certificate.records[0].validity_known is False
    thesis = adapter.validate_python(
        {
            **academic_data(),
            "kind": "theses",
            "records": [
                {
                    "client_id": str(uuid4()),
                    "source_page": 1,
                    "thesis_type": "capstone",
                    "is_completed": None,
                    "approval_status": "needs_review",
                }
            ],
        }
    )
    assert thesis.records[0].is_completed is None


def test_approval_requires_reviewed_content_context_coverage_and_exact_replacement():
    valid = {
        "expected_version": 1,
        "expected_source_sha256": "a" * 64,
        "records_reviewed": True,
        "context_reviewed": True,
        "coverage_reviewed": True,
    }
    dto.BatchApprove.model_validate(valid)
    for change in [
        {"records_reviewed": False},
        {"context_reviewed": 1},
        {"coverage_reviewed": "true"},
        {"replaces_batch_id": str(uuid4())},
        {"expected_replaced_version": 1},
    ]:
        with pytest.raises(ValidationError):
            dto.BatchApprove.model_validate({**valid, **change})
