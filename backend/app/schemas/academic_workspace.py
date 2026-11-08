"""Administrator-only contracts for the shared school classification source."""

from datetime import datetime
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
