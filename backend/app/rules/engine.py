"""Pure, deterministic evaluation. Callers own authorization and data provenance."""

from collections import Counter, defaultdict
from datetime import date
from decimal import Context, Decimal, localcontext
from functools import wraps
from uuid import UUID

from app.rules.contracts import (
    AcademicContext,
    AppliedVersion,
    Approval,
    CertificateRule,
    Completion,
    CourseRequirement,
    CourseRule,
    CreditRule,
    Evaluation,
    Origin,
    ReviewRule,
    Rule,
    RuleResult,
    RuleSet,
    Snapshot,
    Status,
    ThesisRule,
    VolunteerRule,
)

ZERO = Decimal(0)


def _decimal_context(function):
    @wraps(function)
    def calculate(*args, **kwargs):
        # Exact within validated input precision; independent of caller/thread
        # decimal settings. No process-global arithmetic context is mutated.
        with localcontext(Context(prec=50)):
            return function(*args, **kwargs)

    return calculate


def _active(rule_set: RuleSet, as_of: date) -> bool:
    return (
        rule_set.is_active
        and (rule_set.effective_from is None or as_of >= rule_set.effective_from)
        and (rule_set.effective_to is None or as_of <= rule_set.effective_to)
    )


def _threshold(current: Decimal, minimum: Decimal, unknown: bool, evidence: tuple) -> dict:
    if current >= minimum:
        status, reason = Status.SATISFIED, "threshold_met"
    elif unknown:
        status, reason = Status.NEEDS_REVIEW, "incomplete_record_data"
    else:
        status, reason = Status.NOT_SATISFIED, "below_threshold"
    return {
        "status": status,
        "reason": reason,
        "current": current,
        "required": minimum,
        "deficit": None if status == Status.NEEDS_REVIEW else max(ZERO, minimum - current),
        "evidence_record_ids": evidence,
    }


def _credits(rule: CreditRule, snapshot: Snapshot) -> dict:
    if snapshot.academics is None:
        return {"status": Status.NEEDS_REVIEW, "reason": "academic_records_unavailable"}
    passed = [r for r in snapshot.academics if r.completion_status == Completion.COMPLETED]
    counts = Counter(record.course_id for record in passed)
    total, unknown, evidence = ZERO, False, []
    for record in snapshot.academics:
        if rule.category is not None and record.category not in (None, rule.category):
            continue
        if record.completion_status == Completion.NEEDS_REVIEW:
            unknown = True
        if record.completion_status != Completion.COMPLETED:
            continue
        # Retake/duplicate-credit policy belongs to the school adapter. Exclude
        # ambiguous records rather than inventing a policy or counting twice.
        if counts[record.course_id] > 1 or record.earned_credits is None:
            unknown = True
            continue
        if rule.category is not None and record.category is None:
            unknown = True
            continue
        total += record.earned_credits
        evidence.append(record.id)
    return _threshold(total, rule.minimum, unknown, tuple(evidence))


def _course(requirement: CourseRequirement, snapshot: Snapshot) -> tuple[Status, tuple]:
    records = [r for r in snapshot.academics or () if r.course_id == requirement.course_id]
    unknown = snapshot.academics is None
    for record in records:
        if record.completion_status == Completion.NEEDS_REVIEW:
            unknown = True
        if record.completion_status != Completion.COMPLETED:
            continue
        credit_unknown = requirement.minimum_credits is not None and record.earned_credits is None
        grade_unknown = requirement.minimum_grade_points is not None and (
            record.grade_points is None or record.grade_scale != requirement.comparison_grade_scale
        )
        if credit_unknown or grade_unknown:
            unknown = True
            continue
        if (
            requirement.minimum_credits is not None
            and record.earned_credits < requirement.minimum_credits
        ):
            continue
        if (
            requirement.minimum_grade_points is not None
            and record.grade_points < requirement.minimum_grade_points
        ):
            continue
        return Status.SATISFIED, (record.id,)
    return (Status.NEEDS_REVIEW if unknown else Status.NOT_SATISFIED), ()


def _courses(rule: CourseRule, snapshot: Snapshot) -> dict:
    missing, uncertain, evidence = [], [], []
    for course in rule.courses:
        status, record_ids = _course(course, snapshot)
        evidence.extend(record_ids)
        if status == Status.NEEDS_REVIEW:
            uncertain.append(course.course_id)
        elif status == Status.NOT_SATISFIED:
            missing.append(course.course_id)
    status = (
        Status.NOT_SATISFIED if missing else Status.NEEDS_REVIEW if uncertain else Status.SATISFIED
    )
    return {
        "status": status,
        "reason": "missing_required_courses"
        if missing
        else ("course_data_needs_review" if uncertain else "required_courses_met"),
        "current": Decimal(len(rule.courses) - len(missing) - len(uncertain)),
        "required": Decimal(len(rule.courses)),
        "deficit": None if uncertain else Decimal(len(missing)),
        "missing_course_ids": tuple(missing),
        "uncertain_course_ids": tuple(uncertain),
        "evidence_record_ids": tuple(evidence),
    }


def _volunteers(rule: VolunteerRule, snapshot: Snapshot) -> dict:
    if snapshot.volunteers is None:
        return {"status": Status.NEEDS_REVIEW, "reason": "volunteer_records_unavailable"}
    total, unknown, evidence = ZERO, False, []
    for record in snapshot.volunteers:
        if record.approval_status in (Approval.PENDING, Approval.NEEDS_REVIEW):
            unknown = True
        if record.approval_status != Approval.APPROVED:
            continue
        if record.approved_hours is None:
            unknown = True
            continue
        total += record.approved_hours
        evidence.append(record.id)
    return _threshold(total, rule.minimum, unknown, tuple(evidence))


def _certificates(rule: CertificateRule, snapshot: Snapshot, as_of: date) -> dict:
    unknown = snapshot.certificates is None
    for record in snapshot.certificates or ():
        if record.certificate_id not in rule.certificate_ids:
            continue
        if record.approval_status in (Approval.PENDING, Approval.NEEDS_REVIEW):
            unknown = True
        if record.approval_status != Approval.APPROVED:
            continue
        if not record.validity_known:
            unknown = True
            continue
        if record.expires_on is None or record.expires_on >= as_of:
            return _threshold(Decimal(1), Decimal(1), False, (record.id,))
    return _threshold(ZERO, Decimal(1), unknown, ())


def _thesis(rule: ThesisRule, snapshot: Snapshot) -> dict:
    unknown = snapshot.theses is None
    for record in snapshot.theses or ():
        if record.thesis_type != rule.thesis_type:
            continue
        if not record.is_completed:
            unknown |= record.approval_status in (Approval.APPROVED, Approval.NEEDS_REVIEW)
            continue
        if rule.requires_approval:
            if record.approval_status in (Approval.PENDING, Approval.NEEDS_REVIEW):
                unknown = True
            if record.approval_status != Approval.APPROVED:
                continue
        if rule.accepted_grades and record.grade is None:
            unknown = True
            continue
        if rule.accepted_grades and record.grade not in rule.accepted_grades:
            continue
        return _threshold(Decimal(1), Decimal(1), False, (record.id,))
    return _threshold(ZERO, Decimal(1), unknown, ())


def _evaluate_rule(rule: Rule, rule_set: RuleSet, snapshot: Snapshot, as_of: date) -> RuleResult:
    match rule:
        case CreditRule():
            values = _credits(rule, snapshot)
        case CourseRule():
            values = _courses(rule, snapshot)
        case VolunteerRule():
            values = _volunteers(rule, snapshot)
        case CertificateRule():
            values = _certificates(rule, snapshot, as_of)
        case ThesisRule():
            values = _thesis(rule, snapshot)
        case ReviewRule():
            values = {"status": Status.NEEDS_REVIEW, "reason": rule.reason}
        case _:
            raise TypeError("Unsupported rule type")
    return RuleResult(
        rule_set_id=rule_set.id,
        rule_set_version=rule_set.version,
        rule_id=rule.id,
        rule_code=rule.code,
        title=rule.title,
        **values,
    )


def _finish(
    selected: tuple[RuleSet, ...],
    snapshot: Snapshot,
    as_of: date,
    *,
    official: bool,
    missing: tuple[str, ...] = (),
    forced_reason: str | None = None,
    snapshots: dict[UUID, Snapshot] | None = None,
) -> Evaluation:
    results = tuple(
        _evaluate_rule(r, s, snapshots[s.id] if snapshots is not None else snapshot, as_of)
        for s in selected
        for r in s.rules
    )
    if forced_reason:
        status, reason = Status.NEEDS_REVIEW, forced_reason
    elif not results:
        status, reason = Status.NOT_APPLICABLE, "no_applicable_rules"
    elif any(r.status == Status.NOT_SATISFIED for r in results):
        status, reason = Status.NOT_SATISFIED, "requirements_not_met"
    elif any(r.status == Status.NEEDS_REVIEW for r in results):
        status, reason = Status.NEEDS_REVIEW, "record_data_needs_review"
    else:
        status, reason = Status.SATISFIED, "all_requirements_met"
    return Evaluation(
        status=status,
        official=official,
        label="공식 규칙 계산" if official else "개인 기준 계산 · 학교 공식 판정 아님",
        reason=reason,
        evaluated_on=as_of,
        results=results,
        missing_fields=missing,
        applied_versions=tuple(
            AppliedVersion(
                rule_set_id=s.id,
                version=s.version,
                scope_type=s.scope.scope_type if s.scope else None,
                evidence=s.evidence,
            )
            for s in selected
        ),
    )


def _distinct(selected: tuple[RuleSet, ...]) -> bool:
    rules = [rule.id for rule_set in selected for rule in rule_set.rules]
    return len(set(rules)) == len(rules) and len({s.id for s in selected}) == len(selected)


@_decimal_context
def evaluate_personal(
    rule_sets: tuple[RuleSet, ...],
    snapshot: Snapshot,
    *,
    as_of: date,
) -> Evaluation:
    """The caller must supply only the current user's own personal rules."""
    if any(s.origin != Origin.PERSONAL for s in rule_sets):
        raise ValueError("Personal evaluation cannot accept official rule sets")
    selected = tuple(s for s in rule_sets if _active(s, as_of))
    if not _distinct(selected):
        return _finish(
            (), snapshot, as_of, official=False, forced_reason="ambiguous_rule_identifiers"
        )
    return _finish(selected, snapshot, as_of, official=False)


@_decimal_context
def evaluate_personal_sources(
    cases: tuple[tuple[RuleSet, Snapshot], ...],
    *,
    as_of: date,
) -> Evaluation:
    """Personal criteria may select different owned records for each requirement.

    Authorization, ownership and source observations belong to the API adapter.
    The same deterministic rules and aggregate status policy apply to every case.
    """
    if any(rule_set.origin != Origin.PERSONAL for rule_set, _ in cases):
        raise ValueError("Personal evaluation cannot accept official rule sets")
    selected = tuple(rule_set for rule_set, _ in cases if _active(rule_set, as_of))
    if not _distinct(selected):
        return _finish(
            (), Snapshot(), as_of, official=False, forced_reason="ambiguous_rule_identifiers"
        )
    snapshots = {rule_set.id: snapshot for rule_set, snapshot in cases}
    return _finish(selected, Snapshot(), as_of, official=False, snapshots=snapshots)


@_decimal_context
def evaluate_official(
    rule_sets: tuple[RuleSet, ...],
    snapshot: Snapshot,
    context: AcademicContext,
    *,
    as_of: date,
    catalog_complete: bool = False,
) -> Evaluation:
    """Internal only: a future authorized DB adapter supplies approved, complete rules."""
    selected, missing = [], set()
    for rule_set in rule_sets:
        if (
            rule_set.origin != Origin.OFFICIAL
            or rule_set.approval_status != Approval.APPROVED
            or not _active(rule_set, as_of)
        ):
            continue
        scope = rule_set.scope
        required = {
            k: getattr(scope, k)
            for k in (
                "institution_id",
                "department_id",
                "curriculum_id",
                "track",
            )
            if getattr(scope, k) is not None
        }
        # A known mismatch excludes the rule even if another context field is missing.
        if any(
            getattr(context, k) is not None and getattr(context, k) != v
            for k, v in required.items()
        ):
            continue
        absent = {k for k in required if getattr(context, k) is None}
        if scope.admission_year_from is not None:
            if context.admission_year is None:
                absent.add("admission_year")
            elif not scope.admission_year_from <= context.admission_year <= scope.admission_year_to:
                continue
        if absent:
            missing.update(absent)
        else:
            selected.append(rule_set)
    groups = defaultdict(list)
    for rule_set in selected:
        scope = rule_set.scope
        groups[
            (
                scope.scope_type,
                scope.institution_id,
                scope.department_id,
                scope.curriculum_id,
                rule_set.code,
            )
        ].append(rule_set)
    ambiguous = any(len(group) > 1 for group in groups.values())
    selected = tuple(s for group in groups.values() if len(group) == 1 for s in group)
    forced = (
        "ambiguous_rule_set_versions"
        if ambiguous
        else "ambiguous_rule_identifiers"
        if not _distinct(selected)
        else "academic_scope_required"
        if missing
        else "catalog_completeness_unconfirmed"
        if selected and catalog_complete is not True
        else None
    )
    if forced == "ambiguous_rule_identifiers":
        selected = ()
    return _finish(
        selected,
        snapshot,
        as_of,
        official=True,
        missing=tuple(sorted(missing)),
        forced_reason=forced,
    )
