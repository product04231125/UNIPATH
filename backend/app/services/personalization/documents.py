"""Files the student picked from 내 자료 become request-scoped records next to saved ones."""

import base64

from app.core.auth_errors import AuthError
from app.schemas.common import ErrorCode
from app.schemas.personalization import PersonalEvidence, PersonalizationContext
from app.services.personalization.redaction import redact_text

MAX_TOTAL_BASE64 = 11_184_812
MAX_TOTAL_BYTES = 8 * 1024 * 1024


def attach_documents(documents, outbound, identity, *, max_records):
    """Return (context, sources, warnings) for one request; nothing is stored on the server.

    Text is extracted (OCR for scans), redacted like saved records and appended as records with
    fresh IDs, so the usual citation checks apply. Sources tell the app which file and page each
    of those IDs came from.
    """
    # Imported only for explicit document requests; reuse #69 extraction and redaction.
    from app.rag.career.documents import prepare_documents
    from app.rag.career.ocr import OcrUnavailable

    names = (identity.user.display_name,)
    try:
        if sum(len(doc.content_base64) for doc in documents) > MAX_TOTAL_BASE64:
            raise ValueError("선택한 파일의 합계는 8MiB 이하여야 합니다.")
        files = [(d.filename, base64.b64decode(d.content_base64, validate=True)) for d in documents]
        if sum(len(raw) for _, raw in files) > MAX_TOTAL_BYTES:
            raise ValueError("선택한 파일의 합계는 8MiB 이하여야 합니다.")
        extracted, locations, warnings = prepare_documents(files, names=names)
        records, sources = list(outbound.records), []
        for item in extracted["records"]:
            source = locations[item["record_id"]]
            title = f"{source['filename'][:80]} · {source['location']}"
            if source["method"] == "ocr":
                title += " · OCR 원본 대조 필요"
            records.append(PersonalEvidence(**item, title=redact_text(title, names=names)[:128]))
            sources.append(
                {
                    "record_id": item["record_id"],
                    "filename": source["filename"][:200],
                    "location": source["location"][:40],
                    "ocr": source["method"] == "ocr",
                }
            )
        if len(records) > max_records:
            raise ValueError("문서 범위와 선택 기록 수를 줄여 주세요.")
        return PersonalizationContext(records=records), sources, warnings
    except OcrUnavailable as error:
        raise AuthError(503, ErrorCode.SERVICE_UNAVAILABLE, str(error)) from error
    except Exception as error:
        raise AuthError(
            422,
            ErrorCode.VALIDATION_ERROR,
            "파일 형식·8MiB 합계·텍스트 추출 가능 여부를 확인해 주세요.",
        ) from error
