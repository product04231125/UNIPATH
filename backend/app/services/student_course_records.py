"""Course selection and progress links share the personal record transaction."""

from datetime import UTC, datetime

from sqlalchemy import select

from app.models.academic_workspace import AcademicCurriculumCourse, AcademicCurriculumRevision
from app.models.personal import CourseRecord
from app.models.student_academic import StudentAcademicCourseLink as Link
from app.services import student_academic as academic
from app.services.academic_workspace import invalid


def links(db, record):
    return list(
        db.scalars(
            select(Link).where(Link.owner_id == record.owner_id, Link.course_record_id == record.id)
        )
    )


def reference(db, record):
    values = links(db, record)
    link = values[0] if len(values) == 1 else None
    return {
        "academic_context_id": link.context_id if link else None,
        "academic_entry_id": link.entry_id if link else None,
    }


def sync(db, record, context_id, entry_id, *, clear=False):
    existing = links(db, record)
    if context_id is None:
        if clear:
            for link in existing:
                db.delete(link)
            db.flush()
            return
        # No school selection: preserve free-form record and any older multi-major links.
        selected = existing
    else:
        context = academic.personal.get(db, record.owner_id, academic.Context, context_id)
        entry = db.get(AcademicCurriculumCourse, entry_id)
        revision = db.get(AcademicCurriculumRevision, context.curriculum_revision_id)
        retained = any(
            link.context_id == context_id and link.entry_id == entry_id for link in existing
        )
        if (
            (
                not retained
                and (
                    not context.active
                    or academic.context_issues(db, record.owner_id)
                    or revision.status != "published"
                )
            )
            or entry is None
            or entry.curriculum_revision_id != context.curriculum_revision_id
        ):
            invalid("academic_entry_id", "현재 학업 기준의 교육과정 과목을 선택하세요.")
        selected = [link for link in existing if link.context_id == context_id]
        if not selected:
            link = Link(
                owner_id=record.owner_id,
                course_record_id=record.id,
                context_id=context_id,
                entry_id=entry_id,
                version=0,
            )
            db.add(link)
            selected = [link]
        for link in existing:
            if link not in selected:
                db.delete(link)
        selected[0].entry_id = entry_id
    for link in selected:
        link.result = (
            "completed"
            if record.completion == "recorded"
            else "not_completed"
            if record.completion == "not_completed"
            else "needs_review"
        )
        link.earned_credits = (
            record.credits
            if record.completion == "recorded"
            else (0 if record.completion == "not_completed" else None)
        )
        link.record_version = record.version
        link.included = True
        link.version += 1
    db.flush()


def resolve(db, owner):
    """Only exact, unique school codes link automatically; never match titles."""
    if academic.context_issues(db, owner):
        invalid("contexts", "학업 기준을 먼저 확인하세요.")
    candidates = {}
    for context in academic.contexts(db, owner):
        for entry in db.scalars(
            select(AcademicCurriculumCourse).where(
                AcademicCurriculumCourse.curriculum_revision_id == context.curriculum_revision_id
            )
        ):
            if entry.course_code.strip():
                candidates.setdefault(entry.course_code.strip(), []).append((context.id, entry.id))
    linked, unresolved = 0, []
    for record in academic.rows(db, CourseRecord, owner):
        existing = links(db, record)
        if existing:
            sync(
                db,
                record,
                **{k.replace("academic_", ""): v for k, v in reference(db, record).items()},
            )
            continue
        choices = (
            candidates.get(record.course_code.strip(), []) if record.course_code.strip() else []
        )
        if len(choices) != 1:
            unresolved.append(
                {"record_id": record.id, "reason": "ambiguous" if choices else "no_match"}
            )
            continue
        record.version += 1
        record.updated_at = datetime.now(UTC)
        sync(db, record, *choices[0])
        linked += 1
    return {"owner_id": owner, "linked_count": linked, "unresolved": unresolved}
