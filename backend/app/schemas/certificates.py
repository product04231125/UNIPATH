"""Shared master data contracts; never assert a student's certificate possession."""

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator

from app.schemas.academic import Code, safe_url
from app.schemas.auth import Name, StrictModel


class ProviderCreate(StrictModel):
    code: Code
    name: Name
    official_url: str = Field(min_length=1, max_length=2048)
    _url = field_validator("official_url")(safe_url)


class CertificateCreate(ProviderCreate):
    provider_id: UUID


class RegistryUpdate(StrictModel):
    expected_version: int = Field(ge=1, strict=True)
    name: Name
    official_url: str = Field(min_length=1, max_length=2048)
    _url = field_validator("official_url")(safe_url)


class RegistryVersion(StrictModel):
    expected_version: int = Field(ge=1, strict=True)


class ProviderView(BaseModel):
    model_config = {"from_attributes": True}
    id: UUID
    code: str
    name: str
    official_url: str
    version: int
    status: Literal["active", "inactive"]
    created_at: datetime
    updated_at: datetime


class CertificateView(ProviderView):
    provider_id: UUID


class ProviderList(BaseModel):
    items: list[ProviderView]
    next_cursor: UUID | None = None


class CertificateList(BaseModel):
    items: list[CertificateView]
    next_cursor: UUID | None = None


class RegistryReference(BaseModel):
    id: UUID
    kind: Literal["rule_program", "protected_reference"]
    name: str


class RegistryReferences(BaseModel):
    items: list[RegistryReference]
