"""Personal CRUD: owner isolation, atomic references, versioning and safe retries."""

import hashlib
import json
from datetime import UTC, datetime

from fastapi.exceptions import RequestValidationError
from pydantic import ValidationError
from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError

from app.core.auth_errors import AuthError, conflict
from app.models.academic import Curriculum, Department
from app.models.identity import Institution
from app.models.personal import (
    AchievementRecord,
    ActivityRecord,
    ApplicationDocument,
    ApplicationSource,
    CourseRecord,
    CredentialRecord,
    ExperienceRecord,
    PersonalCreationReceipt,
    PersonalCurriculum,
    PersonalCurriculumCourse,
    PersonalEvent,
    PersonalGraduationRule,
    PlanningProfile,
    PortfolioComposition,
    PortfolioSource,
)
from app.schemas import personal as dto
from app.schemas.common import ErrorCode
from app.services.access import locked_identity

RESOURCES = {
    "events": (PersonalEvent, "Event"),
    "course-records": (CourseRecord, "CourseRecord"),
    "activity-records": (ActivityRecord, "ActivityRecord"),
    "experience-records": (ExperienceRecord, "ExperienceRecord"),
    "credential-records": (CredentialRecord, "CredentialRecord"),
    "achievement-records": (AchievementRecord, "AchievementRecord"),
    "personal-curricula": (PersonalCurriculum, "PersonalCurriculum"),
    "personal-curriculum-courses": (PersonalCurriculumCourse, "PersonalCurriculumCourse"),
    "personal-graduation-rules": (PersonalGraduationRule, "PersonalGraduationRule"),
    "portfolio-compositions": (PortfolioComposition, "PortfolioComposition"),
    "application-documents": (ApplicationDocument, "ApplicationDocument"),
}
RECORD_MODELS = {
    "course": CourseRecord,
    "activity": ActivityRecord,
    "experience": ExperienceRecord,
    "credential": CredentialRecord,
    "achievement": AchievementRecord,
}


def missing():
    return AuthError(404, ErrorCode.NOT_FOUND, "요청한 개인 자료를 찾을 수 없습니다.")


def get(db, owner_id, model, record_id):
    item = db.scalar(select(model).where(model.id == record_id, model.owner_id == owner_id))
    if item is None:
        raise missing()
    return item


def contents(db, item, schema):
    result = {
        key: getattr(item, key)
        for key in schema.model_fields
        if key not in ("related_record", "sources")
    }
    if isinstance(item, PersonalGraduationRule):
        result["related_record"] = None
        for kind in RECORD_MODELS:
            record_id = getattr(item, f"related_{kind}_id")
            if record_id:
                result["related_record"] = {"kind": kind, "record_id": record_id}
    if isinstance(item, PortfolioComposition):
        result["sources"] = [
            {"kind": "achievement", "record_id": source.achievement_id}
            for source in db.scalars(
                select(PortfolioSource)
                .where(
                    PortfolioSource.composition_id == item.id,
                    PortfolioSource.owner_id == item.owner_id,
                )
                .order_by(PortfolioSource.position)
            )
        ]
    if isinstance(item, ApplicationDocument):
        result["sources"] = [
            {
                "kind": "achievement" if source.achievement_id else "experience",
                "record_id": source.achievement_id or source.experience_id,
            }
            for source in db.scalars(
                select(ApplicationSource)
                .where(
                    ApplicationSource.document_id == item.id,
                    ApplicationSource.owner_id == item.owner_id,
                )
                .order_by(ApplicationSource.position)
            )
        ]
    return result


def view(db, item, prefix):
    schema = getattr(dto, prefix + "Create")
    return {
        **contents(db, item, schema),
        **{
            key: getattr(item, key)
            for key in ("id", "owner_id", "version", "created_at", "updated_at")
        },
        "origin": "personal",
        "official": False,
    }


def validate(schema, value):
    try:
        return schema.model_validate(value)
    except ValidationError as error:
        errors = [dict(item, loc=("body", *item["loc"])) for item in error.errors()]
        raise RequestValidationError(errors) from None


def commit(db):
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise conflict() from None


def profile(db, owner_id):
    item = db.get(PlanningProfile, owner_id)
    if item is None:
        return {**dto.ProfileData().model_dump(), "owner_id": owner_id, "version": 0}
    return {
        **{key: getattr(item, key) for key in dto.ProfileData.model_fields},
        **{key: getattr(item, key) for key in ("owner_id", "version", "created_at", "updated_at")},
    }


def save_profile(db, request, payload):
    identity = locked_identity(db, request)
    previous = profile(db, identity.user.id)
    if previous["version"] != payload.expected_version:
        raise conflict()
    fields = dto.ProfileData.model_fields
    merged = {key: previous[key] for key in fields}
    merged.update(payload.model_dump(exclude_unset=True, exclude={"expected_version"}))
    data = validate(dto.ProfileData, merged).model_dump()
    institution_id = data["institution_id"]
    if institution_id:
        school = db.get(Institution, institution_id)
        if school is None or school.deleted_at is not None:
            raise missing()
    for key, model in (("department_id", Department), ("curriculum_id", Curriculum)):
        if data[key]:
            row = db.get(model, data[key])
            if row is None or row.institution_id != institution_id:
                raise missing()
            if model == Curriculum and row.department_id != data["department_id"]:
                raise conflict()
    item = db.get(PlanningProfile, identity.user.id)
    if item is None:
        item = PlanningProfile(owner_id=identity.user.id)
        db.add(item)
    for key, value in data.items():
        setattr(item, key, value)
    item.version = previous["version"] + 1
    item.updated_at = datetime.now(UTC)
    commit(db)
    return profile(db, identity.user.id)


def listing(
    db,
    owner_id,
    model,
    *,
    query="",
    cursor=None,
    limit=100,
    client_id=None,
    curriculum_id=None,
    starts_before=None,
    ends_after=None,
):
    statement = select(model).where(model.owner_id == owner_id)
    if query:
        statement = statement.where(model.title.icontains(query, autoescape=True))
    if cursor:
        statement = statement.where(model.id > cursor)
    if client_id:
        statement = statement.where(model.client_id == client_id)
    if curriculum_id:
        if not hasattr(model, "curriculum_id"):
            raise AuthError(
                422, ErrorCode.VALIDATION_ERROR, "이 목록에는 교육과정 필터를 사용할 수 없습니다."
            )
        get(db, owner_id, PersonalCurriculum, curriculum_id)
        statement = statement.where(model.curriculum_id == curriculum_id)
    if starts_before or ends_after:
        if model != PersonalEvent:
            raise AuthError(
                422, ErrorCode.VALIDATION_ERROR, "일정 목록에서만 기간을 조회할 수 있습니다."
            )
        if starts_before:
            statement = statement.where(model.starts_at < starts_before)
        if ends_after:
            statement = statement.where(model.ends_at > ends_after)
        if starts_before and ends_after and starts_before <= ends_after:
            raise AuthError(422, ErrorCode.VALIDATION_ERROR, "조회 기간을 확인해 주세요.")
    return list(db.scalars(statement.order_by(model.id).limit(limit + 1)))


def check_relations(db, owner_id, model, data):
    if model in (PersonalCurriculumCourse, PersonalGraduationRule):
        get(db, owner_id, PersonalCurriculum, data["curriculum_id"])
    if model == PersonalCurriculumCourse and data["course_record_id"]:
        get(db, owner_id, CourseRecord, data["course_record_id"])
    if model == PersonalGraduationRule:
        if data["curriculum_course_id"]:
            course = get(db, owner_id, PersonalCurriculumCourse, data["curriculum_course_id"])
            if course.curriculum_id != data["curriculum_id"]:
                raise conflict()
        if data["related_record"]:
            reference = data["related_record"]
            get(db, owner_id, RECORD_MODELS[reference["kind"]], reference["record_id"])
    for reference in data.get("sources", []):
        get(db, owner_id, RECORD_MODELS[reference["kind"]], reference["record_id"])


def set_values(db, item, data):
    values = {key: value for key, value in data.items() if key not in ("sources", "related_record")}
    if isinstance(item, PersonalGraduationRule):
        for kind in RECORD_MODELS:
            values[f"related_{kind}_id"] = None
        reference = data["related_record"]
        if reference:
            values[f"related_{reference['kind']}_id"] = reference["record_id"]
    for key, value in values.items():
        setattr(item, key, value)
    if "sources" not in data:
        return
    source_model, parent_key = (
        (PortfolioSource, "composition_id")
        if isinstance(item, PortfolioComposition)
        else (ApplicationSource, "document_id")
    )
    # Flush the parent before inserting composite owner FKs; source replacement
    # and the parent version update remain in the same transaction.
    db.flush()
    db.execute(
        delete(source_model).where(
            getattr(source_model, parent_key) == item.id, source_model.owner_id == item.owner_id
        )
    )
    for position, reference in enumerate(data["sources"]):
        db.add(
            source_model(
                **{
                    parent_key: item.id,
                    "owner_id": item.owner_id,
                    "position": position,
                    reference["kind"] + "_id": reference["record_id"],
                }
            )
        )


def invalidate_reviews(db, item):
    if not isinstance(item, AchievementRecord):
        return
    affected = db.scalars(
        select(PortfolioComposition)
        .join(PortfolioSource, PortfolioSource.composition_id == PortfolioComposition.id)
        .where(
            PortfolioSource.achievement_id == item.id,
            PortfolioComposition.owner_id == item.owner_id,
            PortfolioComposition.reviewed.is_(True),
        )
    )
    for composition in affected:
        composition.reviewed = False
        composition.version += 1
        composition.updated_at = datetime.now(UTC)


def save(db, request, resource, payload, record_id=None):
    identity = locked_identity(db, request)
    owner_id = identity.user.id
    model, prefix = RESOURCES[resource]
    schema = getattr(dto, prefix + "Create")
    item = get(db, owner_id, model, record_id) if record_id else None
    if item is not None:
        if item.version != payload.expected_version:
            raise conflict()
        previous = contents(db, item, schema)
        updates = payload.model_dump(exclude_unset=True, exclude={"expected_version"})
        merged = {**previous, **updates}
        if (
            model == PortfolioComposition
            and any(
                key in updates and updates[key] != previous[key]
                for key in ("title", "detail", "sources", "audience")
            )
            and "reviewed" not in updates
        ):
            merged["reviewed"] = False
        data = validate(schema, merged).model_dump()
    else:
        data = payload.model_dump()
        if payload.client_id:
            digest = hashlib.sha256(
                json.dumps(
                    payload.model_dump(mode="json", exclude_unset=True),
                    sort_keys=True,
                    ensure_ascii=False,
                ).encode()
            ).hexdigest()
            receipt = db.get(PersonalCreationReceipt, (owner_id, resource, payload.client_id))
            if receipt:
                if receipt.digest != digest:
                    raise conflict()
                existing = db.scalar(
                    select(model).where(model.owner_id == owner_id, model.id == receipt.record_id)
                )
                if existing is None:
                    raise conflict()
                return view(db, existing, prefix)
    check_relations(db, owner_id, model, data)
    try:
        if item is None:
            item = model(owner_id=owner_id)
            db.add(item)
            item.version = 1
        else:
            invalidate_reviews(db, item)
            item.version += 1
        item.updated_at = datetime.now(UTC)
        set_values(db, item, data)
        db.flush()
        if record_id is None and payload.client_id:
            db.add(
                PersonalCreationReceipt(
                    owner_id=owner_id,
                    resource=resource,
                    client_id=payload.client_id,
                    record_id=item.id,
                    digest=digest,
                )
            )
        commit(db)
    except IntegrityError:
        db.rollback()
        raise conflict() from None
    return view(db, item, prefix)


def references(db, owner_id, model, record_id):
    get(db, owner_id, model, record_id)
    targets = []
    if model == PersonalCurriculum:
        targets += [
            (PersonalCurriculumCourse, "curriculum_id"),
            (PersonalGraduationRule, "curriculum_id"),
        ]
    if model == PersonalCurriculumCourse:
        targets.append((PersonalGraduationRule, "curriculum_course_id"))
    if model == CourseRecord:
        targets.append((PersonalCurriculumCourse, "course_record_id"))
    for kind, target in RECORD_MODELS.items():
        if model == target:
            targets.append((PersonalGraduationRule, f"related_{kind}_id"))
    result = []
    for target, key in targets:
        for row in db.scalars(
            select(target).where(target.owner_id == owner_id, getattr(target, key) == record_id)
        ):
            result.append({"id": row.id, "kind": target.__tablename__, "name": row.title})
    if model == AchievementRecord:
        for row in db.scalars(
            select(PortfolioComposition)
            .join(PortfolioSource, PortfolioSource.composition_id == PortfolioComposition.id)
            .where(
                PortfolioComposition.owner_id == owner_id,
                PortfolioSource.achievement_id == record_id,
            )
        ):
            result.append({"id": row.id, "kind": "portfolio-compositions", "name": row.title})
    if model in (AchievementRecord, ExperienceRecord):
        key = (
            ApplicationSource.achievement_id
            if model == AchievementRecord
            else ApplicationSource.experience_id
        )
        for row in db.scalars(
            select(ApplicationDocument)
            .join(ApplicationSource, ApplicationSource.document_id == ApplicationDocument.id)
            .where(ApplicationDocument.owner_id == owner_id, key == record_id)
        ):
            result.append({"id": row.id, "kind": "application-documents", "name": row.title})
    # The same rule may reference an item through more than one relation.
    return list({row["id"]: row for row in result}.values())


def remove(db, request, resource, record_id, expected_version):
    identity = locked_identity(db, request)
    model, _ = RESOURCES[resource]
    item = get(db, identity.user.id, model, record_id)
    if item.version != expected_version or references(db, identity.user.id, model, record_id):
        raise conflict()
    db.delete(item)
    commit(db)
