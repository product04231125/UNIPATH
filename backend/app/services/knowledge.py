"""Administrator-scoped extraction storage, explicit review and terminal revocation."""

import hashlib
from datetime import UTC, datetime
from uuid import uuid5

from sqlalchemy import delete, exists, func, select
from sqlalchemy.exc import IntegrityError

from app.core.auth_errors import AuthError, conflict, forbidden
from app.models.academic import OfficialDocument
from app.models.identity import AdminScope, Institution, Role
from app.models.knowledge import KnowledgeChunk, KnowledgeDocument
from app.rag.school.retriever import validate_chunks
from app.schemas import knowledge as dto
from app.schemas.common import ErrorCode
from app.services import academic, access


def invalid(message="문서 원본·추출 내용·적용 범위와 검토 상태를 확인해 주세요."):
    return AuthError(422, ErrorCode.VALIDATION_ERROR, message)


def listing(
    db, identity, institution_id=None, status=None, source_document_id=None, cursor=None, limit=100
):
    if identity.user.role not in (Role.SUPER_ADMIN, Role.SCHOOL_ADMIN):
        raise forbidden()
    statement = select(KnowledgeDocument).join(Institution).where(Institution.deleted_at.is_(None))
    if institution_id:
        academic.school(db, identity, institution_id)
        statement = statement.where(KnowledgeDocument.institution_id == institution_id)
    if identity.user.role == Role.SCHOOL_ADMIN:
        statement = statement.where(
            exists().where(
                AdminScope.user_id == identity.user.id,
                AdminScope.institution_id == KnowledgeDocument.institution_id,
                AdminScope.status == "active",
            )
        )
    if status:
        statement = statement.where(KnowledgeDocument.status == status)
    if source_document_id:
        statement = statement.where(KnowledgeDocument.source_document_id == source_document_id)
    if cursor:
        statement = statement.where(KnowledgeDocument.id > cursor)
    return list(db.scalars(statement.order_by(KnowledgeDocument.id).limit(limit + 1)))


def read(db, identity, record_id):
    return academic.read(db, identity, KnowledgeDocument, record_id)


def mutate(db, request, record_id, expected_version, *, status="draft"):
    identity = access.locked_identity(db, request)
    item = read(db, identity, record_id)
    if item.version != expected_version or item.status != status:
        raise conflict()
    source = academic.read(db, identity, OfficialDocument, item.source_document_id)
    if source.status != "applied" or source.version != item.source_document_version:
        raise conflict()
    return identity, item, source


def audit(db, identity, action, item, request):
    access.audit(
        db,
        identity.user.id,
        "knowledge:" + action,
        item.id,
        request.state.request_id,
        item.institution_id,
    )


def touched(item, identity):
    item.version += 1
    item.updated_by, item.updated_at = identity.user.id, datetime.now(UTC)


def create(db, request, payload):
    identity = access.locked_identity(db, request)
    source = academic.read(db, identity, OfficialDocument, payload.source_document_id)
    if source.status != "applied" or source.version != payload.expected_source_version:
        raise conflict()
    if payload.source_checked_on > datetime.now(UTC).date():
        raise invalid("출처 확인일은 미래 날짜로 지정할 수 없습니다.")
    item = KnowledgeDocument(
        source_document_id=source.id,
        source_document_version=source.version,
        institution_id=source.institution_id,
        department_id=source.department_id,
        curriculum_id=source.curriculum_id,
        name=source.name,
        document_hash=payload.document_hash,
        page_count=payload.page_count,
        extractor_version=payload.extractor_version,
        source_checked_on=payload.source_checked_on,
        created_by=identity.user.id,
        updated_by=identity.user.id,
    )
    db.add(item)
    # Use the common safe conflict response for duplicate source registrations.
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise conflict() from None
    audit(db, identity, "create", item, request)
    academic.commit(db)
    return item


def chunks(db, record_id, page=None):
    statement = select(KnowledgeChunk).where(KnowledgeChunk.knowledge_document_id == record_id)
    if page is not None:
        statement = statement.where(KnowledgeChunk.page == page)
    return list(db.scalars(statement.order_by(KnowledgeChunk.page, KnowledgeChunk.part_index)))


def page_view(item, rows):
    if not rows:
        raise academic.failure("페이지를 찾을 수 없습니다.", 404)
    return dto.PageView(
        knowledge_document_id=item.id,
        version=item.version,
        page=rows[0].page,
        page_hash=rows[0].page_hash,
        is_blank=rows[0].is_blank,
        parts=[dto.ChunkView.model_validate(row) for row in rows if not row.is_blank],
    )


def pages(db, item, cursor, limit):
    statement = select(
        KnowledgeChunk.page.label("page"),
        func.count().filter(KnowledgeChunk.is_blank.is_(False)).label("part_count"),
        func.sum(func.char_length(KnowledgeChunk.content)).label("character_count"),
        func.min(KnowledgeChunk.page_hash).label("page_hash"),
        func.bool_and(KnowledgeChunk.is_blank).label("is_blank"),
    ).where(KnowledgeChunk.knowledge_document_id == item.id)
    if cursor:
        statement = statement.where(KnowledgeChunk.page > cursor)
    return list(
        db.execute(
            statement.group_by(KnowledgeChunk.page).order_by(KnowledgeChunk.page).limit(limit + 1)
        ).mappings()
    )


def replace_page(db, request, record_id, page, payload):
    identity, item, _ = mutate(db, request, record_id, payload.expected_version)
    if page > item.page_count:
        raise invalid("문서의 전체 페이지 범위를 확인해 주세요.")
    content = "".join(part.content for part in payload.parts)
    digest = hashlib.sha256(content.encode()).hexdigest()
    db.execute(
        delete(KnowledgeChunk).where(
            KnowledgeChunk.knowledge_document_id == item.id, KnowledgeChunk.page == page
        )
    )
    offset = 0
    if payload.is_blank:
        db.add(
            KnowledgeChunk(
                id=uuid5(item.id, f"{page}:0"),
                knowledge_document_id=item.id,
                institution_id=item.institution_id,
                page=page,
                part_index=0,
                part_count=1,
                character_start=0,
                character_end=0,
                content="",
                is_blank=True,
                content_hash=digest,
                page_hash=digest,
                admission_years=None,
                tracks=None,
                warnings=[],
            )
        )
    for index, part in enumerate(payload.parts):
        db.add(
            KnowledgeChunk(
                id=uuid5(item.id, f"{page}:{index}"),
                knowledge_document_id=item.id,
                institution_id=item.institution_id,
                page=page,
                part_index=index,
                part_count=len(payload.parts),
                character_start=offset,
                character_end=offset + len(part.content),
                content=part.content,
                is_blank=False,
                content_hash=hashlib.sha256(part.content.encode()).hexdigest(),
                page_hash=digest,
                admission_years=sorted(part.admission_years) if part.admission_years else None,
                tracks=sorted(part.tracks) if part.tracks else None,
                warnings=part.warnings,
            )
        )
        offset += len(part.content)
    touched(item, identity)
    db.flush()
    response = page_view(item, chunks(db, item.id, page))
    audit(db, identity, "replace_page", item, request)
    academic.commit(db)
    return response


def remove_page(db, request, record_id, page, expected_version):
    identity, item, _ = mutate(db, request, record_id, expected_version)
    if not chunks(db, item.id, page):
        raise academic.failure("페이지를 찾을 수 없습니다.", 404)
    db.execute(
        delete(KnowledgeChunk).where(
            KnowledgeChunk.knowledge_document_id == item.id, KnowledgeChunk.page == page
        )
    )
    touched(item, identity)
    audit(db, identity, "delete_page", item, request)
    academic.commit(db)


def rag_chunks(item, source, rows, institution, department):
    """Project persisted review facts to the team's existing extraction contract."""
    return [
        {
            "schema_version": "2.0",
            "chunk_id": str(row.id),
            "document_id": str(source.id),
            "title": source.name,
            "source_file": "catalog:" + str(source.id),
            "source_url": source.source_url,
            "institution": institution,
            "department": department,
            "page": row.page,
            "document_page_count": item.page_count,
            "document_hash": item.document_hash,
            "reviewed_blank_pages": sorted({r.page for r in rows if r.is_blank}),
            "content": row.content,
            "content_hash": row.content_hash,
            "page_content_hash": row.page_hash,
            "page_part_index": row.part_index,
            "page_part_count": row.part_count,
            "source_character_start": row.character_start,
            "source_character_end": row.character_end,
            "admission_years": row.admission_years,
            "tracks": row.tracks,
            "warnings": row.warnings,
            "review_status": "approved" if item.status == "approved" else "needs_review",
            "applicability_status": "verified" if item.status == "approved" else "unverified",
            "eligible_for_official_answers": item.status == "approved",
        }
        for row in rows
        if not row.is_blank
    ]


def approve(db, request, record_id, payload):
    identity, item, source = mutate(db, request, record_id, payload.expected_version)
    if payload.reviewed_document_hash != item.document_hash:
        raise conflict()
    rows = chunks(db, item.id)
    if {row.page for row in rows} != set(range(1, item.page_count + 1)):
        raise invalid("모든 원본 페이지의 추출 내용을 먼저 등록해 주세요.")
    if not any(not row.is_blank for row in rows):
        raise invalid("검색할 본문이 있는 문서를 등록해 주세요.")
    if any(
        not row.admission_years or not row.tracks or row.warnings
        for row in rows
        if not row.is_blank
    ):
        raise invalid("모든 청크의 입학연도·이수경로를 검토하고 추출 경고를 해결해 주세요.")
    try:
        # This also verifies complete v2 page parts, offsets and reconstruction hashes.
        validate_chunks(rag_chunks(item, source, rows, "검증용 학교", "검증용 학과"))
    except (ValueError, KeyError, TypeError):
        raise invalid() from None
    item.status, item.approved_by, item.approved_at = (
        "approved",
        identity.user.id,
        datetime.now(UTC),
    )
    item.review_note = payload.review_note
    touched(item, identity)
    audit(db, identity, "approve", item, request)
    academic.commit(db)
    return item


def revoke(db, request, record_id, payload):
    identity, item, _ = mutate(db, request, record_id, payload.expected_version, status="approved")
    item.status, item.revoked_by, item.revoked_at = "revoked", identity.user.id, datetime.now(UTC)
    item.revocation_reason = payload.reason
    touched(item, identity)
    audit(db, identity, "revoke", item, request)
    academic.commit(db)
    return item


def remove(db, request, record_id, expected_version):
    identity, item, _ = mutate(db, request, record_id, expected_version)
    audit(db, identity, "delete_draft", item, request)
    db.delete(item)
    academic.commit(db)
