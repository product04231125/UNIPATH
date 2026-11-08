"""Authenticated student projection of published administrator academic documents."""

from uuid import UUID

from fastapi import APIRouter, Request

from app.api.auth import CurrentIdentity, Database
from app.schemas import student_academic as dto
from app.services import student_academic as service
from app.services.student_academic_progress import progress

router = APIRouter(tags=["student academic requirements"])


@router.get("/catalog/academic/options", response_model=dto.StudentAcademicOptions)
def options(institution_id: UUID, db: Database, identity: CurrentIdentity):
    return service.options(db, institution_id)


@router.get("/me/academic-contexts", response_model=dto.StudentAcademicWorkspaceView)
def contexts(db: Database, identity: CurrentIdentity):
    return service.read_contexts(db, identity.user.id)


@router.put("/me/academic-contexts", response_model=dto.StudentAcademicWorkspaceView)
def save_contexts(
    payload: dto.StudentAcademicContextsSave,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return service.save_contexts(db, request, payload)


@router.get("/me/academic-requirements/preview", response_model=dto.StudentAcademicPreview)
def preview(db: Database, identity: CurrentIdentity):
    return service.preview_data(db, identity.user.id)[1]


@router.post("/me/academic-requirements/activate", response_model=dto.StudentAcademicRequirements)
def activate(
    payload: dto.StudentAcademicActivate, request: Request, db: Database, identity: CurrentIdentity
):
    return service.activate(db, request, payload)


@router.get("/me/academic-requirements", response_model=dto.StudentAcademicRequirements)
def requirements(db: Database, identity: CurrentIdentity):
    return service.read_requirements(db, identity.user.id)


@router.get("/me/academic-requirements/history", response_model=dto.StudentAcademicHistory)
def history(db: Database, identity: CurrentIdentity):
    return service.history(db, identity.user.id)


@router.get(
    "/me/academic-requirements/history/{activation_id}",
    response_model=dto.StudentAcademicRequirements,
)
def historical(activation_id: UUID, db: Database, identity: CurrentIdentity):
    return service.read_requirements(db, identity.user.id, activation_id)


@router.put(
    "/me/academic-requirements/{revision_id}/responses/{item_id}",
    response_model=dto.StudentAcademicRequirements,
)
def response(
    revision_id: UUID,
    item_id: UUID,
    payload: dto.StudentAcademicResponseSave,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return service.save_response(db, request, revision_id, item_id, payload)


@router.put(
    "/me/course-records/{record_id}/academic-link", response_model=dto.StudentAcademicCourseView
)
def course_link(
    record_id: UUID,
    payload: dto.StudentAcademicCourseSave,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return service.save_course_link(db, request, record_id, payload)


@router.get("/me/academic-credit-progress", response_model=dto.StudentAcademicCreditProgress)
def credit_progress(db: Database, identity: CurrentIdentity):
    return progress(db, identity.user.id)
