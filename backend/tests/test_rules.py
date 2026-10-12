import sys
from datetime import date, timedelta
from decimal import Decimal, localcontext
from uuid import UUID

import pytest
from pydantic import ValidationError

from app.rules.__main__ import PersonalInput, demo, main
from app.rules.contracts import AcademicContext, RuleSet, Snapshot, Status
from app.rules.engine import evaluate_official, evaluate_personal

TODAY = date(2026, 10, 12)


def uid(n):
    return str(UUID(int=n))


def personal(kind="minimum_credits", **values):
    return RuleSet.model_validate(
        {
            "id": uid(100),
            "code": "synthetic_personal",
            "version": 1,
            "origin": "personal",
            "rules": [
                {
                    "id": uid(101),
                    "code": "synthetic_rule",
                    "title": "합성 기준",
                    "kind": kind,
                    **values,
                }
            ],
        }
    )


def academic(n=1, **values):
    return {
        "id": uid(n),
        "course_id": uid(n + 10),
        "completion_status": "completed",
        "earned_credits": "3",
        **values,
    }


def evaluate(rule_set, **snapshot):
    return evaluate_personal((rule_set,), Snapshot.model_validate(snapshot), as_of=TODAY)


@pytest.mark.parametrize(
    "records,status,current",
    [
        (None, Status.NEEDS_REVIEW, None),
        ([], Status.NOT_SATISFIED, Decimal(0)),
        ([academic(earned_credits="0.29")], Status.NOT_SATISFIED, Decimal("0.29")),
        ([academic(earned_credits="0.3")], Status.SATISFIED, Decimal("0.3")),
        (
            [academic(1, earned_credits="0.1"), academic(2, earned_credits="0.2")],
            Status.SATISFIED,
            Decimal("0.3"),
        ),
        ([academic(completion_status="failed")], Status.NOT_SATISFIED, Decimal(0)),
        ([academic(completion_status="in_progress")], Status.NOT_SATISFIED, Decimal(0)),
        ([academic(earned_credits=None)], Status.NEEDS_REVIEW, Decimal(0)),
        ([academic(completion_status="needs_review")], Status.NEEDS_REVIEW, Decimal(0)),
    ],
)
def test_credit_boundaries_and_unavailable_records(records, status, current):
    result = evaluate(personal(minimum="0.3"), academics=records)
    assert result.status == status
    assert result.results[0].current == current
    assert result.official is False
    assert result.label == "개인 기준 계산 · 학교 공식 판정 아님"
    if status == Status.NEEDS_REVIEW:
        assert result.results[0].deficit is None


def test_categories_and_ambiguous_repeated_courses_never_double_count():
    rule = personal(minimum="6", category="major")
    repeated = [academic(1, category="major"), academic(2, course_id=uid(11), category="major")]
    result = evaluate(rule, academics=repeated)
    assert result.status == Status.NEEDS_REVIEW
    assert result.results[0].current == 0
    assert evaluate(rule, academics=[academic(category=None)]).status == Status.NEEDS_REVIEW
    assert evaluate(rule, academics=[academic(category="general")]).status == Status.NOT_SATISFIED
    proven = evaluate(
        rule, academics=[*repeated, academic(3, category="major", earned_credits="6")]
    )
    assert proven.status == Status.SATISFIED
    assert proven.results[0].evidence_record_ids == (UUID(int=3),)


@pytest.mark.parametrize(
    "points,scale,status",
    [
        ("3.0", "4.5", Status.SATISFIED),
        ("2.99", "4.5", Status.NOT_SATISFIED),
        (None, "4.5", Status.NEEDS_REVIEW),
        ("97", "100", Status.NEEDS_REVIEW),
    ],
)
def test_required_course_grades_only_compare_explicit_matching_scales(points, scale, status):
    rule = personal(
        "required_courses",
        courses=[
            {
                "course_id": uid(11),
                "minimum_credits": "3",
                "minimum_grade_points": "3",
                "comparison_grade_scale": "4.5",
            }
        ],
    )
    result = evaluate(rule, academics=[academic(grade_points=points, grade_scale=scale)])
    assert result.status == status
    assert evaluate(rule, academics=None).status == Status.NEEDS_REVIEW
    missing = evaluate(rule, academics=[])
    assert missing.status == Status.NOT_SATISFIED
    assert missing.results[0].missing_course_ids == (UUID(int=11),)


@pytest.mark.parametrize(
    "approval,hours,status",
    [
        ("approved", "24", Status.SATISFIED),
        ("approved", "23.99", Status.NOT_SATISFIED),
        ("approved", None, Status.NEEDS_REVIEW),
        ("pending", "100", Status.NEEDS_REVIEW),
        ("needs_review", "100", Status.NEEDS_REVIEW),
        ("rejected", "100", Status.NOT_SATISFIED),
    ],
)
def test_volunteer_counts_only_approved_hours(approval, hours, status):
    result = evaluate(
        personal("minimum_volunteer_hours", minimum="24"),
        volunteers=[
            {
                "id": uid(1),
                "approval_status": approval,
                "approved_hours": hours,
            }
        ],
    )
    assert result.status == status
    if approval != "approved":
        assert result.results[0].current == 0


@pytest.mark.parametrize(
    "expires,known,status",
    [
        (TODAY, True, Status.SATISFIED),
        (TODAY - timedelta(days=1), True, Status.NOT_SATISFIED),
        (None, True, Status.SATISFIED),
        (None, False, Status.NEEDS_REVIEW),
    ],
)
def test_certificate_alternatives_and_validity_boundary(expires, known, status):
    rule = personal("any_certificate", certificate_ids=[uid(30), uid(31)])
    result = evaluate(
        rule,
        certificates=[
            {
                "id": uid(1),
                "certificate_id": uid(31),
                "approval_status": "approved",
                "expires_on": expires,
                "validity_known": known,
            }
        ],
    )
    assert result.status == status
    assert evaluate(rule, certificates=None).status == Status.NEEDS_REVIEW


@pytest.mark.parametrize(
    "approval,grade,status",
    [
        ("approved", "pass", Status.SATISFIED),
        ("approved", "fail", Status.NOT_SATISFIED),
        ("approved", None, Status.NEEDS_REVIEW),
        ("pending", "pass", Status.NEEDS_REVIEW),
        ("rejected", "pass", Status.NOT_SATISFIED),
    ],
)
def test_thesis_uses_explicit_approval_and_grade_policy(approval, grade, status):
    rule = personal("thesis", thesis_type="capstone", accepted_grades=["pass"])
    result = evaluate(
        rule,
        theses=[
            {
                "id": uid(1),
                "thesis_type": "capstone",
                "approval_status": approval,
                "is_completed": True,
                "grade": grade,
            }
        ],
    )
    assert result.status == status
    assert evaluate(rule, theses=None).status == Status.NEEDS_REVIEW


def official(n, scope_type="institution", **updates):
    scope = {"scope_type": scope_type, "institution_id": uid(1)}
    if scope_type in ("department", "curriculum"):
        scope["department_id"] = uid(2)
    if scope_type == "curriculum":
        scope["curriculum_id"] = uid(3)
    return RuleSet.model_validate(
        {
            "id": uid(200 + n),
            "code": f"synthetic_{n}",
            "version": 1,
            "origin": "official",
            "scope": scope,
            "approval_status": "approved",
            "rules": [
                {
                    "id": uid(300 + n),
                    "kind": "minimum_credits",
                    "code": f"credits_{n}",
                    "title": "합성 규칙 · 실제 학교 기준 아님",
                    "minimum": "6",
                }
            ],
            "evidence": [
                {
                    "document_id": uid(400 + n),
                    "title": "합성 문서",
                    "source_url": "https://rules.example.invalid/synthetic",
                    "page": 1,
                }
            ],
            **updates,
        }
    )


CONTEXT = AcademicContext(
    institution_id=uid(1),
    department_id=uid(2),
    curriculum_id=uid(3),
    admission_year=2026,
    track="single_major",
)


def test_official_combines_school_department_curriculum_and_records_versions():
    sets = tuple(
        official(n, scope)
        for n, scope in enumerate(
            ("institution", "department", "curriculum"),
            1,
        )
    )
    snapshot = Snapshot.model_validate({"academics": [academic(earned_credits="6")]})
    result = evaluate_official(sets, snapshot, CONTEXT, as_of=TODAY, catalog_complete=True)
    assert result.status == Status.SATISFIED
    assert len(result.results) == len(result.applied_versions) == 3
    assert result.applied_versions[2].version == 1
    assert result.applied_versions[2].evidence == sets[2].evidence
    assert evaluate_official(sets, snapshot, CONTEXT, as_of=TODAY).status == Status.NEEDS_REVIEW
    stricter = sets[2].model_copy(
        update={
            "rules": (
                sets[2]
                .rules[0]
                .model_copy(
                    update={"minimum": Decimal("7")},
                ),
            )
        }
    )
    failing = evaluate_official(
        (*sets[:2], stricter), snapshot, CONTEXT, as_of=TODAY, catalog_complete=True
    )
    assert failing.status == Status.NOT_SATISFIED
    assert failing.results[-1].deficit == 1


def test_scope_filters_cohort_track_dates_and_preserves_missing_context():
    scoped = official(
        1,
        scope={
            "scope_type": "institution",
            "institution_id": uid(1),
            "admission_year_from": 2024,
            "admission_year_to": 2026,
            "track": "single_major",
        },
        effective_from=TODAY,
        effective_to=TODAY,
    )
    snapshot = Snapshot(academics=())
    kwargs = {"as_of": TODAY, "catalog_complete": True}
    assert evaluate_official((scoped,), snapshot, CONTEXT, **kwargs).status == Status.NOT_SATISFIED
    for context in [
        CONTEXT.model_copy(update={"admission_year": 2027}),
        CONTEXT.model_copy(update={"track": "double_major"}),
        CONTEXT.model_copy(update={"institution_id": UUID(int=999)}),
    ]:
        assert (
            evaluate_official((scoped,), snapshot, context, **kwargs).status
            == Status.NOT_APPLICABLE
        )
    incomplete = CONTEXT.model_copy(update={"admission_year": None})
    result = evaluate_official((scoped,), snapshot, incomplete, **kwargs)
    assert result.status == Status.NEEDS_REVIEW
    assert result.missing_fields == ("admission_year",)
    assert (
        evaluate_official(
            (scoped,), snapshot, CONTEXT, as_of=TODAY + timedelta(days=1), catalog_complete=True
        ).status
        == Status.NOT_APPLICABLE
    )


def test_unapproved_rules_personal_rules_and_ambiguous_versions_never_produce_official_pass():
    snapshot = Snapshot.model_validate({"academics": [academic(earned_credits="100")]})
    approved = official(1)
    unapproved = official(2, approval_status="pending")
    result = evaluate_official(
        (unapproved, personal(minimum="1")), snapshot, CONTEXT, as_of=TODAY, catalog_complete=True
    )
    assert result.status == Status.NOT_APPLICABLE
    overlap = official(9, code=approved.code, version=2)
    result = evaluate_official(
        (approved, overlap), snapshot, CONTEXT, as_of=TODAY, catalog_complete=True
    )
    assert result.status == Status.NEEDS_REVIEW
    assert result.reason == "ambiguous_rule_set_versions"
    assert not result.applied_versions
    with pytest.raises(ValueError):
        evaluate_personal((approved,), snapshot, as_of=TODAY)


@pytest.mark.parametrize("minimum", ["-1", "NaN", "Infinity", "-Infinity"])
def test_invalid_amounts_are_rejected(minimum):
    with pytest.raises(ValidationError):
        personal(minimum=minimum)


def test_duplicate_records_scopes_unknown_kinds_and_missing_grade_policies_rejected():
    with pytest.raises(ValidationError):
        Snapshot.model_validate({"academics": [academic(), academic()]})
    with pytest.raises(ValidationError):
        official(1, evidence=[])
    with pytest.raises(ValidationError):
        official(
            1,
            scope={"scope_type": "institution", "institution_id": uid(1), "department_id": uid(2)},
        )
    with pytest.raises(ValidationError):
        personal("execute_expression", expression="arbitrary expression")
    with pytest.raises(ValidationError):
        personal("required_courses", courses=[{"course_id": uid(1), "minimum_grade_points": "3"}])


def test_repeatability_input_immutability_and_json_contract():
    data = demo()
    before = data.model_dump_json()
    first = evaluate_personal(data.rule_sets, data.snapshot, as_of=data.evaluated_on)
    assert first == evaluate_personal(data.rule_sets, data.snapshot, as_of=data.evaluated_on)
    assert first.results[0].current == Decimal("3")
    assert data.model_dump_json() == before
    assert PersonalInput.model_validate_json(before) == data


def test_calculations_ignore_callers_decimal_precision_and_do_not_change_it():
    rule = personal(minimum="130.24")
    snapshot = Snapshot.model_validate(
        {
            "academics": [
                academic(1, earned_credits="123.45"),
                academic(2, earned_credits="6.78"),
            ]
        }
    )
    with localcontext() as context:
        context.prec = 2
        result = evaluate_personal((rule,), snapshot, as_of=TODAY)
        assert result.status == Status.NOT_SATISFIED
        assert result.results[0].current == Decimal("130.23")
        assert result.results[0].deficit == Decimal("0.01")
        assert context.prec == 2


def test_input_precision_empty_names_and_boolean_years_are_rejected():
    with pytest.raises(ValidationError):
        personal(minimum="0.0000001")
    with pytest.raises(ValidationError):
        personal(minimum="6", title=" ")
    with pytest.raises(ValidationError):
        AcademicContext(admission_year=True)


def test_string_false_cannot_confirm_official_catalog():
    snapshot = Snapshot.model_validate({"academics": [academic(earned_credits="100")]})
    result = evaluate_official(
        (official(1),), snapshot, CONTEXT, as_of=TODAY, catalog_complete="false"
    )
    assert result.status == Status.NEEDS_REVIEW


def test_cli_outputs_personal_result_and_rejects_official_input(tmp_path, monkeypatch, capsys):
    file = tmp_path / "synthetic.json"
    file.write_text(demo().model_dump_json())
    monkeypatch.setattr(sys, "argv", ["rules", "--input", str(file)])
    main()
    assert '"official": false' in capsys.readouterr().out
    payload = PersonalInput(rule_sets=(official(1),), snapshot=Snapshot(), evaluated_on=TODAY)
    file.write_text(payload.model_dump_json())
    with pytest.raises(SystemExit) as error:
        main()
    assert error.value.code == 2
    captured = capsys.readouterr()
    assert not captured.out
    assert captured.err.strip() == '{"error":"invalid_personal_input"}'


def test_cli_validation_errors_never_echo_input_values(tmp_path, monkeypatch, capsys):
    payload = demo().model_dump(mode="json")
    payload["rule_sets"][0]["rules"][0]["minimum"] = "PRIVATE_SYNTHETIC_MARKER"
    import json

    file = tmp_path / "synthetic.json"
    file.write_text(json.dumps(payload))
    monkeypatch.setattr(sys, "argv", ["rules", "--input", str(file)])
    with pytest.raises(SystemExit):
        main()
    captured = capsys.readouterr()
    assert "PRIVATE_SYNTHETIC_MARKER" not in captured.err + captured.out
    assert "invalid_input" in captured.err
