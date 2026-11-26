"""Administrator-managed transcript-category wiring, separate from immutable criteria."""

from datetime import UTC, datetime

from sqlalchemy import select

from app.core.auth_errors import conflict
from app.models.academic_workspace import AcademicCreditRecordBinding as Binding
from app.models.academic_workspace import AcademicRequirementRevision
from app.schemas.academic_requirements import CreditRecordBindingView
from app.services.academic_workspace import invalid, mutate, scoped_record


def requirement(db, identity, revision_id):
    revision = scoped_record(db, identity, AcademicRequirementRevision, revision_id)
    if revision.kind != "credit_table":
        invalid("requirement_revision_id", "학점표의 이수구분 연결만 설정할 수 있습니다.")
    return revision


def view(db, revision):
    binding = db.get(Binding, revision.id)
    return CreditRecordBindingView(
        requirement_revision_id=revision.id,
        institution_id=revision.institution_id,
        version=binding.version if binding else 0,
        bindings=binding.bindings_json if binding else {},
    ).model_dump(mode="json")


def replace_data(db, actor, revision, payload):
    if revision.status == "withdrawn":
        invalid("requirement_revision_id", "철회된 학점표의 연결은 수정할 수 없습니다.")
    current = db.scalar(
        select(Binding)
        .where(Binding.requirement_revision_id == revision.id)
        .with_for_update()
        .execution_options(populate_existing=True)
    )
    if (current.version if current else 0) != payload.expected_version:
        raise conflict()
    parents = {h.get("parent_id") for h in revision.content_json["headers"] if h.get("parent_id")}
    leaves = {
        h["id"]
        for h in revision.content_json["headers"]
        if h["id"] not in parents and h.get("role") != "group"
    }
    if any(str(header_id) not in leaves for header_id in payload.bindings):
        invalid("bindings", "현재 학점표의 숫자 열을 선택하세요.")
    if current is None:
        current = Binding(
            requirement_revision_id=revision.id, institution_id=revision.institution_id, version=0
        )
        db.add(current)
    current.bindings_json = {str(key): list(value) for key, value in payload.bindings.items()}
    current.version += 1
    current.updated_by, current.updated_at = actor.user.id, datetime.now(UTC)
    db.flush()
    return view(db, revision)


def replace(db, request, identity, revision_id, payload):
    revision = requirement(db, identity, revision_id)
    return mutate(
        db,
        request,
        revision.institution_id,
        payload,
        f"credit_record_binding:{revision_id}",
        lambda actor: replace_data(db, actor, revision, payload),
    )


def copy_data(db, source, target, actor):
    original = db.get(Binding, source.id)
    if original:
        db.add(
            Binding(
                requirement_revision_id=target.id,
                institution_id=target.institution_id,
                version=1,
                bindings_json={key: list(value) for key, value in original.bindings_json.items()},
                updated_by=actor.user.id,
            )
        )
