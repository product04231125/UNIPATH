"""Authenticated portfolio recommendations, using the same app/auth as the student API."""

import base64
import os
from typing import Annotated, Literal

from fastapi import APIRouter, Request
from pydantic import BaseModel, ConfigDict, Field

from app.api.auth import CurrentIdentity, Database
from app.core.auth_errors import AuthError, conflict
from app.schemas.common import ErrorCode
from app.schemas.personalization import PersonalizationRequest
from app.services import auth, gemini
from app.services.personalization.context import assemble
from app.services.personalization.redaction import redact_context

from .contracts import SearchQuery
from .documents import prepare_documents
from .greenhouse import Greenhouse
from .ocr import OcrInputError, OcrUnavailable
from .recommendations import MODEL, recommend
from .sources import Saramin, Work24
from .transport import Transport

router = APIRouter(prefix="/me", tags=["career"])
RegionCode = Annotated[str, Field(pattern=r"^[0-9]{2,6}$")]


class Document(BaseModel):
    model_config = ConfigDict(extra="forbid")
    filename: str = Field(min_length=1, max_length=200)
    content_base64: str = Field(min_length=4, max_length=11_184_812)


class RecommendationRequest(PersonalizationRequest):
    documents: list[Document] = Field(default_factory=list, max_length=5)
    keyword: str = Field(min_length=1, max_length=80)
    region: str = Field(min_length=1, max_length=100)
    region_codes: dict[Literal["work24", "saramin"], RegionCode] = Field(default_factory=dict)
    limit: int = Field(default=3, ge=1, le=3)
    external_processing_consent: bool = Field(default=False, strict=True)


@router.post("/job-recommendations")
def recommendations(
    payload: RecommendationRequest, request: Request, db: Database, identity: CurrentIdentity
):
    if not payload.external_processing_consent:
        return {"status": "needs_user_input", "missing_fields": ["external_processing_consent"]}
    if not payload.documents and not payload.records:
        return {"status": "needs_user_input", "missing_fields": ["documents_or_records"]}
    if request.app.state.portfolio_analyzer is None:
        return {"status": "not_configured", "model": MODEL}

    auth.throttle(db, "job-recommendation:" + str(identity.user.id), limit=30)
    context = assemble(db, identity, payload.records)
    records = redact_context(context, identity).model_dump(mode="json")["records"]
    locations, warnings = {}, []
    try:
        query = SearchQuery(
            payload.keyword.strip(),
            payload.region.strip(),
            nationwide=payload.region.strip() == "전국",
            region_codes=payload.region_codes,
            limit=payload.limit,
        )
        if sum(len(doc.content_base64) for doc in payload.documents) > 11_184_812:
            raise ValueError("선택한 파일의 합계는 8MiB 이하여야 합니다.")
        if payload.documents:
            files = [
                (doc.filename, base64.b64decode(doc.content_base64, validate=True))
                for doc in payload.documents
            ]
            uploaded, locations, warnings = prepare_documents(
                files, names=(identity.user.display_name,)
            )
            records.extend(uploaded["records"])
        if len(records) > 20:
            raise ValueError("문서 범위와 선택 기록 수를 줄여 주세요.")
    except OcrUnavailable as error:
        raise AuthError(503, ErrorCode.SERVICE_UNAVAILABLE, str(error)) from error
    except OcrInputError as error:
        raise AuthError(422, ErrorCode.VALIDATION_ERROR, str(error)) from error
    except Exception as error:
        raise AuthError(
            422,
            ErrorCode.VALIDATION_ERROR,
            "검색 조건과 파일 형식·크기·텍스트 추출 가능 여부를 확인해 주세요.",
        ) from error

    owner_id = identity.user.id
    db.rollback()
    result = recommend(
        query,
        records,
        configured_sources(),
        request.app.state.portfolio_analyzer,
        before_analysis=lambda: gemini.reserve_call(db, request),
    )
    db.expire_all()
    current = auth.current_identity(request, db)
    if current.user.id != owner_id or assemble(db, current, payload.records) != context:
        raise conflict()
    return {
        **result,
        "model": MODEL,
        "document_locations": locations,
        "document_warnings": warnings,
    }


def configured_sources():
    network = Transport(allow_network=True)
    sources = [
        Saramin(os.getenv("SARAMIN_ACCESS_KEY"), transport=network),
        Work24(os.getenv("WORK24_AUTH_KEY"), transport=network),
    ]
    board = os.getenv("CAREER_GREENHOUSE_BOARD", "sendbird").strip()
    if board:
        sources.append(Greenhouse(board, network))
    return sources


def portfolio_analyzer(config):
    model = None
    if config.vertex_configured:
        model = gemini.create_model(
            config.model_copy(update={"vertex_model": MODEL}), timeout=config.vertex_timeout_seconds
        )
    return gemini.create_job_analyzer(model)


def create_app(settings=None):
    """ASGI factory, also supports the project's standard frontend and existing routes."""
    from app.core.config import get_settings
    from app.main import create_app as base_app

    config = settings or get_settings()
    app = base_app(config)
    app.state.portfolio_analyzer = portfolio_analyzer(config)
    app.include_router(router, prefix="/api/v1")
    return app
