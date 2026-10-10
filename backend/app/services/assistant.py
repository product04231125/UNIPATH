from uuid import uuid4

from app.core.config import Settings
from app.rag.school.contracts import SchoolContext
from app.rag.school.retriever import SchoolRetriever, load_chunks
from app.rag.school.service import SchoolRagService
from app.schemas.assistant import (
    AssistantCitation,
    AssistantQueryRequest,
    AssistantQueryResponse,
    AssistantReason,
    AssistantStatus,
)


def create_school_rag_service(settings: Settings) -> SchoolRagService:
    path = settings.resolved_school_corpus_path
    try:
        chunks = load_chunks(path) if path is not None else []
        return SchoolRagService(SchoolRetriever(chunks))
    except (OSError, ValueError, KeyError, TypeError):
        # Fail closed on an invalid configured corpus without disclosing its content.
        raise RuntimeError("The configured school corpus cannot be loaded") from None


def query_school(
    payload: AssistantQueryRequest, service: SchoolRagService
) -> AssistantQueryResponse:
    query_id = uuid4()
    try:
        result = service.query(
            payload.question,
            SchoolContext(**payload.context.model_dump()),
            preview=False,
        )
        return AssistantQueryResponse(
            query_id=query_id,
            status=result.status,
            reason=result.reason,
            answer=result.answer,
            citations=[
                AssistantCitation(
                    chunk_id=item["chunk_id"],
                    document_id=item["document_id"],
                    title=item["title"],
                    source_url=item["source_url"],
                    page=item["page"],
                    excerpt=item["excerpt"],
                )
                for item in result.citations
            ],
            missing_fields=result.missing_fields,
        )
    except Exception:
        # Provider/module failures must not expose input, unvalidated answers, or exception details.
        return AssistantQueryResponse(
            query_id=query_id,
            status=AssistantStatus.FAILED,
            reason=AssistantReason.RAG_PROCESSING_FAILED,
        )
