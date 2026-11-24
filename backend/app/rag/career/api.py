"""Authenticated portfolio recommendations, using the same app/auth as the student API."""

import base64
import os
from datetime import UTC, datetime
from typing import Annotated, Literal
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Path, Query, Request
from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy import select

from app.api.auth import CurrentIdentity, Database
from app.core.auth_errors import AuthError, conflict
from app.models.personal import AnalysisResult
from app.schemas.common import ErrorCode
from app.schemas.personalization import (
    MAX_ANALYSIS_RECORDS,
    PersonalEvidenceSelection,
    PersonalizationRequest,
)
from app.services import auth, gemini
from app.services.personalization.context import assemble
from app.services.personalization.redaction import redact_context

from . import activities, categories, certificates, regions
from .contracts import SearchQuery, failure_reason
from .crawling import Work24Crawler
from .documents import prepare_documents
from .gap import COLLECTION_SECONDS, MAX_POSTINGS, analyze_gap
from .goal import CareerGoalUpdate, CareerGoalView, get_goal, save_goal
from .greenhouse import Greenhouse
from .ocr import OcrInputError, OcrUnavailable
from .recommendations import recommend
from .regions import RegionName
from .service import CareerService
from .sources import Saramin, Work24
from .transport import Transport

router = APIRouter(prefix="/me", tags=["career"])
RegionCode = Annotated[str, Field(pattern=r"^[0-9]{2,6}(,[0-9]{2,6}){0,15}$")]


class Document(BaseModel):
    model_config = ConfigDict(extra="forbid")
    filename: str = Field(min_length=1, max_length=200)
    content_base64: str = Field(min_length=4, max_length=11_184_812)


OccupationCode = Annotated[str, Field(pattern=r"^[0-9]{2}[0-9A-Z]?$")]


class RecommendationRequest(PersonalizationRequest):
    # Every saved record may be sent; each comparison bounds the text that reaches the model.
    records: list[PersonalEvidenceSelection] = Field(
        default_factory=list, max_length=MAX_ANALYSIS_RECORDS
    )
    academic_stage: Literal["year1", "year2", "year3", "year4", "graduating", "graduate"] | None = (
        None
    )
    documents: list[Document] = Field(default_factory=list, max_length=5)
    # Detail search words; optional once a category (Work24 occupation codes) is chosen.
    keyword: str = Field(default="", max_length=80)
    category_codes: list[OccupationCode] = Field(default_factory=list, max_length=10)
    # `전국`, or the chosen regions in `regions` (searched by each source's region codes).
    region: str = Field(default="", max_length=100)
    regions: list[RegionName] = Field(default_factory=list, max_length=16)
    region_codes: dict[Literal["work24", "saramin"], RegionCode] = Field(default_factory=dict)
    limit: int = Field(default=3, ge=1, le=3)
    external_processing_consent: bool = Field(default=False, strict=True)

    @model_validator(mode="after")
    def keyword_or_category(self):
        if len(set(self.regions)) != len(self.regions):
            raise ValueError("근무 지역을 한 번씩만 골라 주세요.")
        if not self.regions and not self.region.strip():
            raise ValueError("근무 지역을 골라 주세요.")
        categories.validate_codes(self.category_codes)
        if not self.keyword.strip() and not self.category_codes:
            raise ValueError("직무 대분류를 고르거나 세부 검색어를 입력해 주세요.")
        return self


class GapAnalysisRequest(PersonalizationRequest):
    # Every saved record may be sent, like posting recommendations.
    records: list[PersonalEvidenceSelection] = Field(
        default_factory=list, max_length=MAX_ANALYSIS_RECORDS
    )
    # Empty: use the saved career goal.
    category_codes: list[OccupationCode] = Field(default_factory=list, max_length=10)
    keyword: str = Field(default="", max_length=80)
    external_processing_consent: bool = Field(default=False, strict=True)

    @model_validator(mode="after")
    def known_codes(self):
        categories.validate_codes(self.category_codes)
        return self


@router.post("/career-gap-analyses")
def gap_analyses(
    payload: GapAnalysisRequest, request: Request, db: Database, identity: CurrentIdentity
):
    """What postings for the target job ask for most, compared with all saved records."""
    if not payload.external_processing_consent:
        return {"status": "needs_user_input", "missing_fields": ["external_processing_consent"]}
    codes, keyword = list(payload.category_codes), payload.keyword.strip()
    if not codes and not keyword:
        goal = get_goal(db, identity.user.id)
        codes, keyword = list(goal.category_codes), goal.keyword
    if not codes and not keyword:
        return {"status": "needs_user_input", "missing_fields": ["career_goal"]}
    if not payload.records:
        return {"status": "needs_user_input", "missing_fields": ["records"]}
    model_name = request.app.state.settings.vertex_model
    model = getattr(request.app.state, "gap_model", None)
    if model is None:
        return {"status": "not_configured", "model": model_name}
    try:
        query = SearchQuery(
            keyword,
            "전국",
            nationwide=True,
            limit=10,
            occupation_codes=tuple(codes),
        )
    except ValueError as error:
        raise AuthError(422, ErrorCode.VALIDATION_ERROR, "목표 직무를 확인해 주세요.") from error

    auth.throttle(db, "career-gap:" + str(identity.user.id), limit=10)
    context = assemble(db, identity, payload.records)
    records = redact_context(context, identity).model_dump(mode="json")["records"]
    owner_id = identity.user.id
    db.rollback()
    found = CareerService(
        configured_sources(), None, analysis_limit=0, budget_seconds=COLLECTION_SECONDS
    ).recommend(query, {"records": records}, rank_by_records=False)
    postings = [
        item["posting"]
        for item in found["items"]
        if item["posting"]["text_scope"] != "metadata_only"
    ][:MAX_POSTINGS]
    result = {
        "official": False,
        "goal": {
            "category_codes": codes,
            "keyword": keyword,
            "label": categories.label(codes) if codes else None,
        },
        "postings": [
            {
                "posting": index + 1,
                **{
                    key: posting[key]
                    for key in (
                        "source",
                        "source_id",
                        "title",
                        "company",
                        "location",
                        "url",
                        "closing_label",
                        "expires_at",
                    )
                },
            }
            for index, posting in enumerate(postings)
        ],
        "sources": found["sources"],
        "search_notice": found.get("search_notice"),
        "category_browse_available": found.get("category_browse_available", False),
        "requirements": [],
        "summary": None,
        "warnings": [],
        "model": model_name,
        "generated_at": datetime.now(UTC).isoformat(),
    }
    if not postings:
        return {**result, "status": "no_postings"}
    try:
        gemini.reserve_call(db, request)
        requirements, summary, notes = analyze_gap(model, postings, records)
    except AuthError:
        raise
    except Exception as error:
        gemini.log_failure("gap analysis", error)
        return {**result, "status": "failed", "failure_reason": failure_reason(error)}
    db.expire_all()
    current = auth.current_identity(request, db)
    if current.user.id != owner_id or assemble(db, current, payload.records) != context:
        raise conflict()
    if len(postings) < 3:
        notes.insert(
            0, f"목표 직무 공고가 {len(postings)}건만 수집되어 공통 요건이 적게 나올 수 있습니다."
        )
    return {
        **result,
        "status": "completed",
        "requirements": requirements,
        "summary": summary,
        "warnings": notes[:10],
    }


class ActivityRecommendationRequest(PersonalizationRequest):
    records: list[PersonalEvidenceSelection] = Field(
        default_factory=list, max_length=MAX_ANALYSIS_RECORDS
    )
    academic_stage: Literal["year1", "year2", "year3", "year4", "graduating", "graduate"] | None = (
        None
    )
    external_processing_consent: bool = Field(default=False, strict=True)


def latest_gap(db, owner_id):
    """The newest saved 목표 직무 분석 result, or None."""
    return db.scalar(
        select(AnalysisResult)
        .where(AnalysisResult.owner_id == owner_id, AnalysisResult.kind == "gap")
        .order_by(AnalysisResult.created_at.desc())
        .limit(1)
    )


@router.post("/activity-recommendations")
def activity_recommendations(
    payload: ActivityRecommendationRequest,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    """Kinds of external activities for the target job's gaps and where to look for them.

    Real postings, internships included, are found by 공고 찾기 (job-recommendations); listing
    sites for 대외활동·공모전 do not allow collection, so only links and search words are given.
    """
    if not payload.external_processing_consent:
        return {"status": "needs_user_input", "missing_fields": ["external_processing_consent"]}
    goal_view = get_goal(db, identity.user.id)
    codes, keyword = list(goal_view.category_codes), goal_view.keyword
    if not codes and not keyword:
        return {"status": "needs_user_input", "missing_fields": ["career_goal"]}
    if not payload.records:
        return {"status": "needs_user_input", "missing_fields": ["records"]}
    model_name = request.app.state.settings.vertex_model
    model = getattr(request.app.state, "gap_model", None)
    if model is None:
        return {"status": "not_configured", "model": model_name}
    auth.throttle(db, "activity-recommendation:" + str(identity.user.id), limit=10)
    goal = {
        "category_codes": codes,
        "keyword": keyword,
        "label": categories.label(codes) if codes else None,
    }
    saved = latest_gap(db, identity.user.id)
    gaps = activities.gaps_from(saved.result) if saved is not None else []
    context = assemble(db, identity, payload.records)
    records = redact_context(context, identity).model_dump(mode="json")["records"]
    owner_id = identity.user.id
    db.rollback()
    result = {
        "official": False,
        "goal": goal,
        "gap_basis": {
            "analyzed_at": saved.created_at.isoformat() if saved is not None else None,
            "gaps": len(gaps),
        },
        "recommendations": [],
        "summary": None,
        "sites": activities.site_table([]),
        "model": model_name,
        "generated_at": datetime.now(UTC).isoformat(),
    }
    try:
        gemini.reserve_call(db, request)
        recommendations, summary = activities.recommend_activities(
            model,
            goal,
            gaps,
            records,
            academic_stage=payload.academic_stage,
        )
    except AuthError:
        raise
    except Exception as error:
        gemini.log_failure("activity recommendation", error)
        return {**result, "status": "failed", "failure_reason": failure_reason(error)}
    db.expire_all()
    current = auth.current_identity(request, db)
    if current.user.id != owner_id or assemble(db, current, payload.records) != context:
        raise conflict()
    return {
        **result,
        "status": "completed",
        "recommendations": recommendations,
        "summary": summary,
        "sites": activities.site_table(recommendations),
    }


def seoul_today():
    return datetime.now(ZoneInfo("Asia/Seoul")).date()


def public(item):
    return {k: v for k, v in item.items() if k != "aliases"}


@router.get("/certificates")
def certificate_search(
    identity: CurrentIdentity,
    query: Annotated[str, Query(min_length=1, max_length=40)],
):
    """Catalog names matching the query (Q-Net national qualifications and common others)."""
    return {"items": [public(item) for item in certificates.search(query)]}


@router.get("/certificates/{certificate_id}")
def certificate_detail(
    certificate_id: Annotated[str, Path(pattern=r"^(qnet|private)-[A-Za-z0-9_]{1,40}$")],
    identity: CurrentIdentity,
):
    """Official schedule (rounds still ahead), fee, exam method and trends of one certificate."""
    item = certificates.find(certificate_id)
    if item is None:
        raise AuthError(404, ErrorCode.NOT_FOUND, "자격증을 찾을 수 없습니다.")
    return {"official": False, **certificates.detail(item, seoul_today())}


class CertificateRecommendationRequest(PersonalizationRequest):
    records: list[PersonalEvidenceSelection] = Field(
        default_factory=list, max_length=MAX_ANALYSIS_RECORDS
    )
    academic_stage: Literal["year1", "year2", "year3", "year4", "graduating", "graduate"] | None = (
        None
    )
    external_processing_consent: bool = Field(default=False, strict=True)


@router.post("/certificate-recommendations")
def certificate_recommendations(
    payload: CertificateRecommendationRequest,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    """Certificates for the target job's gaps, with official schedules attached afterwards."""
    if not payload.external_processing_consent:
        return {"status": "needs_user_input", "missing_fields": ["external_processing_consent"]}
    goal_view = get_goal(db, identity.user.id)
    codes, keyword = list(goal_view.category_codes), goal_view.keyword
    if not codes and not keyword:
        return {"status": "needs_user_input", "missing_fields": ["career_goal"]}
    if not payload.records:
        return {"status": "needs_user_input", "missing_fields": ["records"]}
    model_name = request.app.state.settings.vertex_model
    model = getattr(request.app.state, "gap_model", None)
    if model is None:
        return {"status": "not_configured", "model": model_name}
    auth.throttle(db, "certificate-recommendation:" + str(identity.user.id), limit=10)
    goal = {
        "category_codes": codes,
        "keyword": keyword,
        "label": categories.label(codes) if codes else None,
    }
    saved = latest_gap(db, identity.user.id)
    report = saved.result if saved is not None else {}
    gaps = activities.gaps_from(report)
    postings = report.get("postings") if isinstance(report, dict) else None
    context = assemble(db, identity, payload.records)
    records = redact_context(context, identity).model_dump(mode="json")["records"]
    owner_id = identity.user.id
    db.rollback()
    result = {
        "official": False,
        "goal": goal,
        "gap_basis": {
            "analyzed_at": saved.created_at.isoformat() if saved is not None else None,
            "gaps": len(gaps),
            "postings": len(postings) if isinstance(postings, list) else 0,
        },
        "recommendations": [],
        "held": [],
        "summary": None,
        "model": model_name,
        "generated_at": datetime.now(UTC).isoformat(),
    }
    try:
        gemini.reserve_call(db, request)
        recommendations, summary, held = certificates.recommend_certificates(
            model, goal, gaps, records, academic_stage=payload.academic_stage
        )
    except AuthError:
        raise
    except Exception as error:
        gemini.log_failure("certificate recommendation", error)
        return {**result, "status": "failed", "failure_reason": failure_reason(error)}
    db.expire_all()
    current = auth.current_identity(request, db)
    if current.user.id != owner_id or assemble(db, current, payload.records) != context:
        raise conflict()
    # Official schedules and how often postings asked, never from the model.
    today = seoul_today()
    frequency = {g["requirement"]: g.get("frequency") for g in gaps}
    for entry in recommendations:
        entry["schedule"] = certificates.schedule(entry["certificate"], today)
        entry["evidence"] = [
            {"requirement": text, "frequency": frequency.get(text)}
            for text in entry["requirements"]
        ]
    return {
        **result,
        "status": "completed",
        "recommendations": recommendations,
        "held": held,
        "summary": summary,
    }


@router.get("/career-goal", response_model=CareerGoalView)
def career_goal(db: Database, identity: CurrentIdentity):
    """The student's target job (Work24 occupation codes and detail words); version 0 if unset."""
    return get_goal(db, identity.user.id)


@router.put("/career-goal", response_model=CareerGoalView)
def put_career_goal(
    payload: CareerGoalUpdate, request: Request, db: Database, identity: CurrentIdentity
):
    return save_goal(db, request, payload)


@router.get("/job-categories")
def job_categories(identity: CurrentIdentity):
    """Work24's 1차·2차 occupation tree: the categories a student picks before detail words."""
    return categories.table()


@router.post("/job-recommendations")
def recommendations(
    payload: RecommendationRequest, request: Request, db: Database, identity: CurrentIdentity
):
    if not payload.external_processing_consent:
        return {"status": "needs_user_input", "missing_fields": ["external_processing_consent"]}
    if not payload.documents and not payload.records:
        return {"status": "needs_user_input", "missing_fields": ["documents_or_records"]}
    model = request.app.state.settings.vertex_model
    if request.app.state.portfolio_analyzer is None:
        return {"status": "not_configured", "model": model}

    auth.throttle(db, "job-recommendation:" + str(identity.user.id), limit=30)
    context = assemble(db, identity, payload.records)
    records = redact_context(context, identity).model_dump(mode="json")["records"]
    locations, warnings = {}, []
    try:
        # Chosen regions go into each source's search; postings are never filtered afterwards.
        ordered = [name for name in regions.WORK24 if name in payload.regions]
        query = SearchQuery(
            payload.keyword.strip(),
            regions.label(ordered) if ordered else payload.region.strip(),
            nationwide=not ordered and payload.region.strip() == "전국",
            region_codes=regions.provider_codes(ordered) if ordered else payload.region_codes,
            limit=payload.limit,
            occupation_codes=tuple(payload.category_codes),
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
            # At most 20 document chunks (prepare_documents) on top of the saved records.
            records.extend(uploaded["records"])
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
        academic_stage=payload.academic_stage,
        before_analysis=lambda: gemini.reserve_call(db, request),
    )
    db.expire_all()
    current = auth.current_identity(request, db)
    if current.user.id != owner_id or assemble(db, current, payload.records) != context:
        raise conflict()
    return {
        **result,
        "model": model,
        "document_locations": locations,
        "document_warnings": warnings,
    }


def configured_sources():
    network = Transport(allow_network=True)
    mode = os.getenv("CAREER_SOURCE_MODE", "api")
    if mode not in {"api", "crawl", "hybrid"}:
        raise ValueError("CAREER_SOURCE_MODE must be api, crawl or hybrid")
    crawler = Work24Crawler(Transport(allow_network=True, timeout=5))
    if mode == "crawl":
        return [crawler]
    sources = [
        Saramin(os.getenv("SARAMIN_ACCESS_KEY"), transport=network),
        Work24(os.getenv("WORK24_AUTH_KEY"), transport=network),
    ]
    board = os.getenv("CAREER_GREENHOUSE_BOARD", "sendbird").strip()
    if board:
        sources.append(Greenhouse(board, network))
    if mode == "hybrid":
        sources.append(crawler)
    return sources


def portfolio_analyzer(config):
    """Command-line runs; the API uses the job-analysis model created at startup."""
    model = None
    if config.vertex_configured:
        model = gemini.create_model(config, timeout=config.vertex_timeout_seconds)
    return gemini.create_job_analyzer(model)


def create_app(settings=None):
    """Kept for existing commands: the main API now serves this router itself."""
    from app.main import create_app as base_app

    return base_app(settings)
