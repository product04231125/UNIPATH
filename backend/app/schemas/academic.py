"""Typed public catalog contracts. Definitions are reviewed descriptions, not code."""

from datetime import date, datetime
from decimal import Decimal
from typing import Annotated, Literal
from uuid import UUID

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
    field_validator,
    model_validator,
)

from app.schemas.auth import Name, StrictModel

Code = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=64)]


def safe_url(value: str) -> str:
    from urllib.parse import urlsplit

    if not value:
        return value
    url = urlsplit(value)
    if (
        url.scheme not in ("http", "https")
        or not url.hostname
        or url.username is not None
        or url.password is not None
        or any(c.isspace() or ord(c) < 32 for c in value)
    ):
        raise ValueError("Use an HTTP(S) URL without credentials")
    _ = url.port
    return value


class CatalogCreate(StrictModel):
    name: Name
    institution_id: UUID


class DepartmentCreate(CatalogCreate):
    code: Code


class CurriculumCreate(CatalogCreate):
    department_id: UUID
    year: int = Field(ge=1000, le=9999, strict=True)


class CourseCreate(CatalogCreate):
    code: Code
    credits: Decimal = Field(ge=0, le=100, max_digits=8, decimal_places=3, allow_inf_nan=False)


class CurriculumCourseCreate(CatalogCreate):
    curriculum_id: UUID
    course_id: UUID
    category: Literal["major", "general", "other"]
    required: bool = Field(strict=True)


class ReviewedCreate(CatalogCreate):
    department_id: UUID | None = None
    curriculum_id: UUID | None = None
    effective_from: date | None = None
    effective_to: date | None = None

    @model_validator(mode="after")
    def scope_and_dates(self):
        if self.curriculum_id and not self.department_id:
            raise ValueError("A curriculum requires a department")
        if self.effective_from and self.effective_to and self.effective_from > self.effective_to:
            raise ValueError("Effective dates are reversed")
        return self


class RuleSetCreate(ReviewedCreate):
    pass


class RuleCreate(ReviewedCreate):
    rule_set_id: UUID | None = None
    rule_type: Literal["credits", "required_course", "volunteer", "thesis", "certificate", "custom"]
    definition: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=8000)
    ]
    source_url: str = Field(default="", max_length=2048)
    _url = field_validator("source_url")(safe_url)


class DocumentCreate(ReviewedCreate):
    source_url: str = Field(min_length=1, max_length=2048)
    document_type: Literal["academic", "graduation", "other"]
    rule_id: UUID | None = None
    _url = field_validator("source_url")(safe_url)


class ExpectedVersion(StrictModel):
    expected_version: int = Field(ge=1)


class DepartmentUpdate(DepartmentCreate, ExpectedVersion):
    pass


class CurriculumUpdate(CurriculumCreate, ExpectedVersion):
    pass


class CourseUpdate(CourseCreate, ExpectedVersion):
    pass


class CurriculumCourseUpdate(CurriculumCourseCreate, ExpectedVersion):
    pass


class RuleSetUpdate(RuleSetCreate, ExpectedVersion):
    pass


class RuleUpdate(RuleCreate, ExpectedVersion):
    pass


class DocumentUpdate(DocumentCreate, ExpectedVersion):
    pass


class CatalogView(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    version: int
    created_by: UUID
    updated_by: UUID
    created_at: datetime
    updated_at: datetime
    status: Literal["active"] = "active"


class ReviewedView(CatalogView):
    status: Literal["draft", "applied"]
    lineage_id: UUID
    revision: int
    applied_by: UUID | None
    applied_at: datetime | None


class DepartmentView(DepartmentCreate, CatalogView):
    pass


class CurriculumView(CurriculumCreate, CatalogView):
    pass


class CourseView(CourseCreate, CatalogView):
    pass


class CurriculumCourseView(CurriculumCourseCreate, CatalogView):
    pass


class RuleSetView(RuleSetCreate, ReviewedView):
    pass


class RuleView(RuleCreate, ReviewedView):
    pass


class DocumentView(DocumentCreate, ReviewedView):
    pass


class ReferenceView(BaseModel):
    id: UUID
    kind: str
    name: str


class ReferenceList(BaseModel):
    items: list[ReferenceView]
    total: int


class AuditView(BaseModel):
    id: UUID
    actor_id: UUID | None
    target_id: UUID
    institution_id: UUID | None
    action: str
    kind: str
    occurred_at: datetime
    request_id: UUID | None
