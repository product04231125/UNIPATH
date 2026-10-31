"""Minimal personal-context and job-analysis endpoints, without management features."""

from fastapi import APIRouter, Request

from app.api.auth import CurrentIdentity, Database
from app.schemas.job_analysis import JobAnalysisRequest, JobAnalysisResponse
from app.schemas.personalization import PersonalizationContext, PersonalizationRequest
from app.services.job_analysis.service import execute
from app.services.personalization.context import assemble

router = APIRouter(prefix="/me", tags=["personalization and job analysis"])


@router.post("/personalization-contexts", response_model=PersonalizationContext)
def context(payload: PersonalizationRequest, db: Database, identity: CurrentIdentity):
    return assemble(db, identity, payload.records)


@router.post("/job-analyses", response_model=JobAnalysisResponse)
def analyze(payload: JobAnalysisRequest, request: Request, db: Database, identity: CurrentIdentity):
    return execute(db, request, payload, request.app.state.job_analyzer)
