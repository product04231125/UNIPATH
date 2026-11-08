"""Administrator-only contracts for the shared school classification source."""

from datetime import datetime
from decimal import Decimal
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, Field, StringConstraints, model_validator

from app.schemas.auth import StrictModel

Label = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=128)]
ClientRef = Annotated[str, StringConstraints(pattern=r"^[A-Za-z0-9_-]{1,64}$")]
Digest = Annotated[str, StringConstraints(pattern=r"^[0-9a-f]{64}$")]


class ClassificationCreate(StrictModel):
    institution_id: UUID
    client_id: UUID
    copy_from_id: UUID | None = None


class ClassificationNodeInput(StrictModel):
    id: UUID | None = None
    client_ref: ClientRef | None = None
    parent_ref: str | None = Field(default=None, min_length=1, max_length=64)
    label: Label
    position: int = Field(ge=0, strict=True)
    selectable: bool = Field(default=True, strict=True)

    @model_validator(mode="after")
    def identity(self):
        if (self.id is None) == (self.client_ref is None):
            raise ValueError("Use an existing id or a new client_ref, exactly one")
        return self

    @property
    def key(self) -> str:
        return str(self.id) if self.id else self.client_ref


class ClassificationReplace(StrictModel):
    expected_version: int = Field(ge=1, strict=True)
    client_id: UUID
    nodes: list[ClassificationNodeInput] = Field(max_length=1000)

    @model_validator(mode="after")
    def tree(self):
        nodes = {node.key: node for node in self.nodes}
        if len(nodes) != len(self.nodes):
            raise ValueError("Node identities must be unique")
        positions = set()
        for node in self.nodes:
            key = (node.parent_ref, node.position)
            if key in positions:
                raise ValueError("Sibling positions must be unique")
            positions.add(key)
            seen = {node.key}
            parent = node.parent_ref
            while parent is not None:
                if parent in seen or parent not in nodes or len(seen) >= 8:
                    raise ValueError("Use an acyclic tree of depth at most eight")
                seen.add(parent)
                parent = nodes[parent].parent_ref
        return self


class ClassificationNodeView(BaseModel):
    model_config = {"from_attributes": True}
    id: UUID
    logical_id: UUID
    parent_id: UUID | None
    label: str
    position: int
    selectable: bool


class ClassificationHeader(BaseModel):
    model_config = {"from_attributes": True}
    id: UUID
    institution_id: UUID
    revision: int
    version: int
    status: Literal["draft", "published", "withdrawn"]
    digest: str | None
    published_at: datetime | None
    created_at: datetime
    updated_at: datetime


class ClassificationView(ClassificationHeader):
    nodes: list[ClassificationNodeView]
    id_map: dict[str, UUID] = Field(default_factory=dict)


class ClassificationList(BaseModel):
    items: list[ClassificationHeader]
    next_cursor: UUID | None


class PublicationInput(StrictModel):
    client_id: UUID
    expected_version: int = Field(ge=1, strict=True)
    expected_digest: Digest
    review_note: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=1000)
    ]


class VersionInput(StrictModel):
    expected_version: int = Field(ge=1, strict=True)


class PublicationPreview(BaseModel):
    id: UUID
    version: int
    digest: str
    issues: list[str]


class TrackCreate(StrictModel):
    institution_id: UUID
    client_id: UUID
    name: Label


class TrackUpdate(StrictModel):
    client_id: UUID
    expected_version: int = Field(ge=1, strict=True)
    name: Label
    inactive: bool = Field(strict=True)


class TrackView(BaseModel):
    model_config = {"from_attributes": True}
    id: UUID
    institution_id: UUID
    name: str
    version: int
    inactive_at: datetime | None


class TrackList(BaseModel):
    items: list[TrackView]
    next_cursor: UUID | None


class AcademicScopeClause(StrictModel):
    department_id: UUID | None = None
    admission_from: int | None = Field(default=None, ge=1000, le=9999, strict=True)
    admission_to: int | None = Field(default=None, ge=1000, le=9999, strict=True)
    track_mode: Literal["all", "selected"] = "all"
    track_ids: list[UUID] = Field(default_factory=list, max_length=32)

    @model_validator(mode="after")
    def consistent(self):
        if (self.admission_from is None) != (self.admission_to is None):
            raise ValueError("Set both admission-year bounds or neither")
        if self.admission_from is not None and self.admission_from > self.admission_to:
            raise ValueError("Admission interval is reversed")
        if (self.track_mode == "selected") != bool(self.track_ids):
            raise ValueError("Selected tracks require IDs; all tracks require an empty list")
        if len(set(self.track_ids)) != len(self.track_ids):
            raise ValueError("Track IDs must be unique")
        return self


class AcademicScope(StrictModel):
    clauses: list[AcademicScopeClause] = Field(default_factory=list, max_length=100)


Credits = Annotated[
    Decimal, Field(ge=0, le=100, max_digits=8, decimal_places=3, allow_inf_nan=False)
]
Requirement = Literal["required", "elective", "not_specified"]


class AcademicCurriculumCreate(StrictModel):
    institution_id: UUID
    client_id: UUID
    name: Label
    classification_revision_id: UUID
    curriculum_year: int | None = Field(default=None, ge=1000, le=9999, strict=True)
    legacy_curriculum_id: UUID | None = None


class AcademicCurriculumCourseInput(StrictModel):
    id: UUID | None = None
    client_ref: ClientRef | None = None
    course_id: UUID
    expected_course_version: int = Field(ge=1, strict=True)
    classification_node_id: UUID
    requirement: Requirement
    recognized_credits: Credits
    position: int = Field(ge=0, strict=True)

    @model_validator(mode="after")
    def identity(self):
        if (self.id is None) == (self.client_ref is None):
            raise ValueError("Use an existing entry id or a new client_ref")
        return self


class AcademicCurriculumReplace(StrictModel):
    expected_version: int = Field(ge=1, strict=True)
    client_id: UUID
    name: Label
    curriculum_year: int | None = Field(default=None, ge=1000, le=9999, strict=True)
    classification_revision_id: UUID
    scope: AcademicScope
    courses: list[AcademicCurriculumCourseInput] = Field(max_length=1000)

    @model_validator(mode="after")
    def unique_entries(self):
        for values in (
            [entry.course_id for entry in self.courses],
            [entry.position for entry in self.courses],
            [str(entry.id) if entry.id else entry.client_ref for entry in self.courses],
        ):
            if len(set(values)) != len(values):
                raise ValueError("Course identities and positions must be unique")
        return self


class AcademicCurriculumCourseView(BaseModel):
    model_config = {"from_attributes": True}
    id: UUID
    logical_id: UUID
    course_id: UUID
    course_version: int
    course_name: str
    course_code: str
    classification_node_id: UUID
    requirement: Requirement
    recognized_credits: Decimal
    position: int


class AcademicLegacyCurriculumCourse(BaseModel):
    course_id: UUID
    course_version: int
    course_name: str
    course_code: str
    credits: Decimal
    legacy_category: str
    legacy_required: bool


class AcademicCurriculumHeader(BaseModel):
    model_config = {"from_attributes": True}
    id: UUID
    institution_id: UUID
    lineage_id: UUID
    legacy_curriculum_id: UUID | None
    revision: int
    version: int
    name: str
    curriculum_year: int | None
    classification_revision_id: UUID
    status: Literal["draft", "published", "withdrawn"]
    digest: str | None


class AcademicCurriculumView(AcademicCurriculumHeader):
    scope: AcademicScope
    courses: list[AcademicCurriculumCourseView]
    legacy_courses: list[AcademicLegacyCurriculumCourse]
    id_map: dict[str, UUID] = Field(default_factory=dict)


class AcademicCurriculumList(BaseModel):
    items: list[AcademicCurriculumHeader]
    next_cursor: UUID | None


class AcademicNewCourse(StrictModel):
    name: Label
    code: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=64)]
    credits: Credits


class AcademicCourseEntryCreate(StrictModel):
    client_id: UUID
    expected_version: int = Field(ge=1, strict=True)
    course_id: UUID | None = None
    expected_course_version: int | None = Field(default=None, ge=1, strict=True)
    new_course: AcademicNewCourse | None = None
    classification_node_id: UUID
    requirement: Requirement
    recognized_credits: Credits

    @model_validator(mode="after")
    def exactly_one_source(self):
        if (self.course_id is None) == (self.new_course is None):
            raise ValueError("Select an existing course or create one, exactly one")
        if (self.course_id is not None) != (self.expected_course_version is not None):
            raise ValueError("Existing courses require their version")
        return self


class AcademicCopyInput(StrictModel):
    client_id: UUID
    expected_version: int = Field(ge=1, strict=True)
