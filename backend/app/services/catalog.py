"""Read-only catalog visibility, applicable dates and latest applied revisions."""

from sqlalchemy import exists, or_, select
from sqlalchemy.orm import aliased

from app.core.auth_errors import AuthError
from app.models.academic import (
    Course,
    Curriculum,
    CurriculumCourse,
    Department,
    GraduationRule,
    OfficialDocument,
    RuleSet,
)
from app.models.identity import Institution
from app.schemas.common import ErrorCode


def missing():
    return AuthError(404, ErrorCode.NOT_FOUND, "요청한 학사 정보를 찾을 수 없습니다.")


def context(db, institution_id, department_id, curriculum_id):
    if curriculum_id:
        row = db.get(Curriculum, curriculum_id)
        if row is None or (department_id and department_id != row.department_id):
            raise missing()
        department_id = row.department_id
    if department_id:
        row = db.get(Department, department_id)
        if row is None or (institution_id and institution_id != row.institution_id):
            raise missing()
        institution_id = row.institution_id
    if institution_id:
        row = db.get(Institution, institution_id)
        if row is None or row.deleted_at is not None:
            raise missing()
    return institution_id, department_id, curriculum_id


def dates(model, on):
    return (
        or_(model.effective_from.is_(None), model.effective_from <= on),
        or_(model.effective_to.is_(None), model.effective_to >= on),
    )


def applied(model, on):
    newer = aliased(model)
    return (
        model.status == "applied",
        *dates(model, on),
        ~exists().where(
            newer.lineage_id == model.lineage_id,
            newer.revision > model.revision,
            newer.status == "applied",
            *dates(newer, on),
        ),
    )


def statement(model, on, institution_id=None, department_id=None, curriculum_id=None):
    query = select(model)
    if model == Institution:
        query = query.where(model.deleted_at.is_(None))
        if institution_id:
            query = query.where(model.id == institution_id)
        return query
    query = query.where(
        exists().where(Institution.id == model.institution_id, Institution.deleted_at.is_(None))
    )
    if institution_id:
        query = query.where(model.institution_id == institution_id)
    if model in (RuleSet, GraduationRule, OfficialDocument):
        query = query.where(*applied(model, on))
        if department_id:
            query = query.where(
                or_(model.department_id.is_(None), model.department_id == department_id)
            )
        if curriculum_id:
            query = query.where(
                or_(model.curriculum_id.is_(None), model.curriculum_id == curriculum_id)
            )
    elif model == Department and department_id:
        query = query.where(model.id == department_id)
    elif model == Curriculum:
        if department_id:
            query = query.where(model.department_id == department_id)
        if curriculum_id:
            query = query.where(model.id == curriculum_id)
    elif model == CurriculumCourse:
        if curriculum_id:
            query = query.where(model.curriculum_id == curriculum_id)
        elif department_id:
            query = query.where(
                exists().where(
                    Curriculum.id == model.curriculum_id, Curriculum.department_id == department_id
                )
            )
    elif model == Course and (curriculum_id or department_id):
        memberships = select(CurriculumCourse.course_id).join(
            Curriculum, Curriculum.id == CurriculumCourse.curriculum_id
        )
        if curriculum_id:
            memberships = memberships.where(Curriculum.id == curriculum_id)
        else:
            memberships = memberships.where(Curriculum.department_id == department_id)
        query = query.where(model.id.in_(memberships))
    if model == GraduationRule:
        parent_ids = statement(
            RuleSet, on, institution_id, department_id, curriculum_id
        ).with_only_columns(RuleSet.id)
        query = query.where(or_(model.rule_set_id.is_(None), model.rule_set_id.in_(parent_ids)))
    if model == OfficialDocument:
        rule_ids = statement(
            GraduationRule, on, institution_id, department_id, curriculum_id
        ).with_only_columns(GraduationRule.id)
        query = query.where(or_(model.rule_id.is_(None), model.rule_id.in_(rule_ids)))
    return query


def listing(
    db,
    model,
    *,
    on,
    institution_id=None,
    department_id=None,
    curriculum_id=None,
    query="",
    cursor=None,
    limit=100,
    rule_set_id=None,
):
    institution_id, department_id, curriculum_id = context(
        db, institution_id, department_id, curriculum_id
    )
    result = statement(model, on, institution_id, department_id, curriculum_id)
    if rule_set_id:
        if model != GraduationRule:
            raise missing()
        if (
            db.scalar(
                statement(RuleSet, on, institution_id, department_id, curriculum_id).where(
                    RuleSet.id == rule_set_id
                )
            )
            is None
        ):
            raise missing()
        result = result.where(model.rule_set_id == rule_set_id)
    if query:
        result = result.where(model.name.icontains(query, autoescape=True))
    if cursor:
        result = result.where(model.id > cursor)
    return list(db.scalars(result.order_by(model.id).limit(limit + 1)))


def detail(db, model, record_id, on):
    row = db.scalar(statement(model, on).where(model.id == record_id))
    if row is None:
        raise missing()
    return row
