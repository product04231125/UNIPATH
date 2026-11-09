"""Scoped, atomic revision writes with replay-safe administrator receipts."""

import hashlib
import json
from datetime import UTC, datetime
from uuid import uuid4

from fastapi.exceptions import RequestValidationError
from sqlalchemy import delete, func, select
from sqlalchemy.exc import IntegrityError

from app.core.auth_errors import conflict, forbidden
from app.models.academic_workspace import (
    AcademicMutationReceipt,
    ClassificationNode,
    ClassificationRevision,
    StudyTrack,
)
from app.models.identity import Role
from app.schemas import academic_workspace as dto
from app.services import academic, access


def digest(value):
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(encoded.encode()).hexdigest()


def require_school(db, identity, institution_id):
    if identity.user.role not in (Role.SUPER_ADMIN, Role.SCHOOL_ADMIN):
        raise forbidden()
    academic.school(db, identity, institution_id)


def invalid(field, reason):
    raise RequestValidationError([{"loc": ("body", field), "msg": reason, "type": "value_error"}])


def scoped_record(db, identity, model, record_id):
    item = db.get(model, record_id)
    if item is None:
        raise academic.failure("요청한 기준을 찾을 수 없습니다.", 404)
    require_school(db, identity, item.institution_id)
    return item


def mutate(db, request, institution_id, payload, operation, action):
    identity = access.locked_identity(db, request)
    require_school(db, identity, institution_id)
    request_hash = digest({"operation": operation, "body": payload.model_dump(mode="json")})
    prior = db.get(AcademicMutationReceipt, (identity.user.id, payload.client_id))
    if prior:
        if prior.operation != operation or prior.request_digest != request_hash:
            raise conflict()
        return prior.response_json
    try:
        response = action(identity)
        # Persist a complete JSON response in the same transaction as the mutation.
        db.add(
            AcademicMutationReceipt(
                actor_id=identity.user.id,
                client_id=payload.client_id,
                institution_id=institution_id,
                operation=operation,
                request_digest=request_hash,
                response_json=response,
            )
        )
        access.audit(
            db,
            identity.user.id,
            "academic:" + operation.split(":")[0],
            institution_id,
            request.state.request_id,
            institution_id,
        )
        db.commit()
        return response
    except IntegrityError:
        db.rollback()
        raise conflict() from None


def classification_nodes(db, revision):
    return list(
        db.scalars(
            select(ClassificationNode)
            .where(ClassificationNode.revision_id == revision.id)
            .order_by(ClassificationNode.position, ClassificationNode.id)
        )
    )


def classification_view(db, revision, id_map=None):
    db.flush()
    return dto.ClassificationView(
        **dto.ClassificationHeader.model_validate(revision).model_dump(),
        nodes=[
            dto.ClassificationNodeView.model_validate(n) for n in classification_nodes(db, revision)
        ],
        id_map=id_map or {},
    ).model_dump(mode="json")


def classification_list(db, identity, institution_id, status, cursor, limit):
    require_school(db, identity, institution_id)
    statement = select(ClassificationRevision).where(
        ClassificationRevision.institution_id == institution_id
    )
    if status:
        statement = statement.where(ClassificationRevision.status == status)
    if cursor:
        statement = statement.where(ClassificationRevision.id > cursor)
    rows = list(db.scalars(statement.order_by(ClassificationRevision.id).limit(limit + 1)))
    return {"items": rows[:limit], "next_cursor": rows[limit - 1].id if len(rows) > limit else None}


def create_classification(db, request, payload):
    def create(identity):
        source = (
            scoped_record(db, identity, ClassificationRevision, payload.copy_from_id)
            if payload.copy_from_id
            else None
        )
        if source and source.institution_id != payload.institution_id:
            invalid("copy_from_id", "Copy from the same school")
        existing = db.scalar(
            select(ClassificationRevision.id).where(
                ClassificationRevision.institution_id == payload.institution_id,
                ClassificationRevision.status == "draft",
            )
        )
        if existing:
            raise academic.failure("작성 중인 학교 분류가 있습니다. 해당 초안을 이어서 편집하세요.")
        last = db.scalar(
            select(func.max(ClassificationRevision.revision)).where(
                ClassificationRevision.institution_id == payload.institution_id
            )
        )
        revision = ClassificationRevision(
            id=uuid4(),
            institution_id=payload.institution_id,
            revision=(last or 0) + 1,
            created_by=identity.user.id,
            updated_by=identity.user.id,
        )
        db.add(revision)
        db.flush()
        if source:
            nodes = classification_nodes(db, source)
            new_ids = {n.id: uuid4() for n in nodes}
            for node in nodes:
                db.add(
                    ClassificationNode(
                        id=new_ids[node.id],
                        institution_id=revision.institution_id,
                        revision_id=revision.id,
                        logical_id=node.logical_id,
                        parent_id=new_ids.get(node.parent_id),
                        label=node.label,
                        position=node.position,
                        selectable=node.selectable,
                    )
                )
        return classification_view(db, revision)

    return mutate(db, request, payload.institution_id, payload, "classification_create", create)


def replace_classification(db, request, identity, record_id, payload):
    revision = scoped_record(db, identity, ClassificationRevision, record_id)

    def replace(fresh_identity):
        # locked_identity expires the dependency-time object before checking its version.
        if revision.version != payload.expected_version or revision.status != "draft":
            raise conflict()
        old = {node.id: node for node in classification_nodes(db, revision)}
        ids, logical_ids = {}, {}
        for index, node in enumerate(payload.nodes):
            if node.id is not None and node.id not in old:
                invalid(f"nodes.{index}.id", "The node does not belong to this revision")
            ids[node.key] = node.id or uuid4()
            logical_ids[node.key] = old[node.id].logical_id if node.id else uuid4()
        # Published revisions cannot be changed and cannot reference draft nodes.
        db.execute(delete(ClassificationNode).where(ClassificationNode.revision_id == revision.id))
        for node in payload.nodes:
            db.add(
                ClassificationNode(
                    id=ids[node.key],
                    logical_id=logical_ids[node.key],
                    institution_id=revision.institution_id,
                    revision_id=revision.id,
                    parent_id=ids.get(node.parent_ref),
                    label=node.label,
                    position=node.position,
                    selectable=node.selectable,
                )
            )
        revision.version += 1
        revision.updated_by = fresh_identity.user.id
        revision.updated_at = datetime.now(UTC)
        return classification_view(
            db, revision, {n.client_ref: ids[n.key] for n in payload.nodes if n.client_ref}
        )

    return mutate(
        db,
        request,
        revision.institution_id,
        payload,
        f"classification_replace:{record_id}",
        replace,
    )


def preview_classification(db, identity, record_id, payload):
    revision = scoped_record(db, identity, ClassificationRevision, record_id)
    if revision.version != payload.expected_version or revision.status != "draft":
        raise conflict()
    view = classification_view(db, revision)
    return {
        "id": revision.id,
        "version": revision.version,
        "digest": digest(view),
        "issues": [] if view["nodes"] else ["분류 항목을 하나 이상 작성하세요."],
    }


def publish_classification(db, request, identity, record_id, payload):
    revision = scoped_record(db, identity, ClassificationRevision, record_id)

    def publish(fresh_identity):
        preview = preview_classification(db, fresh_identity, record_id, payload)
        if preview["issues"] or preview["digest"] != payload.expected_digest:
            raise academic.failure("미리보기 이후 기준이 변경됐거나 미완성입니다. 다시 확인하세요.")
        revision.status = "published"
        revision.published_at = datetime.now(UTC)
        revision.published_by = fresh_identity.user.id
        revision.digest = payload.expected_digest
        revision.review_note = payload.review_note
        revision.updated_by = fresh_identity.user.id
        revision.updated_at = datetime.now(UTC)
        revision.version += 1
        return classification_view(db, revision)

    return mutate(
        db,
        request,
        revision.institution_id,
        payload,
        f"classification_publish:{record_id}",
        publish,
    )


def track_list(db, identity, institution_id, cursor, limit):
    require_school(db, identity, institution_id)
    statement = select(StudyTrack).where(StudyTrack.institution_id == institution_id)
    if cursor:
        statement = statement.where(StudyTrack.id > cursor)
    rows = list(db.scalars(statement.order_by(StudyTrack.id).limit(limit + 1)))
    return {"items": rows[:limit], "next_cursor": rows[limit - 1].id if len(rows) > limit else None}


def save_track(db, request, identity, payload, record_id=None):
    track = scoped_record(db, identity, StudyTrack, record_id) if record_id else None
    institution_id = track.institution_id if track else payload.institution_id

    def save(fresh_identity):
        nonlocal track
        if track:
            if track.version != payload.expected_version:
                raise conflict()
            track.version += 1
            track.inactive_at = datetime.now(UTC) if payload.inactive else None
            track.updated_at = datetime.now(UTC)
        else:
            track = StudyTrack(
                institution_id=institution_id,
                created_by=fresh_identity.user.id,
                version=1,
            )
            db.add(track)
        track.name = payload.name
        track.updated_by = fresh_identity.user.id
        db.flush()
        return dto.TrackView.model_validate(track).model_dump(mode="json")

    return mutate(
        db,
        request,
        institution_id,
        payload,
        f"track_update:{record_id}" if record_id else "track_create",
        save,
    )
