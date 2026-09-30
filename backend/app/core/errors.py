import logging
from uuid import UUID, uuid4

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException

from app.schemas.common import ErrorCode, ErrorDetail, ErrorResponse, FieldError
from app.services.health import NotReadyError

logger = logging.getLogger(__name__)


def error_response(
    request: Request,
    status_code: int,
    code: ErrorCode,
    message: str,
    field_errors: list[FieldError] | None = None,
) -> JSONResponse:
    request_id = getattr(request.state, "request_id", uuid4())
    body = ErrorResponse(
        error=ErrorDetail(
            code=code, message=message, field_errors=field_errors or [], request_id=request_id
        )
    )
    return JSONResponse(
        status_code=status_code,
        content=body.model_dump(mode="json"),
        headers={"X-Request-ID": str(request_id)},
    )


def register_error_handlers(app: FastAPI) -> None:
    @app.middleware("http")
    async def request_id_middleware(request: Request, call_next):
        try:
            request.state.request_id = UUID(request.headers.get("X-Request-ID", ""))
        except ValueError:
            request.state.request_id = uuid4()
        try:
            response = await call_next(request)
        except Exception:
            # Do not log input, exception text, or traceback containing personal data.
            logger.error("Unhandled request error; request_id=%s", request.state.request_id)
            response = error_response(
                request, 500, ErrorCode.INTERNAL_SERVER_ERROR, "서버에서 오류가 발생했습니다."
            )
        response.headers["X-Request-ID"] = str(request.state.request_id)
        return response

    @app.exception_handler(RequestValidationError)
    async def validation_error(request: Request, exc: RequestValidationError):
        fields = [
            FieldError(field=".".join(map(str, item["loc"])), reason=item["type"])
            for item in exc.errors()
        ]
        return error_response(
            request, 422, ErrorCode.VALIDATION_ERROR, "입력값을 확인해 주세요.", fields
        )

    @app.exception_handler(HTTPException)
    async def http_error(request: Request, exc: HTTPException):
        code, message = {
            404: (ErrorCode.NOT_FOUND, "요청한 데이터를 찾을 수 없습니다."),
            405: (ErrorCode.METHOD_NOT_ALLOWED, "허용되지 않은 요청 방식입니다."),
        }.get(exc.status_code, (ErrorCode.HTTP_ERROR, "요청을 처리할 수 없습니다."))
        response = error_response(request, exc.status_code, code, message)
        response.headers.update(exc.headers or {})
        return response

    @app.exception_handler(NotReadyError)
    async def not_ready(request: Request, exc: NotReadyError):
        return error_response(
            request, 503, ErrorCode.SERVICE_UNAVAILABLE, "데이터베이스가 아직 준비되지 않았습니다."
        )

    @app.exception_handler(Exception)
    async def internal_error(request: Request, exc: Exception):
        return error_response(
            request, 500, ErrorCode.INTERNAL_SERVER_ERROR, "서버에서 오류가 발생했습니다."
        )
