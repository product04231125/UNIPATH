"""Adapt owned saved inputs to the pure personal engine and retain immutable results."""

import hashlib
import json
from datetime import UTC, datetime

from pydantic import ValidationError
from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import defer, load_only

from app.core.auth_errors import AuthError, conflict
from app.models.evaluations import PersonalEvaluation
from app.models.personal import (
    PersonalCreationReceipt,
    PersonalCurriculum,
    PersonalCurriculumCourse,
    PersonalGraduationRule,
)
from app.rules import contracts as rules
from app.rules.engine import evaluate_personal_sources
from app.schemas import evaluations as dto
from app.schemas.common import ErrorCode
from app.services import auth, personal
from app.services.access import locked_identity

RESOURCE = "personal-evaluations"
SOURCE_LIMIT = 500
REFERENCE_LIMIT = 2000


def invalid(message="계산할 개인 자료와 선택 조건을 확인해 주세요."):
    return AuthError(422, ErrorCode.VALIDATION_ERROR, message)


class Inputs:
    def __init__(self, db, owner_id, curriculum, request):
        self.db, self.owner_id, self.curriculum = db, owner_id, curriculum
        self.rows = {}
        self.versions = {}
        self.evidence = {kind: {} for kind in ("academics", "volunteers", "certificates", "theses")}
        self.source_links = 0
        self.grades = {}
        all_links, link_ids, course_ids = False, set(), set()
        for calculation in request.calculations:
            condition = calculation.condition
            if isinstance(condition, dto.CourseCondition):
                self.grades.update({g.course_record_id: g for g in condition.grades})
                link_ids.update(c.curriculum_course_id for c in condition.courses)
            elif isinstance(condition, dto.CreditCondition):
                all_links |= condition.course_record_ids is None
                course_ids.update(condition.course_record_ids or [])
        statement = select(PersonalCurriculumCourse).where(
            PersonalCurriculumCourse.owner_id == owner_id,
            PersonalCurriculumCourse.curriculum_id == curriculum.id,
        )
        if not all_links:
            statement = statement.where(
                or_(
                    PersonalCurriculumCourse.id.in_(link_ids),
                    PersonalCurriculumCourse.course_record_id.in_(course_ids),
                )
            )
        self.links = list(
            db.scalars(statement.order_by(PersonalCurriculumCourse.id).limit(SOURCE_LIMIT + 1))
        )
        if len(self.links) > SOURCE_LIMIT:
            raise invalid("개인 교육과정 과목을 500개 이내로 선택해 주세요.")
        self.by_link = {item.id: item for item in self.links}
        self.linked_records = {
            item.course_record_id for item in self.links if item.course_record_id
        }
        self.cache("personal-curricula", [curriculum])
        self.use("personal-curricula", curriculum)
        self.cache("personal-curriculum-courses", self.links)

    def cache(self, kind, rows):
        for row in rows:
            self.rows[kind, row.id] = row

    def load(self, kind, identifiers):
        identifiers = set(identifiers)
        missing = identifiers - {key[1] for key in self.rows if key[0] == kind}
        if missing:
            model = personal.RESOURCES[kind][0]
            found = list(
                self.db.scalars(
                    select(model).where(model.owner_id == self.owner_id, model.id.in_(missing))
                )
            )
            if {row.id for row in found} != missing:
                raise personal.missing()
            self.cache(kind, found)
        return [self.rows[kind, identifier] for identifier in sorted(identifiers)]

    def use(self, kind, row):
        self.versions[kind, row.id] = dto.SourceVersion(
            kind=kind, record_id=row.id, version=row.version
        )
        if len(self.versions) > REFERENCE_LIMIT:
            raise invalid("한 번에 사용하는 개인 자료 참조를 2000개 이내로 선택해 주세요.")

    def pin(self, versions):
        for kind in {item.kind for item in versions}:
            self.load(kind, [item.record_id for item in versions if item.kind == kind])
        for item in versions:
            if self.rows[item.kind, item.record_id].version != item.version:
                raise conflict()

    def academic(self, row):
        self.use("course-records", row)
        grade = self.grades.get(row.id)
        return rules.AcademicRecord(
            id=row.id,
            course_id=row.id,
            completion_status="completed" if row.completion == "recorded" else "in_progress",
            earned_credits=row.credits if row.completion == "recorded" else None,
            category=row.category,
            grade_points=grade.points if grade else None,
            grade_scale=grade.scale if grade else None,
        )

    def add_evidence(self, snapshot):
        links = {}
        for kind in self.evidence:
            values = getattr(snapshot, kind)
            if values is not None:
                links[kind] = [str(record.id) for record in values]
                self.source_links += len(values)
                for record in values:
                    self.evidence[kind][str(record.id)] = record.model_dump(mode="json")
        if self.source_links > REFERENCE_LIMIT:
            raise invalid("요건별 자료 연결을 합쳐 2000개 이내로 선택해 주세요.")
        return links


def calculate_case(inputs, saved, condition, on):
    base = {"id": saved.id, "code": "personal_" + saved.id.hex, "title": saved.title}
    aliases = {}
    if condition is None:
        return rules.ReviewRule(**base), rules.Snapshot(), aliases
    match condition:
        case dto.CreditCondition():
            identifiers = (
                inputs.linked_records
                if condition.course_record_ids is None
                else set(condition.course_record_ids)
            )
            if not identifiers <= inputs.linked_records:
                raise personal.missing()
            rows = inputs.load("course-records", identifiers)
            if condition.category is not None:
                rows = [row for row in rows if row.category == condition.category]
            selected = {row.id for row in rows}
            for link in inputs.links:
                if link.course_record_id in selected:
                    inputs.use("personal-curriculum-courses", link)
            return (
                rules.CreditRule(**base, minimum=condition.minimum, category=condition.category),
                rules.Snapshot(academics=tuple(inputs.academic(row) for row in rows)),
                aliases,
            )
        case dto.CourseCondition():
            choices = []
            identifiers = []
            for choice in condition.courses:
                link = inputs.by_link.get(choice.curriculum_course_id)
                if link is None:
                    raise personal.missing()
                inputs.use("personal-curriculum-courses", link)
                key = link.course_record_id or link.id
                aliases[key] = link.id
                identifiers.append(key)
                choices.append(
                    rules.CourseRequirement(
                        course_id=key,
                        minimum_credits=choice.minimum_credits,
                        minimum_grade_points=choice.minimum_grade_points,
                        comparison_grade_scale=choice.comparison_grade_scale,
                    )
                )
            record_ids = {
                inputs.by_link[c.curriculum_course_id].course_record_id for c in condition.courses
            }
            record_ids.discard(None)
            if any(grade.course_record_id not in record_ids for grade in condition.grades):
                raise invalid("성적 관찰 값은 선택한 과목의 수강 기록에만 연결할 수 있습니다.")
            rows = inputs.load("course-records", record_ids)
            if len(set(identifiers)) != len(identifiers):
                for row in rows:
                    inputs.use("course-records", row)
                return (
                    rules.ReviewRule(**base, reason="ambiguous_personal_course_mapping"),
                    rules.Snapshot(),
                    {},
                )
            return (
                rules.CourseRule(**base, courses=tuple(choices)),
                rules.Snapshot(academics=tuple(inputs.academic(row) for row in rows)),
                aliases,
            )
        case dto.VolunteerCondition():
            rows = inputs.load("activity-records", condition.activity_ids)
            values = []
            for row in rows:
                inputs.use("activity-records", row)
                observed = row.observed_on is not None and row.observed_on <= on
                values.append(
                    rules.VolunteerRecord(
                        id=row.id,
                        approval_status=row.approval
                        if observed and row.approval
                        else "needs_review",
                        approved_hours=row.approved_hours if observed else None,
                    )
                )
            return (
                rules.VolunteerRule(**base, minimum=condition.minimum),
                rules.Snapshot(volunteers=tuple(values)),
                aliases,
            )
        case dto.CertificateCondition():
            by_id = {
                row.id: row
                for row in inputs.load(
                    "credential-records", [o.credential_id for o in condition.certificates]
                )
            }
            values = []
            for observation in condition.certificates:
                row = by_id[observation.credential_id]
                inputs.use("credential-records", row)
                approval = {"held": "approved", "not_held": "rejected", "unknown": "needs_review"}[
                    observation.possession
                ]
                if row.earned_on and row.earned_on > on:
                    approval = "rejected"
                values.append(
                    rules.CertificateRecord(
                        id=row.id,
                        certificate_id=row.id,
                        approval_status=approval,
                        expires_on=row.expires_on,
                        validity_known=observation.validity_known,
                    )
                )
            return (
                rules.CertificateRule(**base, certificate_ids=tuple(by_id)),
                rules.Snapshot(certificates=tuple(values)),
                aliases,
            )
        case dto.ThesisCondition():
            by_id = {
                row.id: row
                for row in inputs.load(
                    "achievement-records", [o.achievement_id for o in condition.records]
                )
            }
            values = []
            for observation in condition.records:
                row = by_id[observation.achievement_id]
                inputs.use("achievement-records", row)
                if not row.thesis_type:
                    raise invalid("선택한 성과에 논문·캡스톤 유형을 먼저 기록해 주세요.")
                approval = observation.approval
                if observation.completion == "unknown":
                    approval = "needs_review"
                if approval == "approved" and (
                    row.thesis_approved_on is None or row.thesis_approved_on > on
                ):
                    approval = "needs_review"
                values.append(
                    rules.ThesisRecord(
                        id=row.id,
                        thesis_type=row.thesis_type,
                        is_completed=observation.completion == "completed",
                        approval_status=approval,
                        grade=row.thesis_grade or None,
                    )
                )
            return (
                rules.ThesisRule(
                    **base,
                    thesis_type=condition.thesis_type,
                    requires_approval=condition.requires_approval,
                    accepted_grades=tuple(condition.accepted_grades),
                ),
                rules.Snapshot(theses=tuple(values)),
                aliases,
            )
    raise invalid()


def view(row):
    result = rules.Evaluation.model_validate(row.result_json)
    if result.official:
        raise conflict()
    conditions = {item["rule_id"]: item.get("condition") for item in row.criteria_json}
    aliases = row.course_aliases_json
    items = []
    for value in result.results:
        mapping = aliases.get(str(value.rule_id), {})
        items.append(
            dto.EvaluationItem(
                rule_id=value.rule_id,
                rule_version=value.rule_set_version,
                title=value.title,
                status=value.status,
                reason=value.reason,
                current=value.current,
                required=value.required,
                deficit=value.deficit,
                missing_course_ids=[
                    mapping.get(str(identifier), identifier)
                    for identifier in value.missing_course_ids
                ],
                uncertain_course_ids=[
                    mapping.get(str(identifier), identifier)
                    for identifier in value.uncertain_course_ids
                ],
                evidence_record_ids=list(value.evidence_record_ids),
                condition=conditions.get(str(value.rule_id)),
            )
        )
    return dto.PersonalEvaluationView(
        id=row.id,
        owner_id=row.owner_id,
        client_id=row.client_id,
        curriculum_id=row.curriculum_id,
        curriculum_version=row.curriculum_version,
        curriculum_title=row.curriculum_title,
        created_at=row.created_at,
        evaluated_on=row.evaluated_on,
        official=False,
        label=result.label,
        status=result.status,
        reason=result.reason,
        results=items,
        source_versions=row.source_versions_json,
    )


def create(db, request, payload):
    identity = auth.current_identity(request, db)
    auth.throttle(db, "personal-evaluation:" + str(identity.user.id), limit=60)
    identity = locked_identity(db, request)
    owner_id = identity.user.id
    digest = hashlib.sha256(
        json.dumps(
            payload.model_dump(mode="json", exclude_unset=True), sort_keys=True, ensure_ascii=False
        ).encode()
    ).hexdigest()
    if payload.client_id:
        receipt = db.get(PersonalCreationReceipt, (owner_id, RESOURCE, payload.client_id))
        if receipt:
            if receipt.digest != digest:
                raise conflict()
            previous = db.scalar(
                select(PersonalEvaluation).where(
                    PersonalEvaluation.owner_id == owner_id,
                    PersonalEvaluation.id == receipt.record_id,
                )
            )
            if previous is None:
                raise conflict()
            return view(previous)
    curriculum = personal.get(db, owner_id, PersonalCurriculum, payload.curriculum_id)
    if curriculum.version != payload.expected_curriculum_version:
        raise conflict()
    on = payload.as_of or datetime.now(UTC).date()
    saved_rules = list(
        db.scalars(
            select(PersonalGraduationRule)
            .where(
                PersonalGraduationRule.owner_id == owner_id,
                PersonalGraduationRule.curriculum_id == curriculum.id,
                or_(
                    PersonalGraduationRule.effective_from.is_(None),
                    PersonalGraduationRule.effective_from <= on,
                ),
                or_(
                    PersonalGraduationRule.effective_to.is_(None),
                    PersonalGraduationRule.effective_to >= on,
                ),
            )
            .order_by(PersonalGraduationRule.id)
            .limit(101)
        )
    )
    if len(saved_rules) > 100:
        raise invalid("계산할 활성 개인 규칙은 100개 이내로 구성해 주세요.")
    by_rule = {item.id: item for item in saved_rules}
    for calculation in payload.calculations:
        row = personal.get(db, owner_id, PersonalGraduationRule, calculation.rule_id)
        if row.id not in by_rule:
            raise invalid("선택한 규칙의 교육과정과 기준일을 확인해 주세요.")
        if row.version != calculation.expected_version:
            raise conflict()
    inputs = Inputs(db, owner_id, curriculum, payload)
    inputs.pin(payload.expected_source_versions)
    calculations = {item.rule_id: item.condition for item in payload.calculations}
    cases, criteria, case_sources, aliases = [], [], [], {}
    try:
        for row in saved_rules:
            inputs.use("personal-graduation-rules", row)
            condition = calculations.get(row.id)
            rule, snapshot, mapping = calculate_case(inputs, row, condition, on)
            rule_set = rules.RuleSet(
                id=row.id,
                code="personal_" + row.id.hex,
                version=row.version,
                origin="personal",
                effective_from=row.effective_from,
                effective_to=row.effective_to,
                rules=(rule,),
            )
            cases.append((rule_set, snapshot))
            case_sources.append(
                {
                    "rule_set": rule_set.model_dump(mode="json"),
                    "source_ids": inputs.add_evidence(snapshot),
                }
            )
            criteria.append(
                {
                    "rule_id": str(row.id),
                    "condition": condition.model_dump(mode="json") if condition else None,
                }
            )
            aliases[str(row.id)] = {str(key): str(value) for key, value in mapping.items()}
        result = evaluate_personal_sources(tuple(cases), as_of=on)
        if result.official:
            raise conflict()
        item = PersonalEvaluation(
            owner_id=owner_id,
            client_id=payload.client_id,
            version=1,
            curriculum_id=curriculum.id,
            curriculum_version=curriculum.version,
            curriculum_title=curriculum.title,
            evaluated_on=on,
            result_json=result.model_dump(mode="json"),
            criteria_json=criteria,
            status=result.status,
            reason=result.reason,
            course_aliases_json=aliases,
            source_versions_json=[
                value.model_dump(mode="json") for _, value in sorted(inputs.versions.items())
            ],
            input_snapshot_json={"cases": case_sources, "sources": inputs.evidence},
        )
        db.add(item)
        db.flush()
        response = view(item)
        if payload.client_id:
            db.add(
                PersonalCreationReceipt(
                    owner_id=owner_id,
                    resource=RESOURCE,
                    client_id=payload.client_id,
                    record_id=item.id,
                    digest=digest,
                )
            )
        personal.commit(db)
        return response
    except ValidationError:
        db.rollback()
        raise conflict() from None
    except IntegrityError:
        db.rollback()
        raise conflict() from None


def listing(db, owner_id, curriculum_id=None, cursor=None, limit=100):
    statement = (
        select(PersonalEvaluation)
        .options(
            load_only(
                PersonalEvaluation.id,
                PersonalEvaluation.owner_id,
                PersonalEvaluation.client_id,
                PersonalEvaluation.version,
                PersonalEvaluation.curriculum_id,
                PersonalEvaluation.curriculum_version,
                PersonalEvaluation.curriculum_title,
                PersonalEvaluation.created_at,
                PersonalEvaluation.evaluated_on,
                PersonalEvaluation.status,
                PersonalEvaluation.reason,
            )
        )
        .where(PersonalEvaluation.owner_id == owner_id)
    )
    if curriculum_id:
        statement = statement.where(PersonalEvaluation.curriculum_id == curriculum_id)
    if cursor:
        previous = personal.get(db, owner_id, PersonalEvaluation, cursor)
        statement = statement.where(
            or_(
                PersonalEvaluation.created_at < previous.created_at,
                (PersonalEvaluation.created_at == previous.created_at)
                & (PersonalEvaluation.id < previous.id),
            )
        )
    return list(
        db.scalars(
            statement.order_by(
                PersonalEvaluation.created_at.desc(), PersonalEvaluation.id.desc()
            ).limit(limit + 1)
        )
    )


def detail(db, owner_id, record_id):
    row = db.scalar(
        select(PersonalEvaluation)
        .options(defer(PersonalEvaluation.input_snapshot_json))
        .where(
            PersonalEvaluation.id == record_id,
            PersonalEvaluation.owner_id == owner_id,
        )
    )
    if row is None:
        raise personal.missing()
    return row


def summary(row):
    return dto.PersonalEvaluationSummary.model_validate(row, from_attributes=True)


def remove(db, request, record_id, version):
    identity = locked_identity(db, request)
    row = personal.get(db, identity.user.id, PersonalEvaluation, record_id)
    if row.version != version:
        raise conflict()
    db.delete(row)
    personal.commit(db)


def replay(row):
    """Recompute a saved internal snapshot without consulting modified live records."""
    saved = row.input_snapshot_json
    cases = []
    for item in saved["cases"]:
        snapshot = {
            kind: [saved["sources"][kind][identifier] for identifier in identifiers]
            for kind, identifiers in item["source_ids"].items()
        }
        cases.append(
            (
                rules.RuleSet.model_validate(item["rule_set"]),
                rules.Snapshot.model_validate(snapshot),
            )
        )
    return evaluate_personal_sources(tuple(cases), as_of=row.evaluated_on)
