"""Administrators link a school to a bundle; students read only their school's bundle."""

from datetime import UTC, datetime

from app.core.auth_errors import conflict, forbidden
from app.models.guidance_bindings import AcademicGuidanceBinding
from app.models.identity import Role
from app.models.personal import PlanningProfile
from app.rag.guidance.bundles import bundles
from app.schemas.guidance_bindings import GuidanceBindingView, StudentGuidanceBinding
from app.services import academic, auth

ADMIN_ROLES = (Role.SUPER_ADMIN, Role.SCHOOL_ADMIN)


def require_admin(identity):
    if identity.user.role not in ADMIN_ROLES:
        raise forbidden()


def list_bundles(db, request):
    require_admin(auth.current_identity(request, db))
    return {"items": list(bundles().values()), "next_cursor": None}


def present(institution_id, row):
    if row is None:
        return GuidanceBindingView(institution_id=institution_id, state="unbound", version=0)
    bundle = bundles().get(row.bundle_id)
    return GuidanceBindingView(
        institution_id=institution_id,
        state="bound" if bundle else "unavailable",
        version=row.version,
        bundle_id=row.bundle_id,
        bound_edition=row.edition,
        bundle=bundle,
        edition_changed=bool(bundle) and bundle["edition"] != row.edition,
        updated_by=row.updated_by,
        updated_at=row.updated_at,
    )


def read(db, request, institution_id):
    identity = auth.current_identity(request, db)
    require_admin(identity)
    academic.school(db, identity, institution_id)
    return present(institution_id, db.get(AcademicGuidanceBinding, institution_id))


def save(db, request, institution_id, payload):
    identity = academic.lock_actor(db, request)
    require_admin(identity)
    school = academic.school(db, identity, institution_id)
    row = db.get(AcademicGuidanceBinding, institution_id, with_for_update=True)
    if (row.version if row else 0) != payload.expected_version:
        raise conflict()
    bundle = bundles().get(payload.bundle_id)
    if bundle is None or bundle["availability"] != "available":
        raise academic.failure("연결할 수 있는 안내 자료가 아닙니다.", 404)
    if bundle["edition"] != payload.edition:
        raise academic.failure("자료 판본이 바뀌었습니다. 목록을 다시 조회해 확인하세요.")
    now = datetime.now(UTC)
    if row is None:
        row = AcademicGuidanceBinding(
            institution_id=institution_id,
            bundle_id=payload.bundle_id,
            edition=payload.edition,
            version=1,
            created_by=identity.user.id,
            updated_by=identity.user.id,
        )
        db.add(row)
    else:
        row.bundle_id, row.edition = payload.bundle_id, payload.edition
        row.version += 1
        row.updated_by, row.updated_at = identity.user.id, now
    db.flush()
    academic.audit(db, identity, "institution", "guidance_bind", school, request)
    academic.commit(db)
    return present(institution_id, row)


def remove(db, request, institution_id, expected_version):
    identity = academic.lock_actor(db, request)
    require_admin(identity)
    school = academic.school(db, identity, institution_id)
    row = db.get(AcademicGuidanceBinding, institution_id, with_for_update=True)
    if row is None or row.version != expected_version:
        raise conflict()
    db.delete(row)
    academic.audit(db, identity, "institution", "guidance_unbind", school, request)
    academic.commit(db)
    return present(institution_id, None)


def resolve(db, identity, institution_id=None):
    """Return the student-facing state and the bundle to serve for this request."""
    profile = db.get(PlanningProfile, identity.user.id)
    registered = profile.institution_id if profile else None
    if institution_id is None:
        institution_id = registered
    elif identity.user.role in ADMIN_ROLES:
        # Administrators may preview a school inside their own scope.
        academic.school(db, identity, institution_id)
    elif institution_id != registered:
        raise academic.failure("등록한 학교의 안내 자료만 조회할 수 있습니다.", 404)
    if institution_id is None:
        return StudentGuidanceBinding(state="school_required"), None
    view = present(institution_id, db.get(AcademicGuidanceBinding, institution_id))
    bundle = view.bundle if view.state == "bound" else None
    return (
        StudentGuidanceBinding(state=view.state, institution_id=institution_id, bundle=bundle),
        bundle,
    )


def student_binding(db, request, institution_id=None):
    identity = auth.current_identity(request, db)
    return resolve(db, identity, institution_id)[0]
