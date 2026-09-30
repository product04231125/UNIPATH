from enum import StrEnum
from uuid import UUID

from pydantic import BaseModel, Field


class ErrorCode(StrEnum):
    VALIDATION_ERROR = "VALIDATION_ERROR"
    NOT_FOUND = "NOT_FOUND"
    METHOD_NOT_ALLOWED = "METHOD_NOT_ALLOWED"
    HTTP_ERROR = "HTTP_ERROR"
    SERVICE_UNAVAILABLE = "SERVICE_UNAVAILABLE"
    INTERNAL_SERVER_ERROR = "INTERNAL_SERVER_ERROR"


class FieldError(BaseModel):
    field: str
    reason: str


class ErrorDetail(BaseModel):
    code: ErrorCode
    message: str
    field_errors: list[FieldError] = Field(default_factory=list)
    request_id: UUID


class ErrorResponse(BaseModel):
    error: ErrorDetail
