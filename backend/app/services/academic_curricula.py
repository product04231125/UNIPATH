"""Curriculum-specific course recognition using the shared school classification IDs."""

from datetime import UTC, datetime
from uuid import uuid4

from sqlalchemy import delete, func, select

from app.core.auth_errors import conflict
from app.models.academic import Course, Curriculum, CurriculumCourse, Department
from app.models.academic_workspace import (
    AcademicCurriculumCourse,
    AcademicCurriculumDepartmentRef,
    AcademicCurriculumRevision,
    AcademicCurriculumTrackRef,
    ClassificationNode,
    ClassificationRevision,
    StudyTrack,
)
from app.schemas import academic_workspace as dto
from app.services import academic
from app.services.academic_workspace import digest, invalid, mutate, require_school, scoped_record


def classification(db, identity, revision_id, school):
    revision = scoped_record(db, identity, ClassificationRevision, revision_id)
    if revision.institution_id != school or revision.status != "published":
        invalid("classification_revision_id", "Use a published classification from this school")
    return revision


def nodes_for(db, classification_id):
    return {
        row.id: row
        for row in db.scalars(
            select(ClassificationNode).where(ClassificationNode.revision_id == classification_id)
        )
    }


def validate_scope(db, identity, school, scope):
    departments = {c.department_id for c in scope.clauses if c.department_id}
    tracks = {t for c in scope.clauses for t in c.track_ids}
    for dep_id in departments:
        dep = db.get(Department, dep_id)
        if dep is None or dep.institution_id != school:
            invalid("scope", "Use departments from this school")
    for track_id in tracks:
        track = db.get(StudyTrack, track_id)
        if track is None or track.institution_id != school or track.inactive_at is not None:
            invalid("scope", "Use active study tracks from this school")
    return departments, tracks


def courses(db, revision):
    return list(
        db.scalars(
            select(AcademicCurriculumCourse)
            .where(AcademicCurriculumCourse.curriculum_revision_id == revision.id)
            .order_by(AcademicCurriculumCourse.position)
        )
    )


def legacy_courses(db, revision):
    if revision.legacy_curriculum_id is None:
        return []
    pairs = db.execute(
        select(Course, CurriculumCourse)
        .join(CurriculumCourse, CurriculumCourse.course_id == Course.id)
        .where(CurriculumCourse.curriculum_id == revision.legacy_curriculum_id)
    ).all()
    return [
        dto.AcademicLegacyCurriculumCourse(
            course_id=course.id,
            course_version=course.version,
            course_name=course.name,
            course_code=course.code,
            credits=course.credits,
            legacy_category=link.category,
            legacy_required=link.required,
        )
        for course, link in pairs
    ]


def view(db, revision, id_map=None):
    db.flush()
    return dto.AcademicCurriculumView(
        **dto.AcademicCurriculumHeader.model_validate(revision).model_dump(),
        scope=dto.AcademicScope.model_validate(revision.scope_json),
        courses=[
            dto.AcademicCurriculumCourseView.model_validate(row) for row in courses(db, revision)
        ],
        legacy_courses=legacy_courses(db, revision),
        id_map=id_map or {},
    ).model_dump(mode="json")


def listing(db, identity, school, status, cursor, limit):
    require_school(db, identity, school)
    statement = select(AcademicCurriculumRevision).where(
        AcademicCurriculumRevision.institution_id == school
    )
    if status:
        statement = statement.where(AcademicCurriculumRevision.status == status)
    if cursor:
        statement = statement.where(AcademicCurriculumRevision.id > cursor)
    rows = list(db.scalars(statement.order_by(AcademicCurriculumRevision.id).limit(limit + 1)))
    return {"items": rows[:limit], "next_cursor": rows[limit - 1].id if len(rows) > limit else None}


def create(db, request, payload):
    def action(identity):
        classification(db, identity, payload.classification_revision_id, payload.institution_id)
        legacy = None
        scope = dto.AcademicScope()
        if payload.legacy_curriculum_id:
            legacy = scoped_record(db, identity, Curriculum, payload.legacy_curriculum_id)
            if legacy.institution_id != payload.institution_id:
                invalid("legacy_curriculum_id", "Use an existing curriculum from this school")
            if db.scalar(
                select(AcademicCurriculumRevision.id).where(
                    AcademicCurriculumRevision.legacy_curriculum_id == legacy.id
                )
            ):
                raise academic.failure(
                    "이 교육과정의 새 기준이 이미 있습니다. 기존 초안을 확인하세요."
                )
            # The legacy curriculum year is not an admission-year interval.
            scope = dto.AcademicScope(
                clauses=[dto.AcademicScopeClause(department_id=legacy.department_id)]
            )
        revision = AcademicCurriculumRevision(
            institution_id=payload.institution_id,
            lineage_id=legacy.id if legacy else uuid4(),
            legacy_curriculum_id=legacy.id if legacy else None,
            classification_revision_id=payload.classification_revision_id,
            revision=1,
            name=payload.name,
            curriculum_year=payload.curriculum_year,
            scope_json=scope.model_dump(mode="json"),
            created_by=identity.user.id,
            updated_by=identity.user.id,
        )
        db.add(revision)
        db.flush()
        if legacy:
            db.add(
                AcademicCurriculumDepartmentRef(
                    curriculum_revision_id=revision.id,
                    department_id=legacy.department_id,
                    institution_id=revision.institution_id,
                )
            )
        return view(db, revision)

    return mutate(db, request, payload.institution_id, payload, "curriculum_create", action)


def resolve_course(db, school, course_id, expected_version, field):
    course = db.get(Course, course_id)
    if course is None or course.institution_id != school:
        invalid(field, "Use a course from this school")
    if course.version != expected_version:
        raise academic.failure("과목 기준이 변경되었습니다. 최신 과목을 다시 선택하세요.")
    return course


def entry_node(nodes, node_id, field):
    node = nodes.get(node_id)
    if node is None or not node.selectable:
        invalid(field, "Select a usable node in the curriculum classification revision")
    return node


def replace(db, request, identity, record_id, payload):
    revision = scoped_record(db, identity, AcademicCurriculumRevision, record_id)

    def action(actor):
        if revision.status != "draft" or revision.version != payload.expected_version:
            raise conflict()
        classification(db, actor, payload.classification_revision_id, revision.institution_id)
        departments, tracks = validate_scope(db, actor, revision.institution_id, payload.scope)
        old = {entry.id: entry for entry in courses(db, revision)}
        nodes = nodes_for(db, payload.classification_revision_id)
        entries, id_map = [], {}
        for index, item in enumerate(payload.courses):
            if item.id is not None and item.id not in old:
                invalid(f"courses.{index}.id", "The entry does not belong to this draft")
            course = resolve_course(
                db,
                revision.institution_id,
                item.course_id,
                item.expected_course_version,
                f"courses.{index}.course_id",
            )
            entry_node(
                nodes, item.classification_node_id, f"courses.{index}.classification_node_id"
            )
            identity = item.id or uuid4()
            if item.client_ref:
                id_map[item.client_ref] = identity
            entries.append(
                AcademicCurriculumCourse(
                    id=identity,
                    logical_id=old[item.id].logical_id if item.id else uuid4(),
                    institution_id=revision.institution_id,
                    curriculum_revision_id=revision.id,
                    classification_revision_id=payload.classification_revision_id,
                    course_id=course.id,
                    course_version=course.version,
                    course_name=course.name,
                    course_code=course.code,
                    classification_node_id=item.classification_node_id,
                    requirement=item.requirement,
                    recognized_credits=item.recognized_credits,
                    position=item.position,
                )
            )
        for model in (
            AcademicCurriculumCourse,
            AcademicCurriculumDepartmentRef,
            AcademicCurriculumTrackRef,
        ):
            db.execute(delete(model).where(model.curriculum_revision_id == revision.id))
        revision.name = payload.name
        revision.curriculum_year = payload.curriculum_year
        revision.classification_revision_id = payload.classification_revision_id
        revision.scope_json = payload.scope.model_dump(mode="json")
        revision.version += 1
        revision.updated_by = actor.user.id
        revision.updated_at = datetime.now(UTC)
        db.flush()
        db.add_all(entries)
        db.add_all(
            [
                AcademicCurriculumDepartmentRef(
                    curriculum_revision_id=revision.id,
                    department_id=dep,
                    institution_id=revision.institution_id,
                )
                for dep in departments
            ]
        )
        db.add_all(
            [
                AcademicCurriculumTrackRef(
                    curriculum_revision_id=revision.id,
                    track_id=track,
                    institution_id=revision.institution_id,
                )
                for track in tracks
            ]
        )
        return view(db, revision, id_map)

    return mutate(
        db, request, revision.institution_id, payload, f"curriculum_replace:{record_id}", action
    )


def add_course(db, request, identity, record_id, payload):
    revision = scoped_record(db, identity, AcademicCurriculumRevision, record_id)

    def action(actor):
        if revision.status != "draft" or revision.version != payload.expected_version:
            raise conflict()
        classification(db, actor, revision.classification_revision_id, revision.institution_id)
        entry_node(
            nodes_for(db, revision.classification_revision_id),
            payload.classification_node_id,
            "classification_node_id",
        )
        if payload.new_course:
            # New course and its curriculum assignment commit or roll back together.
            course = Course(
                institution_id=revision.institution_id,
                **payload.new_course.model_dump(),
                created_by=actor.user.id,
                updated_by=actor.user.id,
            )
            db.add(course)
            db.flush()
        else:
            course = resolve_course(
                db,
                revision.institution_id,
                payload.course_id,
                payload.expected_course_version,
                "course_id",
            )
        existing = courses(db, revision)
        if any(row.course_id == course.id for row in existing):
            raise academic.failure("이 교육과정에 이미 연결된 과목입니다.")
        db.add(
            AcademicCurriculumCourse(
                institution_id=revision.institution_id,
                curriculum_revision_id=revision.id,
                classification_revision_id=revision.classification_revision_id,
                course_id=course.id,
                course_version=course.version,
                course_name=course.name,
                course_code=course.code,
                classification_node_id=payload.classification_node_id,
                requirement=payload.requirement,
                recognized_credits=payload.recognized_credits,
                position=max([row.position for row in existing], default=-1) + 1,
            )
        )
        revision.version += 1
        revision.updated_by = actor.user.id
        revision.updated_at = datetime.now(UTC)
        return view(db, revision)

    return mutate(
        db, request, revision.institution_id, payload, f"curriculum_entry:{record_id}", action
    )


def preview(db, identity, record_id, payload):
    revision = scoped_record(db, identity, AcademicCurriculumRevision, record_id)
    if revision.version != payload.expected_version or revision.status != "draft":
        raise conflict()
    classification(db, identity, revision.classification_revision_id, revision.institution_id)
    scope = dto.AcademicScope.model_validate(revision.scope_json)
    validate_scope(db, identity, revision.institution_id, scope)
    result = view(db, revision)
    issues = []
    if not scope.clauses:
        issues.append("적용 대상을 하나 이상 지정하세요.")
    if not result["courses"]:
        issues.append("교육과정의 과목을 하나 이상 등록하세요.")
    included = {str(row["course_id"]) for row in result["courses"]}
    if revision.revision == 1 and any(
        str(row["course_id"]) not in included for row in result["legacy_courses"]
    ):
        issues.append("기존 교육과정 과목에 학교 분류를 연결하세요. 원본 과목은 그대로 보존됩니다.")
    for row in courses(db, revision):
        resolve_course(db, revision.institution_id, row.course_id, row.course_version, "courses")
    return {
        "id": revision.id,
        "version": revision.version,
        "digest": digest(result),
        "issues": issues,
    }


def copy_revision(db, request, identity, record_id, payload):
    source = scoped_record(db, identity, AcademicCurriculumRevision, record_id)

    def action(actor):
        if source.version != payload.expected_version or source.status != "published":
            raise conflict()
        if db.scalar(
            select(AcademicCurriculumRevision.id).where(
                AcademicCurriculumRevision.lineage_id == source.lineage_id,
                AcademicCurriculumRevision.status == "draft",
            )
        ):
            raise academic.failure("작성 중인 교육과정 초안이 있습니다.")
        last = db.scalar(
            select(func.max(AcademicCurriculumRevision.revision)).where(
                AcademicCurriculumRevision.lineage_id == source.lineage_id
            )
        )
        revision = AcademicCurriculumRevision(
            institution_id=source.institution_id,
            lineage_id=source.lineage_id,
            legacy_curriculum_id=source.legacy_curriculum_id,
            classification_revision_id=source.classification_revision_id,
            revision=last + 1,
            name=source.name,
            curriculum_year=source.curriculum_year,
            scope_json=source.scope_json,
            created_by=actor.user.id,
            updated_by=actor.user.id,
        )
        db.add(revision)
        db.flush()
        for row in courses(db, source):
            db.add(
                AcademicCurriculumCourse(
                    logical_id=row.logical_id,
                    institution_id=row.institution_id,
                    curriculum_revision_id=revision.id,
                    classification_revision_id=row.classification_revision_id,
                    course_id=row.course_id,
                    course_version=row.course_version,
                    course_name=row.course_name,
                    course_code=row.course_code,
                    classification_node_id=row.classification_node_id,
                    requirement=row.requirement,
                    recognized_credits=row.recognized_credits,
                    position=row.position,
                )
            )
        for model, key in [
            (AcademicCurriculumDepartmentRef, "department_id"),
            (AcademicCurriculumTrackRef, "track_id"),
        ]:
            for ref in db.scalars(select(model).where(model.curriculum_revision_id == source.id)):
                db.add(
                    model(
                        curriculum_revision_id=revision.id,
                        institution_id=revision.institution_id,
                        **{key: getattr(ref, key)},
                    )
                )
        return view(db, revision)

    return mutate(
        db, request, source.institution_id, payload, f"curriculum_copy:{record_id}", action
    )


def publish(db, request, identity, record_id, payload):
    revision = scoped_record(db, identity, AcademicCurriculumRevision, record_id)

    def action(actor):
        result = preview(db, actor, record_id, payload)
        if result["issues"] or result["digest"] != payload.expected_digest:
            raise academic.failure("적용 대상과 과목 연결을 확인한 뒤 다시 게시하세요.")
        revision.status = "published"
        revision.published_by = actor.user.id
        revision.published_at = datetime.now(UTC)
        revision.digest = payload.expected_digest
        revision.review_note = payload.review_note
        revision.updated_by = actor.user.id
        revision.updated_at = datetime.now(UTC)
        revision.version += 1
        return view(db, revision)

    return mutate(
        db, request, revision.institution_id, payload, f"curriculum_publish:{record_id}", action
    )
