"""Linking a registered school to collected guidance; never an official approval."""

from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, Field, StringConstraints

from app.schemas.auth import StrictModel

BundleId = Annotated[str, StringConstraints(pattern=r"^[a-z0-9-]{1,64}$")]
Edition = Annotated[str, StringConstraints(pattern=r"^[0-9a-f]{16}$")]


class GuidanceBundle(BaseModel):
    bundle_id: str
    name: str
    source_school: str
    official_url: str
    schema_version: str
    edition: str
    fetched_at: datetime
    availability: Literal["available", "unavailable"]


class GuidanceBundleList(BaseModel):
    items: list[GuidanceBundle]
    next_cursor: str | None = None


class GuidanceBindingView(BaseModel):
    institution_id: UUID
    # unbound: nothing linked. unavailable: the linked bundle is no longer served.
    state: Literal["unbound", "bound", "unavailable"]
    # 0 while unbound; send it back as expected_version.
    version: int
    bundle_id: str | None = None
    bound_edition: str | None = None
    bundle: GuidanceBundle | None = None
    # The data was refreshed after the link was saved; saving again confirms the new edition.
    edition_changed: bool = False
    updated_by: UUID | None = None
    updated_at: datetime | None = None


class GuidanceBindingSave(StrictModel):
    bundle_id: BundleId
    edition: Edition
    expected_version: int = Field(ge=0, strict=True)


class StudentGuidanceBinding(BaseModel):
    # school_required: the profile has no registered school yet.
    state: Literal["school_required", "unbound", "bound", "unavailable"]
    institution_id: UUID | None = None
    bundle: GuidanceBundle | None = None
