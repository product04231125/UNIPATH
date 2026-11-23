"""Saved 자기소개서·포트폴리오 drafts: owner-only, versioned, never sent to a model from here.

A saved document keeps what the student asked for (`input`), the edited sections with the
citations generation found (`draft`) and record titles for showing those citations (`labels`), so
it can be reopened, edited and exported again.
"""

import json
from datetime import UTC, datetime
from typing import Annotated
from uuid import UUID

from pydantic import Field, StringConstraints
from sqlalchemy import func, select

from app.core.auth_errors import AuthError, conflict
from app.models.personal import WritingDocument
from app.schemas.common import ErrorCode
from app.services.access import locked_identity
from app.services.personal import commit

from .contracts import Label, StoredDraft, Strict, WritingRequest

MAX_DOCUMENTS = 50
MAX_CONTENT_CHARS = 200_000
LabelKey = Annotated[str, StringConstraints(min_length=1, max_length=64)]
LabelText = Annotated[str, StringConstraints(max_length=200)]


class WritingInput(WritingRequest):
    """The generation form as the student filled it in; consent is never stored."""


class WritingDocumentData(Strict):
    title: Label
    input: WritingInput
    draft: StoredDraft
    labels: dict[LabelKey, LabelText] = Field(default_factory=dict, max_length=300)


class WritingDocumentUpdate(WritingDocumentData):
    expected_version: int = Field(ge=1, strict=True)


class WritingDocumentSummary(Strict):
    id: UUID
    title: str
    document_type: str
    version: int
    updated_at: datetime


class WritingDocumentView(WritingDocumentSummary):
    created_at: datetime
    input: dict
    draft: dict
    labels: dict[str, str]


class WritingDocumentList(Strict):
    items: list[WritingDocumentSummary]


def missing():
    return AuthError(404, ErrorCode.NOT_FOUND, "저장한 문서를 찾을 수 없습니다.")


def content(payload):
    value = {
        "input": payload.input.model_dump(mode="json", exclude={"external_processing_consent"}),
        "draft": payload.draft.model_dump(mode="json"),
        "labels": dict(payload.labels),
    }
    if len(json.dumps(value, ensure_ascii=False)) > MAX_CONTENT_CHARS:
        raise AuthError(
            422, ErrorCode.VALIDATION_ERROR, "문서가 너무 깁니다. 공고·원문을 줄여 주세요."
        )
    return value


def summary(item):
    return WritingDocumentSummary(
        id=item.id,
        title=item.title,
        document_type=item.document_type,
        version=item.version,
        updated_at=item.updated_at,
    )


def view(item):
    return WritingDocumentView(
        **summary(item).model_dump(),
        created_at=item.created_at,
        input=item.content["input"],
        draft=item.content["draft"],
        labels=item.content.get("labels", {}),
    )


def owned(db, owner_id, document_id):
    item = db.scalar(
        select(WritingDocument).where(
            WritingDocument.id == document_id, WritingDocument.owner_id == owner_id
        )
    )
    if item is None:
        raise missing()
    return item


def list_documents(db, owner_id):
    rows = db.scalars(
        select(WritingDocument)
        .where(WritingDocument.owner_id == owner_id)
        .order_by(WritingDocument.updated_at.desc(), WritingDocument.id)
    )
    return WritingDocumentList(items=[summary(item) for item in rows])


def get_document(db, owner_id, document_id):
    return view(owned(db, owner_id, document_id))


def create_document(db, request, payload):
    identity = locked_identity(db, request)
    count = db.scalar(
        select(func.count())
        .select_from(WritingDocument)
        .where(WritingDocument.owner_id == identity.user.id)
    )
    if count >= MAX_DOCUMENTS:
        raise AuthError(
            409,
            ErrorCode.CONFLICT,
            f"문서는 {MAX_DOCUMENTS}개까지 저장할 수 있습니다. 쓰지 않는 문서를 지워 주세요.",
        )
    item = WritingDocument(
        owner_id=identity.user.id,
        title=payload.title,
        document_type=payload.input.document_type,
        content=content(payload),
        version=1,
    )
    db.add(item)
    commit(db)
    db.refresh(item)
    return view(item)


def update_document(db, request, document_id, payload):
    identity = locked_identity(db, request)
    item = owned(db, identity.user.id, document_id)
    if item.version != payload.expected_version:
        raise conflict()
    item.title = payload.title
    item.document_type = payload.input.document_type
    item.content = content(payload)
    item.version += 1
    item.updated_at = datetime.now(UTC)
    commit(db)
    db.refresh(item)
    return view(item)


def delete_document(db, request, document_id, expected_version):
    identity = locked_identity(db, request)
    item = owned(db, identity.user.id, document_id)
    if item.version != expected_version:
        raise conflict()
    db.delete(item)
    commit(db)
