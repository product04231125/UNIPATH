"""Scoped catalog mutations, immutable reviewed revisions and safe reference checks."""

import hashlib
import json
from datetime import UTC, datetime
from uuid import uuid4

from sqlalchemy import and_, exists, func, or_, select
from sqlalchemy.exc import IntegrityError

from app.core.auth_errors import AuthError, conflict, forbidden
from app.models.academic import (
    Course,
    CoursePlacementReceipt,
    Curriculum,
    CurriculumCourse,
    Department,
    GraduationRule,
    OfficialDocument,
    RuleSet,
    SchoolClassification,
)
from app.models.graduation import GraduationAudit, GraduationCatalogReview
from app.models.identity import AdminScope, IdentityAudit, Institution, Role
from app.models.official_records import OfficialRecordBatch, OfficialRecordCourseRef
from app.models.personal import CourseRecord, PlanningProfile
from app.models.record_sources import OfficialRecordSource
from app.models.rule_programs import ProgramCourseRef, ProgramRule, RuleProgram
from app.schemas import academic as dto
from app.schemas.common import ErrorCode
from app.services import access, auth

RESOURCES = {
    "departments": (Department, "department"),
    "curricula": (Curriculum, "curriculum"),
    "courses": (Course, "course"),
    "curriculum-courses": (CurriculumCourse, "curriculumCourse"),
    "classifications": (SchoolClassification, "classification"),
    "rule-sets": (RuleSet, "ruleSet"),
    "rules": (GraduationRule, "rule"),
    "documents": (OfficialDocument, "document"),
}
VERSIONED = (RuleSet, GraduationRule, OfficialDocument)
RELATIONS = {
    "department_id": Department,
    "curriculum_id": Curriculum,
    "course_id": Course,
    "rule_set_id": RuleSet,
    "rule_id": GraduationRule,
    "parent_id": SchoolClassification,
    "classification_id": SchoolClassification,
    "track_id": SchoolClassification,
}
# Which classification kinds each reference may point to.
CLASSIFICATION_KINDS = {
    "parent_id": ("category",),
    "classification_id": ("category", "subcategory"),
    "track_id": ("track",),
}


def failure(message, status=409):
    return AuthError(status, ErrorCode.NOT_FOUND if status == 404 else ErrorCode.CONFLICT, message)


def lock_actor(db, request):
    # Shared with role/scope changes, avoiding a write authorized before revocation.
    return access.locked_identity(db, request)


def school(db, identity, institution_id):
    auth.require_institution(db, identity, institution_id)
    item = db.get(Institution, institution_id)
    if item is None or item.deleted_at is not None:
        raise failure("학교를 찾을 수 없습니다.", 404)
    return item


def read(db, identity, model, record_id):
    if identity.user.role not in (Role.SUPER_ADMIN, Role.SCHOOL_ADMIN):
        raise forbidden()
    item = db.get(model, record_id)
    if item is None:
        raise failure("항목을 찾을 수 없습니다.", 404)
    school(db, identity, item.institution_id)
    return item


def list_records(db, identity, model, institution_id, query, status, cursor, limit):
    if identity.user.role not in (Role.SUPER_ADMIN, Role.SCHOOL_ADMIN):
        raise forbidden()
    statement = (
        select(model)
        .join(Institution, Institution.id == model.institution_id)
        .where(Institution.deleted_at.is_(None))
    )
    if institution_id is not None:
        school(db, identity, institution_id)
        statement = statement.where(model.institution_id == institution_id)
    if identity.user.role == Role.SCHOOL_ADMIN:
        statement = statement.where(
            exists().where(
                AdminScope.institution_id == model.institution_id,
                AdminScope.user_id == identity.user.id,
                AdminScope.status == "active",
            )
        )
    if query:
        statement = statement.where(model.name.icontains(query, autoescape=True))
    if status:
        if model == SchoolClassification:
            if status not in ("active", "inactive"):
                return []
            statement = statement.where(model.status == status)
        elif model not in VERSIONED:
            if status != "active":
                return []
        else:
            statement = statement.where(model.status == status)
    if cursor is not None:
        statement = statement.where(model.id > cursor)
    return list(db.scalars(statement.order_by(model.id).limit(limit + 1)))


def validate_relations(db, identity, model, values, current=None):
    school(db, identity, values["institution_id"])
    targets = {}
    for key, target_model in RELATIONS.items():
        target_id = values.get(key)
        if target_id is None:
            continue
        target = db.get(target_model, target_id)
        if target is None or target.institution_id != values["institution_id"]:
            raise failure("연결 대상과 학교 소속을 확인해 주세요.")
        targets[key] = target
        if key in CLASSIFICATION_KINDS:
            validate_classification(db, key, target, current)
    curriculum = targets.get("curriculum_id")
    if (
        curriculum
        and values.get("department_id")
        and (curriculum.department_id != values["department_id"])
    ):
        raise failure("학과와 교육과정의 소속이 다릅니다.")
    group = targets.get("rule_set_id")
    if group:
        if group.status != "draft":
            raise failure("적용된 규칙 묶음은 변경할 수 없습니다. 새 버전을 만드세요.")
        if any(
            getattr(group, key) != values.get(key)
            for key in (
                "institution_id",
                "department_id",
                "curriculum_id",
                "effective_from",
                "effective_to",
            )
        ):
            raise failure("요건과 규칙 묶음의 범위·기간이 다릅니다.")
    return group


def validate_classification(db, key, target, current):
    if target.kind not in CLASSIFICATION_KINDS[key]:
        raise failure("연결할 수 없는 분류 종류입니다.")
    if current is not None and getattr(current, key) == target.id:
        # Keeping an existing link is allowed after the classification is deactivated.
        return
    parent = db.get(SchoolClassification, target.parent_id) if target.parent_id else None
    if target.status != "active" or (parent is not None and parent.status != "active"):
        raise failure("사용 중지된 분류는 새로 연결할 수 없습니다.")


def audit(db, identity, kind, action, item, request):
    access.audit(
        db,
        identity.user.id,
        f"academic:{kind}:{action}",
        item.id,
        request.state.request_id,
        item.id if kind == "institution" else item.institution_id,
    )


def commit(db):
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise failure("중복 데이터 또는 연결 참조가 있습니다. 새로 조회해 확인하세요.") from None


# Older clients omit these fields; on update, omission keeps the stored value.
KEPT_WHEN_OMITTED = {
    Course: ("classification_id", "track_id", "department_id"),
    CurriculumCourse: ("classification_id", "track_id"),
}


def save(db, request, model, kind, payload, record_id=None):
    identity = lock_actor(db, request)
    item = stage(db, request, identity, model, kind, payload, record_id)
    commit(db)
    return item


def stage(db, request, identity, model, kind, payload, record_id=None):
    """Validate, write and audit one record; the caller holds the actor lock and commits."""
    values = payload.model_dump(exclude={"expected_version"})
    current = None if record_id is None else read(db, identity, model, record_id)
    if current is not None:
        for key in KEPT_WHEN_OMITTED.get(model, ()):
            if key in values and key not in payload.model_fields_set:
                values[key] = getattr(current, key)
    group = validate_relations(db, identity, model, values, current)
    if record_id is None:
        item = model(**values, created_by=identity.user.id, updated_by=identity.user.id)
        db.add(item)
        action = "create"
    else:
        item = current
        if item.version != payload.expected_version:
            raise conflict()
        if model == SchoolClassification and item.kind != values["kind"]:
            raise failure("분류 종류는 바꿀 수 없습니다. 새 분류를 등록하세요.")
        if model in VERSIONED and item.status != "draft":
            raise failure("적용본은 변경할 수 없습니다. 새 버전 초안을 만드세요.")
        for key in ("institution_id", "department_id", "curriculum_id", "rule_set_id"):
            if model == Course and key == "department_id":
                # A course's owning department can be corrected; it scopes nothing below it.
                continue
            if key in values and getattr(item, key) != values[key]:
                raise failure("기존 항목의 소속은 변경할 수 없습니다. 새 항목을 등록하세요.")
        for key, value in values.items():
            setattr(item, key, value)
        item.version += 1
        item.updated_by, item.updated_at = identity.user.id, datetime.now(UTC)
        action = "update"
        if model == RuleSet:
            for child in db.scalars(
                select(GraduationRule).where(GraduationRule.rule_set_id == item.id)
            ):
                if child.status != "draft":
                    raise conflict()
                child.effective_from, child.effective_to = item.effective_from, item.effective_to
                child.version += 1
                child.updated_by, child.updated_at = identity.user.id, datetime.now(UTC)
    if group:
        group.version += 1
        group.updated_by, group.updated_at = identity.user.id, datetime.now(UTC)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise failure("동일 범위에 중복된 코드·이름·관계가 있습니다.") from None
    audit(db, identity, kind, action, item, request)
    return item


def placement_digest(payload):
    body = payload.model_dump(mode="json", exclude={"client_id"})
    return hashlib.sha256(json.dumps(body, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def placement_view(db, identity, receipt, *, replayed):
    auth.require_institution(db, identity, receipt.institution_id)
    course = db.get(Course, receipt.course_id) if receipt.course_id else None
    link = (
        db.get(CurriculumCourse, receipt.curriculum_course_id)
        if receipt.curriculum_course_id
        else None
    )
    return dto.CoursePlacementView(
        client_id=receipt.client_id,
        institution_id=receipt.institution_id,
        course=dto.CourseView.model_validate(course) if course else None,
        curriculum_course=dto.CurriculumCourseView.model_validate(link) if link else None,
        created_at=receipt.created_at,
        replayed=replayed,
    )


def place_course(db, request, payload):
    """Create a course and its curriculum link together, at most once per client ID."""
    identity = lock_actor(db, request)
    digest = placement_digest(payload)
    receipt = db.get(CoursePlacementReceipt, (identity.user.id, payload.client_id))
    if receipt is not None:
        if receipt.digest != digest:
            raise failure("같은 제출 ID로 다른 내용을 저장할 수 없습니다. 새로 제출하세요.")
        return placement_view(db, identity, receipt, replayed=True)
    course = stage(db, request, identity, Course, "course", payload.course)
    link = payload.link
    link_payload = dto.CurriculumCourseCreate(
        name=link.name or course.name,
        institution_id=course.institution_id,
        curriculum_id=link.curriculum_id,
        course_id=course.id,
        category=link.category,
        required=link.required,
        classification_id=link.classification_id,
        track_id=link.track_id,
    )
    curriculum_course = stage(
        db, request, identity, CurriculumCourse, "curriculumCourse", link_payload
    )
    receipt = CoursePlacementReceipt(
        actor_id=identity.user.id,
        client_id=payload.client_id,
        institution_id=course.institution_id,
        digest=digest,
        course_id=course.id,
        curriculum_course_id=curriculum_course.id,
    )
    db.add(receipt)
    commit(db)
    db.refresh(receipt)
    return placement_view(db, identity, receipt, replayed=False)


def read_placement(db, request, client_id):
    identity = auth.current_identity(request, db)
    receipt = db.get(CoursePlacementReceipt, (identity.user.id, client_id))
    if receipt is None:
        raise failure("저장된 제출을 찾을 수 없습니다. 저장되지 않았다면 다시 제출하세요.", 404)
    return placement_view(db, identity, receipt, replayed=True)


def references(db, identity, model, record_id):
    if model == Institution:
        item = school(db, identity, record_id)
    else:
        item = read(db, identity, model, record_id)
    result = []
    for target_model, kind in RESOURCES.values():
        for column in target_model.__table__.columns:
            if any(fk.column.table.name == model.__tablename__ for fk in column.foreign_keys):
                for other in db.scalars(select(target_model).where(column == record_id)):
                    value = {"id": other.id, "kind": kind, "name": other.name}
                    if value not in result:
                        result.append(value)
    if model == Institution:
        for scope in db.scalars(
            select(AdminScope).where(
                AdminScope.institution_id == item.id, AdminScope.status == "active"
            )
        ):
            result.append({"id": scope.id, "kind": "scope", "name": "활성 학교 관리 범위"})
    profile_key = {Department: "department_id", Curriculum: "curriculum_id"}.get(model)
    if profile_key and any(
        db.scalar(select(exists().where(getattr(protected_model, profile_key) == record_id)))
        for protected_model in (
            PlanningProfile,
            OfficialRecordSource,
            OfficialRecordBatch,
            GraduationAudit,
            GraduationCatalogReview,
        )
    ):
        # A profile FK must prevent catalog deletion without exposing a student's
        # identity, profile/source values, or the number of private references.
        result.append({"id": record_id, "kind": "protected_reference", "name": "보호된 연결 참조"})
    personal_key = {Course: "catalog_course_id", CurriculumCourse: "curriculum_course_id"}.get(
        model
    )
    if personal_key and db.scalar(
        select(exists().where(getattr(CourseRecord, personal_key) == record_id))
    ):
        # A student's course record names this catalog entry; keep it resolvable.
        result.append({"id": record_id, "kind": "protected_reference", "name": "보호된 연결 참조"})
    if model is Course:
        if db.scalar(select(exists().where(OfficialRecordCourseRef.course_id == record_id))):
            result.append(
                {"id": record_id, "kind": "protected_reference", "name": "보호된 연결 참조"}
            )
        for program in db.scalars(
            select(RuleProgram)
            .join(ProgramRule, ProgramRule.program_id == RuleProgram.id)
            .join(ProgramCourseRef, ProgramCourseRef.program_rule_id == ProgramRule.id)
            .where(ProgramCourseRef.course_id == record_id)
            .distinct()
            .order_by(RuleProgram.id)
        ):
            result.append({"id": program.id, "kind": "ruleProgram", "name": program.name})
    return [row for index, row in enumerate(result) if row not in result[:index]]


def remove(db, request, model, kind, record_id, version):
    identity = lock_actor(db, request)
    item = (
        school(db, identity, record_id)
        if model == Institution
        else read(db, identity, model, record_id)
    )
    if model == Institution:
        access.require_super(db, identity)
    if item.version != version:
        raise conflict()
    if model in VERSIONED and item.status != "draft":
        raise failure("적용 이력은 삭제할 수 없습니다.")
    if references(db, identity, model, record_id):
        raise failure("연결된 항목이 있어 삭제할 수 없습니다. 참조를 먼저 확인하세요.")
    if isinstance(item, GraduationRule) and item.rule_set_id:
        group = db.get(RuleSet, item.rule_set_id)
        if group.status != "draft":
            raise failure("적용된 규칙 묶음의 요건은 삭제할 수 없습니다.")
        group.version += 1
        group.updated_by, group.updated_at = identity.user.id, datetime.now(UTC)
    audit(db, identity, kind, "delete", item, request)
    if model == Institution:
        item.deleted_at = item.updated_at = datetime.now(UTC)
        item.version += 1
    else:
        db.delete(item)
    commit(db)


def review(db, request, model, kind, record_id, version, *, new_draft=False):
    identity = lock_actor(db, request)
    item = read(db, identity, model, record_id)
    if item.version != version:
        raise conflict()
    if isinstance(item, GraduationRule) and item.rule_set_id:
        raise failure("묶음에 속한 요건은 규칙 묶음에서 함께 적용·버전 관리하세요.")
    children = (
        list(db.scalars(select(GraduationRule).where(GraduationRule.rule_set_id == item.id)))
        if model == RuleSet
        else []
    )
    if not new_draft:
        if item.status != "draft" or model == RuleSet and not children:
            raise failure("내용이 있는 초안만 검토·적용할 수 있습니다.")
        now = datetime.now(UTC)
        for record in [item, *children]:
            if record.status != "draft":
                raise conflict()
            if record is not item and any(
                getattr(record, key) != getattr(item, key)
                for key in (
                    "institution_id",
                    "department_id",
                    "curriculum_id",
                    "effective_from",
                    "effective_to",
                )
            ):
                raise failure("하위 요건과 규칙 묶음의 범위·기간을 확인하세요.")
            record.status, record.applied_by, record.applied_at = "applied", identity.user.id, now
            record.version += 1
            record.updated_by, record.updated_at = identity.user.id, now
        audit(db, identity, kind, "apply", item, request)
        commit(db)
        return item
    if item.status != "applied":
        raise failure("적용된 버전에서만 새 초안을 만들 수 있습니다.")

    def clone(original, group_id=None):
        cls = type(original)
        if db.scalar(
            select(cls.id).where(cls.lineage_id == original.lineage_id, cls.status == "draft")
        ):
            raise failure("이미 새 버전 초안이 있습니다. 기존 초안을 확인하세요.")
        fields = {c.name: getattr(original, c.name) for c in cls.__table__.columns}
        fields.update(
            id=uuid4(),
            version=1,
            revision=1
            + db.scalar(
                select(func.max(cls.revision)).where(cls.lineage_id == original.lineage_id)
            ),
            status="draft",
            applied_by=None,
            applied_at=None,
            created_at=datetime.now(UTC),
            updated_at=datetime.now(UTC),
            created_by=identity.user.id,
            updated_by=identity.user.id,
        )
        if group_id is not None:
            fields["rule_set_id"] = group_id
        result = cls(**fields)
        db.add(result)
        return result

    draft = clone(item)
    for child in children:
        clone(child, draft.id)
    audit(db, identity, kind, "new_version", draft, request)
    commit(db)
    return draft


def update_institution(db, request, record_id, payload):
    identity = lock_actor(db, request)
    access.require_super(db, identity)
    item = school(db, identity, record_id)
    if item.version != payload.expected_version:
        raise conflict()
    for key, value in payload.model_dump(exclude={"expected_version"}).items():
        setattr(item, key, value)
    item.version += 1
    item.updated_at = datetime.now(UTC)
    audit(db, identity, "institution", "update", item, request)
    commit(db)
    return item


SCOPE_ACTIONS = ("scope_granted", "scope_revoked")


def kind_condition(kind):
    """The inverse of the kind labels assigned in history()."""
    action = IdentityAudit.action
    if kind == "scope":
        return action.in_(SCOPE_ACTIONS)
    if kind == "institution":
        return or_(
            action == "institution_created",
            action.startswith("academic:institution:", autoescape=True),
        )
    if kind == "account":
        return and_(
            ~action.startswith("academic:", autoescape=True),
            action.not_in((*SCOPE_ACTIONS, "institution_created")),
        )
    return action.startswith(f"academic:{kind}:", autoescape=True)


def history(db, identity, institution_id, cursor, limit, filters=None):
    filters = filters or {}
    if identity.user.role not in (Role.SUPER_ADMIN, Role.SCHOOL_ADMIN):
        raise forbidden()
    statement = select(IdentityAudit)
    if institution_id is not None:
        school(db, identity, institution_id)
        statement = statement.where(IdentityAudit.institution_id == institution_id)
    if identity.user.role == Role.SCHOOL_ADMIN:
        statement = statement.where(
            exists().where(
                AdminScope.institution_id == IdentityAudit.institution_id,
                AdminScope.user_id == identity.user.id,
                AdminScope.status == "active",
            )
        )
    for key in ("target_id", "actor_id", "action"):
        if filters.get(key) is not None:
            statement = statement.where(getattr(IdentityAudit, key) == filters[key])
    if filters.get("kind"):
        statement = statement.where(kind_condition(filters["kind"]))
    if filters.get("occurred_from"):
        statement = statement.where(IdentityAudit.occurred_at >= filters["occurred_from"])
    if filters.get("occurred_to"):
        statement = statement.where(IdentityAudit.occurred_at < filters["occurred_to"])
    if cursor:
        statement = statement.where(IdentityAudit.id > cursor)
    result = []
    for row in db.scalars(statement.order_by(IdentityAudit.id).limit(limit + 1)):
        kind = (
            row.action.split(":")[1]
            if row.action.startswith("academic:")
            else (
                "scope"
                if row.action in ("scope_granted", "scope_revoked")
                else "institution"
                if row.action == "institution_created"
                else "account"
            )
        )
        result.append(
            {
                "id": row.id,
                "actor_id": row.actor_id,
                "target_id": row.target_id,
                "institution_id": row.institution_id,
                "action": row.action,
                "kind": kind,
                "occurred_at": row.occurred_at,
                "request_id": row.request_id,
            }
        )
    return result
