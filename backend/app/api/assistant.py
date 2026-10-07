from typing import Annotated

from fastapi import APIRouter, Depends

from app.api.dependencies import get_school_rag_service
from app.rag.school.service import SchoolRagService
from app.schemas.assistant import AssistantQueryRequest, AssistantQueryResponse
from app.services.assistant import query_school

router = APIRouter(prefix="/assistant", tags=["assistant"])


@router.post("/queries", response_model=AssistantQueryResponse)
def query(
    payload: AssistantQueryRequest,
    service: Annotated[SchoolRagService, Depends(get_school_rag_service)],
) -> AssistantQueryResponse:
    return query_school(payload, service)
