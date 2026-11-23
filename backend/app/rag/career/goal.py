"""The job a student is preparing for. Other career features start from this goal.

A goal is a Work24 occupation category (the same codes as job search) with optional detail words.
It is private planning data like the planning profile; it is never sent anywhere by itself.
"""

from datetime import datetime
from typing import Annotated

from pydantic import Field, field_validator, model_validator

from app.core.auth_errors import conflict
from app.models.personal import CareerGoal
from app.schemas.auth import StrictModel
from app.services.access import locked_identity
from app.services.personal import commit

from . import categories
from .search_terms import search_terms

OccupationCode = Annotated[str, Field(pattern=r"^[0-9]{2}[0-9A-Z]?$")]


class CareerGoalData(StrictModel):
    category_codes: list[OccupationCode] = Field(default_factory=list, max_length=10)
    keyword: str = Field(default="", max_length=80)

    @field_validator("keyword")
    @classmethod
    def trimmed(cls, value):
        return " ".join(value.split())

    @model_validator(mode="after")
    def known(self):
        categories.validate_codes(self.category_codes)
        if self.keyword:
            search_terms(self.keyword)
        return self


class CareerGoalUpdate(CareerGoalData):
    expected_version: int = Field(ge=0, strict=True)


class CareerGoalView(CareerGoalData):
    version: int
    category_label: str | None = None
    updated_at: datetime | None = None


def view(item):
    if item is None:
        return CareerGoalView(version=0)
    codes = list(item.category_codes or [])
    return CareerGoalView(
        category_codes=codes,
        keyword=item.keyword,
        version=item.version,
        category_label=categories.label(codes) if codes else None,
        updated_at=item.updated_at,
    )


def get_goal(db, owner_id):
    return view(db.get(CareerGoal, owner_id))


def save_goal(db, request, payload):
    identity = locked_identity(db, request)
    item = db.get(CareerGoal, identity.user.id)
    if (item.version if item else 0) != payload.expected_version:
        raise conflict()
    if item is None:
        item = CareerGoal(owner_id=identity.user.id, version=1)
        db.add(item)
    else:
        item.version += 1
        item.updated_at = datetime.now().astimezone()
    item.category_codes = list(payload.category_codes)
    item.keyword = payload.keyword
    commit(db)
    db.refresh(item)
    return view(item)
