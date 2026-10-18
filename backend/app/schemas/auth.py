import re
import unicodedata
from datetime import datetime
from enum import StrEnum
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, SecretStr, StringConstraints, field_validator

from app.models.identity import AccountStatus, Role, ScopeStatus

Name = Annotated[str, StringConstraints(min_length=1, max_length=128, strip_whitespace=True)]


class SessionMode(StrEnum):
    COOKIE = "cookie"
    BEARER = "bearer"


def normalized_email(value: str) -> str:
    value = value.strip().lower()
    # This MVP accepts ASCII mailbox addresses, not SMTPUTF8 or ownership claims.
    if len(value) > 254 or not re.fullmatch(
        r"[a-z0-9!#$%&'*+/=?^_`{|}~.-]+@[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\.[a-z]{2,63}", value
    ):
        raise ValueError("Invalid email address")
    local, domain = value.rsplit("@", 1)
    if len(local) > 64 or local.startswith(".") or local.endswith(".") or ".." in value:
        raise ValueError("Invalid email address")
    if any(
        not label or len(label) > 63 or label.startswith("-") or label.endswith("-")
        for label in domain.split(".")
    ):
        raise ValueError("Invalid email domain")
    return value


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class LoginRequest(StrictModel):
    email: str = Field(min_length=3, max_length=254)
    password: SecretStr = Field(min_length=1, max_length=128)
    session_mode: SessionMode = SessionMode.COOKIE
    _email = field_validator("email")(normalized_email)

    @field_validator("password")
    @classmethod
    def bounded_password(cls, value: SecretStr):
        if not 1 <= len(value.get_secret_value()) <= 128:
            raise ValueError("Password length must be between 1 and 128")
        return value


class RegisterRequest(LoginRequest):
    password: SecretStr = Field(min_length=15, max_length=128)
    display_name: Name

    @field_validator("display_name")
    @classmethod
    def valid_name(cls, value: str):
        value = value.strip()
        if not value or any(unicodedata.category(c).startswith("C") for c in value):
            raise ValueError("Invalid display name")
        return value

    @field_validator("password")
    @classmethod
    def strong_password(cls, value: SecretStr):
        if len(value.get_secret_value()) < 15:
            raise ValueError("Use at least 15 characters")
        return value


class UserView(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    email: str
    display_name: str
    role: Role
    account_status: AccountStatus
    version: int
    created_at: datetime


class ScopeView(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    user_id: UUID
    institution_id: UUID
    scope_type: Literal["institution"] = "institution"
    status: ScopeStatus
    version: int
    reason: str
    granted_by: UUID
    granted_at: datetime
    revoked_by: UUID | None
    revoked_at: datetime | None


class MeResponse(BaseModel):
    user: UserView
    admin_scopes: list[ScopeView]
    permission_version: int
    session_expires_at: datetime


class LoginResponse(MeResponse):
    access_token: str | None = None
    token_type: str | None = None


class RoleChange(StrictModel):
    role: Role
    expected_version: int = Field(ge=1)


class StatusChange(StrictModel):
    account_status: AccountStatus
    expected_version: int = Field(ge=1)


class ScopeCreate(StrictModel):
    user_id: UUID
    institution_id: UUID
    reason: str = Field(min_length=1, max_length=500)

    @field_validator("reason")
    @classmethod
    def valid_reason(cls, value: str):
        if not value.strip():
            raise ValueError("Reason is required")
        return value.strip()


class ScopeRevoke(StrictModel):
    expected_version: int = Field(ge=1)


class InstitutionCreate(StrictModel):
    name: Name

    @field_validator("name")
    @classmethod
    def valid_name(cls, value: str):
        value = value.strip()
        if not value:
            raise ValueError("Institution name is required")
        return value


class InstitutionView(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    name: str
    created_at: datetime


class UserList(BaseModel):
    items: list[UserView]
    next_cursor: UUID | None


class ScopeList(BaseModel):
    items: list[ScopeView]
    next_cursor: UUID | None = None


class InstitutionList(BaseModel):
    items: list[InstitutionView]
    next_cursor: UUID | None = None
