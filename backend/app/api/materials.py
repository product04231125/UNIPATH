"""내 자료 in the student's account: owner-only, versioned, never sent to a model from here.

A material is a written description, a PDF, or both. Lists carry metadata only; the PDF is read
with its own request when the student downloads it or picks it for an analysis.
"""

import base64
import binascii
import hashlib
from datetime import UTC, datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Path, Query, Request, Response
from pydantic import Field, StringConstraints
from sqlalchemy import func, select

from app.api.auth import CurrentIdentity, Database
from app.core.auth_errors import AuthError, conflict
from app.models.personal import StudentMaterial
from app.rag import pdf_pages
from app.schemas.auth import StrictModel
from app.schemas.common import ErrorCode
from app.services import auth
from app.services.access import locked_identity
from app.services.personal import commit

router = APIRouter(prefix="/me", tags=["materials"])

MAX_MATERIALS = 100
MAX_PDF_BYTES = 8 * 1024 * 1024
MAX_TOTAL_BYTES = 50 * 1024 * 1024
MaterialType = Literal["portfolio", "resume", "cover_letter", "other"]
Title = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=120)]
Filename = Annotated[str, StringConstraints(strip_whitespace=True, min_length=5, max_length=200)]


class MaterialFile(StrictModel):
    filename: Filename
    # Base64 of a PDF up to 8 MiB, the most one analysis request can send.
    content_base64: str = Field(min_length=8, max_length=11_184_812)


class MaterialData(StrictModel):
    title: Title
    material_type: MaterialType
    description: str = Field(default="", max_length=4000)


class MaterialCreate(MaterialData):
    # Chosen by the client so a device-saved material keeps its id; repeating it is a no-op.
    id: UUID
    file: MaterialFile | None = None


class MaterialUpdate(MaterialData):
    expected_version: int = Field(ge=1, strict=True)
    # Left out keeps the saved PDF, null removes it, a file replaces it.
    file: MaterialFile | None = None


class MaterialView(StrictModel):
    id: UUID
    title: str
    material_type: str
    description: str
    filename: str | None
    byte_count: int
    version: int
    created_at: datetime
    updated_at: datetime


class MaterialList(StrictModel):
    items: list[MaterialView]
    total_bytes: int
    max_total_bytes: int = MAX_TOTAL_BYTES
    max_file_bytes: int = MAX_PDF_BYTES


def _invalid(message):
    return AuthError(422, ErrorCode.VALIDATION_ERROR, message)


def _missing():
    return AuthError(404, ErrorCode.NOT_FOUND, "자료를 찾을 수 없습니다.")


def _pdf(file: MaterialFile) -> bytes:
    if not file.filename.lower().endswith(".pdf"):
        raise _invalid("PDF 파일을 선택하세요.")
    try:
        raw = base64.b64decode(file.content_base64, validate=True)
    except (binascii.Error, ValueError) as error:
        raise _invalid("파일을 읽지 못했습니다. 다시 선택해 주세요.") from error
    if len(raw) > MAX_PDF_BYTES:
        raise _invalid("PDF는 8MB 이하로 선택하세요.")
    if len(raw) < 5 or raw[:5] != b"%PDF-":
        raise _invalid("PDF 파일을 선택하세요.")
    return raw


def _view(item):
    return MaterialView(
        id=item.id,
        title=item.title,
        material_type=item.material_type,
        description=item.description,
        filename=item.filename,
        byte_count=item.byte_count,
        version=item.version,
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


def _owned(db, owner_id, material_id):
    item = db.scalar(
        select(StudentMaterial).where(
            StudentMaterial.id == material_id, StudentMaterial.owner_id == owner_id
        )
    )
    if item is None:
        raise _missing()
    return item


def _total_bytes(db, owner_id, *, excluding=None):
    query = select(func.coalesce(func.sum(StudentMaterial.byte_count), 0)).where(
        StudentMaterial.owner_id == owner_id
    )
    if excluding is not None:
        query = query.where(StudentMaterial.id != excluding)
    return int(db.scalar(query))


def _apply(item, payload, raw: bytes | None, filename: str | None):
    item.title = payload.title
    item.material_type = payload.material_type
    item.description = payload.description
    item.filename = filename
    item.file_data = raw
    item.byte_count = len(raw) if raw is not None else 0
    item.sha256 = hashlib.sha256(raw).hexdigest() if raw is not None else None


def _check_content(payload, has_file):
    if not has_file and not payload.description.strip():
        raise _invalid("자료 내용 설명 또는 PDF를 입력하세요.")


def _check_total(db, owner_id, added, *, excluding=None):
    if _total_bytes(db, owner_id, excluding=excluding) + added > MAX_TOTAL_BYTES:
        raise AuthError(
            409, ErrorCode.CONFLICT, "자료 PDF 보관 한도 50MB입니다. 쓰지 않는 자료를 지워 주세요."
        )


@router.get("/materials", response_model=MaterialList)
def materials(db: Database, identity: CurrentIdentity):
    """The student's materials, newest first; no file contents."""
    rows = list(
        db.scalars(
            select(StudentMaterial)
            .where(StudentMaterial.owner_id == identity.user.id)
            .order_by(StudentMaterial.updated_at.desc(), StudentMaterial.id)
        )
    )
    return MaterialList(
        items=[_view(item) for item in rows], total_bytes=sum(item.byte_count for item in rows)
    )


@router.post("/materials", response_model=MaterialView, status_code=201)
def create_material(
    payload: MaterialCreate, request: Request, response: Response, db: Database, _: CurrentIdentity
):
    raw = _pdf(payload.file) if payload.file is not None else None
    _check_content(payload, raw is not None)
    identity = locked_identity(db, request)
    existing = db.get(StudentMaterial, payload.id)
    if existing is not None:
        if existing.owner_id != identity.user.id:
            raise conflict()
        # The same material sent again (a retried or repeated move from a device).
        response.status_code = 200
        return _view(existing)
    count = db.scalar(
        select(func.count())
        .select_from(StudentMaterial)
        .where(StudentMaterial.owner_id == identity.user.id)
    )
    if count >= MAX_MATERIALS:
        raise AuthError(
            409,
            ErrorCode.CONFLICT,
            f"자료는 {MAX_MATERIALS}개까지 저장할 수 있습니다. 쓰지 않는 자료를 지워 주세요.",
        )
    _check_total(db, identity.user.id, len(raw or b""))
    item = StudentMaterial(id=payload.id, owner_id=identity.user.id, version=1)
    _apply(item, payload, raw, payload.file.filename if payload.file else None)
    db.add(item)
    commit(db)
    db.refresh(item)
    return _view(item)


@router.put("/materials/{material_id}", response_model=MaterialView)
def update_material(
    material_id: UUID, payload: MaterialUpdate, request: Request, db: Database, _: CurrentIdentity
):
    replace = "file" in payload.model_fields_set
    raw = _pdf(payload.file) if replace and payload.file is not None else None
    identity = locked_identity(db, request)
    item = _owned(db, identity.user.id, material_id)
    if item.version != payload.expected_version:
        raise conflict()
    if replace:
        filename = payload.file.filename if payload.file is not None else None
    else:
        raw, filename = item.file_data, item.filename
    _check_content(payload, raw is not None)
    _check_total(db, identity.user.id, len(raw or b""), excluding=item.id)
    _apply(item, payload, raw, filename)
    item.version += 1
    item.updated_at = datetime.now(UTC)
    commit(db)
    db.refresh(item)
    return _view(item)


@router.delete("/materials/{material_id}", status_code=204)
def delete_material(
    material_id: UUID,
    expected_version: Annotated[int, Query(ge=1)],
    request: Request,
    db: Database,
    _: CurrentIdentity,
):
    identity = locked_identity(db, request)
    item = _owned(db, identity.user.id, material_id)
    if item.version != expected_version:
        raise conflict()
    db.delete(item)
    commit(db)
    return Response(status_code=204)


@router.get(
    "/materials/{material_id}/file",
    response_class=Response,
    responses={200: {"content": {"application/pdf": {}}, "description": "The saved PDF"}},
)
def material_file(material_id: UUID, db: Database, identity: CurrentIdentity):
    item = _owned(db, identity.user.id, material_id)
    if item.file_data is None:
        raise AuthError(404, ErrorCode.NOT_FOUND, "이 자료에는 PDF가 없습니다.")
    return Response(
        item.file_data,
        media_type="application/pdf",
        headers={
            "Content-Disposition": "attachment; filename=material.pdf",
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
            "ETag": f'"{item.sha256}"',
        },
    )


class PageSize(StrictModel):
    width: float
    height: float


class MaterialPages(StrictModel):
    """The saved PDF's page count and the sizes (points) of the pages the viewer shows."""

    page_count: int
    pages: list[PageSize]


def _with_pdf(db, identity, material_id):
    item = _owned(db, identity.user.id, material_id)
    if item.sha256 is None:
        raise AuthError(404, ErrorCode.NOT_FOUND, "이 자료에는 PDF가 없습니다.")
    # Rendering costs CPU: a generous per-student bucket (a long PDF scrolled a few times).
    auth.throttle(db, "material-pages:" + str(identity.user.id), limit=600)
    return item


def _unreadable():
    return _invalid(
        "이 PDF는 미리 볼 수 없습니다(암호가 걸렸거나 손상된 파일). PDF 내보내기로 받아 확인하세요."
    )


@router.get("/materials/{material_id}/pages", response_model=MaterialPages)
def material_pages(material_id: UUID, db: Database, identity: CurrentIdentity):
    """Page count and sizes of the saved PDF, for the in-app viewer."""
    item = _with_pdf(db, identity, material_id)
    try:
        count, sizes = pdf_pages.page_sizes(item.sha256, lambda: item.file_data)
    except pdf_pages.PdfUnreadable as error:
        raise _unreadable() from error
    return MaterialPages(page_count=count, pages=[PageSize(width=w, height=h) for w, h in sizes])


@router.get(
    "/materials/{material_id}/pages/{number}",
    response_class=Response,
    responses={200: {"content": {pdf_pages.MEDIA_TYPE: {}}, "description": "One page image"}},
)
def material_page(
    material_id: UUID,
    number: Annotated[int, Path(ge=1, le=pdf_pages.MAX_PAGES)],
    db: Database,
    identity: CurrentIdentity,
):
    """One page of the saved PDF as an image (1,400 px wide). Nothing is stored."""
    item = _with_pdf(db, identity, material_id)
    try:
        image = pdf_pages.page_image(item.sha256, number, lambda: item.file_data)
    except pdf_pages.PdfUnreadable as error:
        raise _unreadable() from error
    except IndexError as error:
        raise AuthError(404, ErrorCode.NOT_FOUND, "PDF에 그 쪽이 없습니다.") from error
    return Response(
        image,
        media_type=pdf_pages.MEDIA_TYPE,
        headers={"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"},
    )
