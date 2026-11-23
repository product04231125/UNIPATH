"""Authenticated 자기소개서·포트폴리오 drafts and Word export. Nothing is stored on the server."""

from datetime import UTC, datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Query, Request, Response
from pydantic import Field, model_validator

from app.api.auth import CurrentIdentity, Database
from app.core.auth_errors import AuthError, conflict
from app.rag.career.contracts import failure_reason
from app.schemas.common import ErrorCode
from app.schemas.job_analysis import AnalysisDocument
from app.schemas.personalization import (
    MAX_ANALYSIS_RECORDS,
    MAX_DOCUMENT_RECORDS,
    PersonalEvidenceSelection,
)
from app.services import auth, gemini
from app.services.personalization.context import assemble
from app.services.personalization.documents import attach_documents
from app.services.personalization.redaction import redact_context

from . import documents
from .contracts import EditedDocument, ExportProfile, Strict, WritingRequest
from .docx_export import MIME as DOCX_MIME
from .docx_export import export_docx
from .pdf_export import MIME as PDF_MIME
from .pdf_export import FontUnavailable, export_pdf
from .service import generate_draft

router = APIRouter(prefix="/me", tags=["writing"])
FILENAMES = {"cover_letter": "cover-letter", "portfolio": "portfolio"}
FORMATS = {"docx": (DOCX_MIME, export_docx), "pdf": (PDF_MIME, export_pdf)}


class WritingDraftRequest(WritingRequest):
    # Every saved record may be sent (D6); the draft keeps only facts it can cite from them.
    records: list[PersonalEvidenceSelection] = Field(
        default_factory=list, max_length=MAX_ANALYSIS_RECORDS
    )
    # Files picked from 내 자료 for this request only.
    documents: list[AnalysisDocument] = Field(default_factory=list, max_length=5)

    @model_validator(mode="after")
    def unique_records(self):
        keys = [(item.kind, item.record_id) for item in self.records]
        if len(keys) != len(set(keys)):
            raise ValueError("Select each personal record once")
        return self


class WritingExportRequest(Strict):
    document_type: Literal["cover_letter", "portfolio"]
    format: Literal["docx", "pdf"] = "docx"
    draft: EditedDocument
    profile: ExportProfile
    reviewed: bool = Field(strict=True)


@router.post("/writing-drafts")
def writing_drafts(
    payload: WritingDraftRequest, request: Request, db: Database, identity: CurrentIdentity
):
    """An editable draft; every paragraph and fact row cites the student's own records."""
    base = {"official": False, "document_type": payload.document_type, "mode": payload.mode}
    if not payload.external_processing_consent:
        return {
            **base,
            "status": "needs_user_input",
            "missing_fields": ["external_processing_consent"],
        }
    if not payload.records and not payload.documents and not payload.original_text.strip():
        return {**base, "status": "needs_user_input", "missing_fields": ["records"]}
    model_name = request.app.state.settings.vertex_model
    model = getattr(request.app.state, "writing_model", None)
    if model is None:
        return {**base, "status": "not_configured", "model": model_name}
    auth.throttle(db, "writing-draft:" + str(identity.user.id), limit=20)
    context = assemble(db, identity, payload.records)
    outbound, sources, notes = redact_context(context, identity), [], []
    if payload.documents:
        # Extraction/OCR only after consent, and never inside an open transaction.
        db.rollback()
        outbound, sources, notes = attach_documents(
            payload.documents,
            outbound,
            identity,
            max_records=MAX_ANALYSIS_RECORDS + MAX_DOCUMENT_RECORDS,
        )
    records = outbound.model_dump(mode="json")["records"]
    owner_id = identity.user.id
    gemini.reserve_call(db, request)
    # Release the read transaction before calling the external model.
    db.rollback()
    try:
        result = generate_draft(
            payload.model_dump(mode="json", include=set(WritingRequest.model_fields)),
            records,
            model,
            names=(identity.user.display_name,),
        )
    except AuthError:
        raise
    except Exception as error:
        gemini.log_failure("writing draft", error)
        return {
            **base,
            "status": "failed",
            "failure_reason": failure_reason(error),
            "model": model_name,
        }
    db.expire_all()
    current = auth.current_identity(request, db)
    if current.user.id != owner_id or assemble(db, current, payload.records) != context:
        raise conflict()
    return {
        **base,
        **result,
        # Document notes first (unreadable or OCR pages), then the draft's own notes.
        "warnings": (notes + result["warnings"])[:10],
        "document_sources": sources,
        "model": model_name,
        "generated_at": datetime.now(UTC).isoformat(),
    }


@router.post(
    "/writing-exports",
    response_class=Response,
    responses={
        200: {
            "content": {DOCX_MIME: {}, PDF_MIME: {}},
            "description": "Editable Word document or A4 PDF",
        }
    },
)
def writing_exports(payload: WritingExportRequest, db: Database, identity: CurrentIdentity):
    """The owner's edited draft as a Word file or PDF; no model call and nothing stored."""
    if payload.reviewed is not True:
        raise AuthError(422, ErrorCode.VALIDATION_ERROR, "초안을 검토한 뒤 내보내세요.")
    auth.throttle(db, "writing-export:" + str(identity.user.id), limit=60)
    media_type, render = FORMATS[payload.format]
    try:
        raw = render(
            payload.draft.model_dump(mode="json"),
            payload.profile.model_dump(mode="json"),
            document_type=payload.document_type,
            reviewed=True,
        )
    except FontUnavailable as error:
        raise AuthError(
            503, ErrorCode.SERVICE_UNAVAILABLE, "PDF용 글꼴이 서버에 없습니다. Word로 받아 주세요."
        ) from error
    filename = f"{FILENAMES[payload.document_type]}.{payload.format}"
    return Response(
        raw,
        media_type=media_type,
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
            "Cache-Control": "no-store",
        },
    )


@router.get("/writing-documents", response_model=documents.WritingDocumentList)
def writing_documents(db: Database, identity: CurrentIdentity):
    """Saved drafts, newest first; titles and dates only."""
    return documents.list_documents(db, identity.user.id)


@router.post("/writing-documents", response_model=documents.WritingDocumentView, status_code=201)
def create_writing_document(
    payload: documents.WritingDocumentData, request: Request, db: Database, _: CurrentIdentity
):
    return documents.create_document(db, request, payload)


@router.get("/writing-documents/{document_id}", response_model=documents.WritingDocumentView)
def writing_document(document_id: UUID, db: Database, identity: CurrentIdentity):
    return documents.get_document(db, identity.user.id, document_id)


@router.put("/writing-documents/{document_id}", response_model=documents.WritingDocumentView)
def update_writing_document(
    document_id: UUID,
    payload: documents.WritingDocumentUpdate,
    request: Request,
    db: Database,
    _: CurrentIdentity,
):
    return documents.update_document(db, request, document_id, payload)


@router.delete("/writing-documents/{document_id}", status_code=204)
def delete_writing_document(
    document_id: UUID,
    expected_version: Annotated[int, Query(ge=1)],
    request: Request,
    db: Database,
    _: CurrentIdentity,
):
    documents.delete_document(db, request, document_id, expected_version)
    return Response(status_code=204)
