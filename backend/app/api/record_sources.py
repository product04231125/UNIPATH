"""Bounded private PDF uploads and explicit, school-scoped source review."""

import base64
import binascii
from typing import Annotated
from urllib.parse import quote
from uuid import UUID

from fastapi import APIRouter, Depends, Header, Query, Request, Response
from pydantic import ValidationError
from starlette.concurrency import run_in_threadpool
from starlette.requests import ClientDisconnect

from app.api.auth import CurrentIdentity, Database
from app.core.auth_errors import AuthError
from app.schemas import record_sources as dto
from app.schemas.common import ErrorCode, ErrorResponse
from app.services import auth
from app.services import record_sources as service

router = APIRouter(prefix="/me/official-record-sources", tags=["private school-issued sources"])
admin_router = APIRouter(
    prefix="/admin/official-record-sources", tags=["school-issued source review"]
)


def upload_metadata(
    encoded: Annotated[
        str,
        Header(
            alias="X-Unipath-Source-Metadata",
            min_length=1,
            max_length=4096,
            description="Base64url UTF-8 SourceUpload JSON; filenames must not be placed in URLs",
            json_schema_extra={
                "contentEncoding": "base64url",
                "contentMediaType": "application/json",
                "contentSchema": dto.SourceUpload.model_json_schema(),
            },
        ),
    ],
):
    try:
        decoded = base64.b64decode(encoded, altchars=b"-_", validate=True)
        return dto.SourceUpload.model_validate_json(decoded)
    except (ValidationError, binascii.Error, ValueError):
        raise service.invalid() from None


@router.post(
    "",
    response_model=dto.SourceView,
    status_code=201,
    responses={413: {"model": ErrorResponse}, 415: {"model": ErrorResponse}},
    openapi_extra={
        "requestBody": {
            "required": True,
            "content": {"application/pdf": {"schema": {"type": "string", "format": "binary"}}},
        }
    },
)
async def upload(
    request: Request,
    db: Database,
    identity: CurrentIdentity,
    metadata: Annotated[dto.SourceUpload, Depends(upload_metadata)],
):
    if (
        request.headers.get("content-type", "").split(";", 1)[0].strip().lower()
        != "application/pdf"
    ):
        raise AuthError(415, ErrorCode.HTTP_ERROR, "PDF 원본을 application/pdf로 전송해 주세요.")
    length = request.headers.get("content-length")
    if length is not None:
        if not length.isascii() or not length.isdigit():
            raise service.invalid()
        if len(length) > 10 or int(length) > dto.MAX_FILE_BYTES:
            raise service.too_large()
    await run_in_threadpool(
        auth.throttle, db, "record-source-upload:" + str(identity.user.id), limit=20
    )
    data = bytearray()
    try:
        async for part in request.stream():
            if len(data) + len(part) > dto.MAX_FILE_BYTES:
                raise service.too_large()
            data.extend(part)
    except ClientDisconnect:
        raise service.invalid() from None
    if length is not None and len(data) != int(length):
        raise service.invalid()
    return await run_in_threadpool(service.upload, db, request, metadata, bytes(data))


def add_read_routes(target, *, admin):
    def listing(
        db: Database,
        identity: CurrentIdentity,
        institution_id: UUID | None = None,
        status: dto.SourceStatus | None = None,
        cursor: UUID | None = None,
        limit: Annotated[int, Query(ge=1, le=100)] = 100,
    ):
        return service.listing(
            db,
            identity,
            admin=admin,
            institution_id=institution_id,
            status=status,
            cursor=cursor,
            limit=limit,
        )

    def detail(source_id: UUID, db: Database, identity: CurrentIdentity):
        return (service.admin_read if admin else service.owner_read)(db, identity, source_id)

    def events(source_id: UUID, db: Database, identity: CurrentIdentity):
        item = (service.admin_read if admin else service.owner_read)(db, identity, source_id)
        return service.events(db, item)

    def file(source_id: UUID, request: Request, db: Database, identity: CurrentIdentity):
        data, filename = service.download(db, request, source_id, admin=admin)
        return Response(
            data,
            media_type="application/octet-stream",
            headers={
                "Content-Disposition": f'attachment; filename="record-{source_id}.pdf"; '
                f"filename*=UTF-8''{quote(filename, safe='')}",
                "X-Content-Type-Options": "nosniff",
                "Content-Security-Policy": "sandbox",
                "Cache-Control": "no-store",
            },
        )

    for path, handler, model in [
        ("", listing, dto.SourceList),
        ("/{source_id}", detail, dto.SourceView),
        ("/{source_id}/events", events, dto.SourceEventList),
    ]:
        target.add_api_route(
            path,
            handler,
            response_model=model,
            name=f"record_source_{'admin' if admin else 'owner'}_{handler.__name__}",
        )
    target.add_api_route(
        "/{source_id}/file",
        file,
        response_class=Response,
        name=f"record_source_{'admin' if admin else 'owner'}_file",
        responses={
            200: {
                "content": {
                    "application/octet-stream": {"schema": {"type": "string", "format": "binary"}}
                }
            }
        },
    )


add_read_routes(router, admin=False)
add_read_routes(admin_router, admin=True)


@router.post("/{source_id}/withdraw", response_model=dto.SourceView)
def withdraw(
    source_id: UUID,
    payload: dto.SourceExpectedVersion,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return service.transition(db, request, source_id, payload, "withdrawn")


@admin_router.post("/{source_id}/verify", response_model=dto.SourceView)
def verify(
    source_id: UUID,
    payload: dto.SourceVerify,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return service.transition(db, request, source_id, payload, "verified")


@admin_router.post("/{source_id}/reject", response_model=dto.SourceView)
def reject(
    source_id: UUID,
    payload: dto.SourceReason,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return service.transition(db, request, source_id, payload, "rejected")


@admin_router.post("/{source_id}/revoke", response_model=dto.SourceView)
def revoke(
    source_id: UUID,
    payload: dto.SourceReason,
    request: Request,
    db: Database,
    identity: CurrentIdentity,
):
    return service.transition(db, request, source_id, payload, "revoked")
