"""Saved analysis results: 공고 1개 비교, 목표 직무 분석, 공고 찾기, 활동 추천 and 자격증 추천.

The app saves each finished result for its owner. The newest results of each kind are kept and
older ones fall off, except starred (favorite) ones, which stay until the student removes them.
A saved result is a snapshot for the owner to reread; nothing here calls a model.
"""

import json
from datetime import datetime
from typing import Annotated, Any, Literal, get_args
from uuid import UUID

from fastapi import APIRouter, Query, Request, Response
from pydantic import Field, StringConstraints
from sqlalchemy import delete, func, select

from app.api.auth import CurrentIdentity, Database
from app.core.auth_errors import AuthError
from app.models.personal import AnalysisResult
from app.schemas.auth import StrictModel
from app.schemas.common import ErrorCode
from app.services.access import locked_identity
from app.services.personal import commit

router = APIRouter(prefix="/me", tags=["analysis results"])

KEEP_RECENT = 30
MAX_FAVORITES = 50
MAX_RESULT_CHARS = 200_000
MAX_INPUT_CHARS = 30_000
MAX_SUMMARY_CHARS = 2_000
Kind = Literal["posting", "gap", "search", "activity", "certificate"]
Title = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=160)]
SummaryValue = Annotated[str, StringConstraints(max_length=200)] | int | float | bool | None


class AnalysisResultCreate(StrictModel):
    kind: Kind
    title: Title
    summary: dict[Annotated[str, StringConstraints(max_length=40)], SummaryValue] = Field(
        default_factory=dict, max_length=12
    )
    input: dict[str, Any] = Field(default_factory=dict)
    result: dict[str, Any]


class AnalysisResultFavorite(StrictModel):
    favorite: bool = Field(strict=True)


class AnalysisResultSummary(StrictModel):
    id: UUID
    kind: str
    title: str
    summary: dict[str, Any]
    favorite: bool
    created_at: datetime


class AnalysisResultView(AnalysisResultSummary):
    input: dict[str, Any]
    result: dict[str, Any]


class AnalysisResultList(StrictModel):
    items: list[AnalysisResultSummary]


def _too_large(what):
    return AuthError(422, ErrorCode.VALIDATION_ERROR, f"{what}가 너무 커서 저장하지 못했습니다.")


def _size(value):
    return len(json.dumps(value, ensure_ascii=False))


def _summary(item):
    return AnalysisResultSummary(
        id=item.id,
        kind=item.kind,
        title=item.title,
        summary=item.summary,
        favorite=item.favorite,
        created_at=item.created_at,
    )


def _owned(db, owner_id, result_id):
    item = db.scalar(
        select(AnalysisResult).where(
            AnalysisResult.id == result_id, AnalysisResult.owner_id == owner_id
        )
    )
    if item is None:
        raise AuthError(404, ErrorCode.NOT_FOUND, "저장된 분석 결과를 찾을 수 없습니다.")
    return item


@router.get("/analysis-results", response_model=AnalysisResultList)
def analysis_results(
    db: Database, identity: CurrentIdentity, kind: Annotated[Kind | None, Query()] = None
):
    """Starred results first, then newest; titles and small facts only."""
    query = select(AnalysisResult).where(AnalysisResult.owner_id == identity.user.id)
    if kind is not None:
        query = query.where(AnalysisResult.kind == kind)
    rows = db.scalars(
        query.order_by(
            AnalysisResult.favorite.desc(), AnalysisResult.created_at.desc(), AnalysisResult.id
        ).limit(KEEP_RECENT * len(get_args(Kind)) + MAX_FAVORITES)
    )
    return AnalysisResultList(items=[_summary(item) for item in rows])


@router.post("/analysis-results", response_model=AnalysisResultSummary, status_code=201)
def save_analysis_result(
    payload: AnalysisResultCreate, request: Request, db: Database, _: CurrentIdentity
):
    if _size(payload.result) > MAX_RESULT_CHARS:
        raise _too_large("분석 결과")
    if _size(payload.input) > MAX_INPUT_CHARS:
        raise _too_large("분석 조건")
    if _size(payload.summary) > MAX_SUMMARY_CHARS:
        raise _too_large("요약")
    identity = locked_identity(db, request)
    item = AnalysisResult(
        owner_id=identity.user.id,
        kind=payload.kind,
        title=payload.title,
        summary=dict(payload.summary),
        input=payload.input,
        result=payload.result,
        favorite=False,
    )
    db.add(item)
    db.flush()
    # Keep the newest results of this kind; starred ones are never removed here.
    stale = (
        select(AnalysisResult.id)
        .where(
            AnalysisResult.owner_id == identity.user.id,
            AnalysisResult.kind == payload.kind,
            AnalysisResult.favorite.is_(False),
        )
        .order_by(AnalysisResult.created_at.desc(), AnalysisResult.id.desc())
        .offset(KEEP_RECENT)
    )
    db.execute(delete(AnalysisResult).where(AnalysisResult.id.in_(stale.scalar_subquery())))
    commit(db)
    db.refresh(item)
    return _summary(item)


@router.get("/analysis-results/{result_id}", response_model=AnalysisResultView)
def analysis_result(result_id: UUID, db: Database, identity: CurrentIdentity):
    item = _owned(db, identity.user.id, result_id)
    return AnalysisResultView(**_summary(item).model_dump(), input=item.input, result=item.result)


@router.patch("/analysis-results/{result_id}", response_model=AnalysisResultSummary)
def favorite_analysis_result(
    result_id: UUID,
    payload: AnalysisResultFavorite,
    request: Request,
    db: Database,
    _: CurrentIdentity,
):
    """Star (keep) or unstar a saved result."""
    identity = locked_identity(db, request)
    item = _owned(db, identity.user.id, result_id)
    if payload.favorite and not item.favorite:
        starred = db.scalar(
            select(func.count())
            .select_from(AnalysisResult)
            .where(AnalysisResult.owner_id == identity.user.id, AnalysisResult.favorite.is_(True))
        )
        if starred >= MAX_FAVORITES:
            raise AuthError(
                409,
                ErrorCode.CONFLICT,
                f"즐겨찾기는 {MAX_FAVORITES}개까지 할 수 있습니다. 필요 없는 것을 해제해 주세요.",
            )
    item.favorite = payload.favorite
    commit(db)
    db.refresh(item)
    return _summary(item)


@router.delete("/analysis-results/{result_id}", status_code=204)
def delete_analysis_result(result_id: UUID, request: Request, db: Database, _: CurrentIdentity):
    identity = locked_identity(db, request)
    db.delete(_owned(db, identity.user.id, result_id))
    commit(db)
    return Response(status_code=204)
