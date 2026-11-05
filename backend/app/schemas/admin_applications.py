"""No request may choose an applicant, role, scope or approval flag."""

from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, Field, StringConstraints, field_validator, model_validator

from app.schemas.auth import StrictModel, normalized_email

ApplicationStatus = Literal["pending", "approved", "rejected", "cancelled"]
Reason = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=500)]


class SchoolAdminApplicationCreate(StrictModel):
    institution_id: UUID
    client_id: UUID
    position: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=128)]
    contact_email: str = Field(min_length=3, max_length=254)
    reason: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=1000)]
    _email = field_validator("contact_email")(normalized_email)


class SchoolAdminApplicationCancel(StrictModel):
    expected_version: int = Field(ge=1, strict=True)


class SchoolAdminApplicationReject(SchoolAdminApplicationCancel):
    review_note: Reason


class SchoolAdminApplicationApprove(SchoolAdminApplicationReject):
    expected_user_version: int = Field(ge=1, strict=True)
    identity_verified: bool = Field(strict=True)
    affiliation_verified: bool = Field(strict=True)

    @model_validator(mode="after")
    def reviewed_identity(self):
        if not self.identity_verified or not self.affiliation_verified:
            raise ValueError("Identity and school affiliation must both be reviewed")
        return self


class SchoolAdminApplicationView(BaseModel):
    id: UUID
    applicant_id: UUID
    institution_id: UUID
    institution_name: str
    client_id: UUID
    position: str
    contact_email: str
    reason: str
    status: ApplicationStatus
    version: int
    created_at: datetime
    updated_at: datetime
    reviewed_by: UUID | None
    reviewed_at: datetime | None
    review_note: str
    identity_verified: bool
    affiliation_verified: bool
    granted_scope_id: UUID | None


class SchoolAdminApplicant(BaseModel):
    id: UUID
    email: str
    display_name: str
    role: Literal["user", "school_admin", "super_admin"]
    account_status: Literal["active", "suspended"]
    version: int


class SchoolAdminApplicationReviewView(SchoolAdminApplicationView):
    applicant: SchoolAdminApplicant


class SchoolAdminApplicationList(BaseModel):
    items: list[SchoolAdminApplicationView]
    next_cursor: UUID | None


class SchoolAdminApplicationReviewList(BaseModel):
    items: list[SchoolAdminApplicationReviewView]
    next_cursor: UUID | None
