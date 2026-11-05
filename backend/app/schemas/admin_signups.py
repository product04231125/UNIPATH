"""Atomic account/request receipt with explicit school registration at approval."""

import unicodedata
from typing import Annotated
from uuid import UUID

from pydantic import Field, StringConstraints, field_validator, model_validator

from app.schemas.admin_applications import (
    ApplicationStatus as ApplicationStatus,
)
from app.schemas.admin_applications import (
    SchoolAdminApplicant,
    SchoolAdminApplicationApprove,
    SchoolAdminApplicationCancel,
    SchoolAdminApplicationReject,
    SchoolAdminApplicationView,
)
from app.schemas.auth import (
    InstitutionCreate,
    LoginResponse,
    RegisterRequest,
    StrictModel,
    normalized_email,
)

SchoolAdminSignupCancel = SchoolAdminApplicationCancel
SchoolAdminSignupReject = SchoolAdminApplicationReject


class SchoolAdminSignupDetails(StrictModel):
    client_id: UUID
    school_name: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=128)
    ]
    official_url: str = Field(default="", max_length=2048)
    position: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=128)]
    contact_email: str = Field(min_length=3, max_length=254)
    reason: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=1000)]
    _contact_email = field_validator("contact_email")(normalized_email)

    @field_validator("school_name")
    @classmethod
    def school_label(cls, value):
        if any(unicodedata.category(char).startswith("C") for char in value):
            raise ValueError("Invalid school name")
        return unicodedata.normalize("NFC", value)

    @field_validator("official_url")
    @classmethod
    def school_url(cls, value):
        from app.schemas.academic import safe_url

        return safe_url(value)


class SchoolAdminSignupRegister(RegisterRequest, SchoolAdminSignupDetails):
    pass


class SchoolAdminSignupApprove(SchoolAdminApplicationApprove):
    institution_id: UUID | None = None
    expected_institution_version: int | None = Field(default=None, ge=1, strict=True)
    new_institution: InstitutionCreate | None = None

    @model_validator(mode="after")
    def explicit_school_decision(self):
        if (self.institution_id is None) == (self.new_institution is None):
            raise ValueError("Choose an existing institution or explicitly register a new one")
        if (self.institution_id is None) != (self.expected_institution_version is None):
            raise ValueError("Existing institution requires its reviewed version")
        return self


class SchoolAdminSignupView(SchoolAdminApplicationView):
    institution_id: UUID | None
    institution_name: str | None
    school_name: str
    official_url: str


class SchoolAdminSignupReviewView(SchoolAdminSignupView):
    applicant: SchoolAdminApplicant


class SchoolAdminSignupList(StrictModel):
    items: list[SchoolAdminSignupView]
    next_cursor: UUID | None


class SchoolAdminSignupReviewList(StrictModel):
    items: list[SchoolAdminSignupReviewView]
    next_cursor: UUID | None


class SchoolAdminSignupResponse(LoginResponse):
    signup: SchoolAdminSignupView
