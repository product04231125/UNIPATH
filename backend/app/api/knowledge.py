"""Administrator review storage and authenticated catalogue-scoped school retrieval."""

from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Path, Query, Request

from app.api.auth import CurrentIdentity, Database
from app.schemas import knowledge as dto
from app.schemas.assistant import AssistantQueryResponse
from app.services import knowledge, knowledge_queries

router = APIRouter(prefix="/admin/knowledge-revisions", tags=["school knowledge review"])
student_router = APIRouter(prefix="/me", tags=["school knowledge"])
Limit = Annotated[int, Query(ge=1, le=100)]
Page = Annotated[int, Path(ge=1, le=200)]


@router.post("", response_model=dto.KnowledgeView, status_code=201)
def create(payload: dto.KnowledgeCreate, request: Request, db: Database, identity: CurrentIdentity):
    return knowledge.create(db, request, payload)


@router.get("", response_model=dto.KnowledgeList)
def listing(
    db: Database,
    identity: CurrentIdentity,
    institution_id: UUID | None = None,
    status: Literal["draft", "approved", "revoked"] | None = None,
    source_document_id: UUID | None = None,
    cursor: UUID | None = None,
    limit: Limit = 100,
):
    rows = knowledge.listing(
        db, identity, institution_id, status, source_document_id, cursor, limit
    )
    return {"items": rows[:limit], "next_cursor": rows[limit - 1].id if len(rows) > limit else None}


@router.get("/{record_id}", response_model=dto.KnowledgeView)
def detail(record_id: UUID, db: Database, identity: CurrentIdentity):
    return knowledge.read(db, identity, record_id)


@router.delete("/{record_id}", status_code=204)
def remove(
    record_id: UUID,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
    expected_version: Annotated[int, Query(ge=1)],
):
    knowledge.remove(db, request, record_id, expected_version)


@router.get("/{record_id}/pages", response_model=dto.PageList)
def pages(
    record_id: UUID,
    db: Database,
    identity: CurrentIdentity,
    cursor: Annotated[int | None, Query(ge=1, le=200)] = None,
    limit: Limit = 100,
):
    item = knowledge.read(db, identity, record_id)
    rows = knowledge.pages(db, item, cursor, limit)
    return {
        "items": rows[:limit],
        "next_cursor": rows[limit - 1]["page"] if len(rows) > limit else None,
    }


@router.get("/{record_id}/pages/{page}", response_model=dto.PageView)
def page_detail(record_id: UUID, page: Page, db: Database, identity: CurrentIdentity):
    item = knowledge.read(db, identity, record_id)
    return knowledge.page_view(item, knowledge.chunks(db, item.id, page))


@router.put("/{record_id}/pages/{page}", response_model=dto.PageView)
def replace_page(
    record_id: UUID,
    page: Page,
    payload: dto.PageReplace,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return knowledge.replace_page(db, request, record_id, page, payload)


@router.delete("/{record_id}/pages/{page}", status_code=204)
def delete_page(
    record_id: UUID,
    page: Page,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
    expected_version: Annotated[int, Query(ge=1)],
):
    knowledge.remove_page(db, request, record_id, page, expected_version)


@router.post("/{record_id}/approve", response_model=dto.KnowledgeView)
def approve(
    record_id: UUID,
    payload: dto.KnowledgeApprove,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return knowledge.approve(db, request, record_id, payload)


@router.post("/{record_id}/revoke", response_model=dto.KnowledgeView)
def revoke(
    record_id: UUID,
    payload: dto.KnowledgeRevoke,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return knowledge.revoke(db, request, record_id, payload)


def get_index_cache(request: Request):
    return request.app.state.knowledge_index_cache


Cache = Annotated[knowledge_queries.KnowledgeIndexCache, Depends(get_index_cache)]


@student_router.post("/school-searches", response_model=dto.KnowledgeSearchResponse)
def search_sources(
    payload: dto.KnowledgeSearch,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
    cache: Cache,
):
    return knowledge_queries.execute(db, request, payload, cache, search=True)


@student_router.post("/school-queries", response_model=AssistantQueryResponse)
def query_school(
    payload: dto.KnowledgeQuery,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
    cache: Cache,
):
    return knowledge_queries.execute(db, request, payload, cache)
