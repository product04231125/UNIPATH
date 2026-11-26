import pytest

from app.services.academic import audit_kind


@pytest.mark.parametrize(
    ("action", "expected"),
    [
        ("academic:classification_create", "classification"),
        ("academic:classification_replace", "classification"),
        ("academic:track_update", "studyTrack"),
        ("academic:curriculum_course_add", "curriculum"),
        ("academic:requirement_replace", "rule"),
        ("academic:course:update", "course"),
        ("local_pdf_import:track", "studyTrack"),
        ("local_pdf_import:requirement", "rule"),
        ("scope_granted", "scope"),
        ("institution_created", "institution"),
        ("role_changed", "account"),
        ("academic:future_operation", "future_operation"),
    ],
)
def test_audit_entity_kind_is_separate_from_operation(action, expected):
    assert audit_kind(action) == expected
