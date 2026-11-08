"""Typed editor documents. Stored descriptions never execute student judgments."""

from datetime import date
from decimal import Decimal
from typing import Annotated, Literal
from uuid import UUID, uuid4

from pydantic import BaseModel, Field, StringConstraints, model_validator

from app.schemas.academic_workspace import AcademicScope, Label
from app.schemas.auth import StrictModel

Text = Annotated[str, StringConstraints(max_length=8000)]
ShortText = Annotated[str, StringConstraints(max_length=128)]
Amount = Annotated[Decimal, Field(ge=0, max_digits=12, decimal_places=3, allow_inf_nan=False)]


class ChecklistLine(StrictModel):
    id: UUID = Field(default_factory=uuid4)
    text: Text
    scope: AcademicScope | None = None


class ChecklistContent(StrictModel):
    kind: Literal["checklist"]
    lines: list[ChecklistLine] = Field(default_factory=list, max_length=1000)


class CertificationItem(StrictModel):
    id: UUID = Field(default_factory=uuid4)
    label: Text
    kind: Literal[
        "text", "certificate", "volunteer", "credits", "grade", "document", "exemption"
    ] = "text"
    scope: AcademicScope | None = None


class CertificationGroup(StrictModel):
    id: UUID = Field(default_factory=uuid4)
    label: ShortText
    choice: Literal["all", "pickOne", "pickN"] = "all"
    pick_count: int | None = Field(default=None, ge=0, strict=True)
    items: list[CertificationItem] = Field(default_factory=list, max_length=1000)
    groups: list["CertificationGroup"] = Field(default_factory=list, max_length=1000)
    exemptions: list[Text] = Field(default_factory=list, max_length=100)
    scope: AcademicScope | None = None


class CertificationContent(StrictModel):
    kind: Literal["certification"]
    groups: list[CertificationGroup] = Field(default_factory=list, max_length=1000)
    # Explanation-only tables; not numeric evaluation criteria.
    tables: list["ExplanationTable"] = Field(default_factory=list, max_length=50)


class ExplanationTable(StrictModel):
    id: UUID = Field(default_factory=uuid4)
    group_id: UUID | None = None
    title: ShortText
    columns: list[ShortText] = Field(max_length=50)
    rows: list[list[Text]] = Field(max_length=100)

    @model_validator(mode="after")
    def rectangular(self):
        if any(len(row) != len(self.columns) for row in self.rows):
            raise ValueError("Explanation table rows must match the column count")
        return self


class CreditHeader(StrictModel):
    id: UUID = Field(default_factory=uuid4)
    parent_id: UUID | None = None
    label: ShortText
    position: int = Field(ge=0, strict=True)
    role: Literal["group", "value", "subtotal", "total"] = "value"
    classification_node_id: UUID | None = None
    match_mode: Literal["exact", "subtree"] = "subtree"
    requirement: Literal["required", "elective", "not_specified"] | None = None
    aggregate_members: list[UUID] = Field(default_factory=list, max_length=300)


class CreditRow(StrictModel):
    id: UUID = Field(default_factory=uuid4)
    label: ShortText
    note: Text = ""
    scope: AcademicScope | None = None


class CreditCell(StrictModel):
    row_id: UUID
    header_id: UUID
    state: Literal["empty", "number", "not_applicable"]
    value: Amount | None = None

    @model_validator(mode="after")
    def numeric_state(self):
        if (self.state == "number") != (self.value is not None):
            raise ValueError("Only numeric cells require a value")
        return self


class CreditContent(StrictModel):
    kind: Literal["credit_table"]
    headers: list[CreditHeader] = Field(default_factory=list, max_length=300)
    rows: list[CreditRow] = Field(default_factory=list, max_length=300)
    cells: list[CreditCell] = Field(default_factory=list, max_length=30000)

    @model_validator(mode="after")
    def references(self):
        headers = {h.id: h for h in self.headers}
        rows = {r.id for r in self.rows}
        if len(headers) != len(self.headers) or len(rows) != len(self.rows):
            raise ValueError("Header and row IDs must be unique")
        positions = set()
        for header in self.headers:
            key = (header.parent_id, header.position)
            if key in positions:
                raise ValueError("Sibling header positions must be unique")
            positions.add(key)
            seen = {header.id}
            parent = header.parent_id
            while parent:
                if parent in seen or parent not in headers or len(seen) >= 8:
                    raise ValueError("Header hierarchy must be acyclic and at most eight levels")
                seen.add(parent)
                parent = headers[parent].parent_id
            if any(
                member not in headers or member == header.id for member in header.aggregate_members
            ):
                raise ValueError("Use other headers in the same table as aggregate members")
            if header.role == "group" and (
                header.classification_node_id or header.requirement or header.aggregate_members
            ):
                raise ValueError("Map numeric leaf headers instead of header groups")
        visiting, visited = set(), set()

        def check_aggregate(header_id):
            if header_id in visiting:
                raise ValueError("Aggregate references must be acyclic")
            if header_id in visited:
                return
            visiting.add(header_id)
            for member in headers[header_id].aggregate_members:
                check_aggregate(member)
            visiting.remove(header_id)
            visited.add(header_id)

        for header_id in headers:
            check_aggregate(header_id)
        cell_keys = set()
        group_ids = {h.parent_id for h in self.headers if h.parent_id}
        for cell in self.cells:
            if (
                cell.row_id not in rows
                or cell.header_id not in headers
                or cell.header_id in group_ids
            ):
                raise ValueError("Cells require a row and a leaf header in the same table")
            key = (cell.row_id, cell.header_id)
            if key in cell_keys:
                raise ValueError("Cell coordinates must be unique")
            cell_keys.add(key)
        return self


Content = Annotated[
    ChecklistContent | CertificationContent | CreditContent, Field(discriminator="kind")
]


def content_nodes(content):
    if isinstance(content, ChecklistContent):
        yield from content.lines
    elif isinstance(content, CertificationContent):

        def walk(groups, depth=1):
            if depth > 8 and groups:
                raise ValueError("Certification nesting cannot exceed eight levels")
            for group in groups:
                yield group
                yield from group.items
                yield from walk(group.groups, depth + 1)

        yield from walk(content.groups)
    else:
        yield from content.headers
        yield from content.rows


class RequirementCreate(StrictModel):
    institution_id: UUID
    client_id: UUID
    name: Label
    kind: Literal["checklist", "certification", "credit_table"]
    classification_revision_id: UUID | None = None
    curriculum_revision_id: UUID | None = None
    legacy_rule_id: UUID | None = None
    effective_from: date | None = None
    effective_to: date | None = None


class RequirementReplace(StrictModel):
    client_id: UUID
    expected_version: int = Field(ge=1, strict=True)
    name: Label
    scope: AcademicScope
    classification_revision_id: UUID | None = None
    curriculum_revision_id: UUID | None = None
    content: Content
    effective_from: date | None = None
    effective_to: date | None = None

    @model_validator(mode="after")
    def stable_ids(self):
        if self.effective_from and self.effective_to and self.effective_from > self.effective_to:
            raise ValueError("Effective dates are reversed")
        nodes = list(content_nodes(self.content))
        ids = [node.id for node in nodes]
        if len(ids) > 1000 or len(set(ids)) != len(ids):
            raise ValueError("Use at most 1000 unique content identities")
        if isinstance(self.content, CertificationContent):
            table_ids = [table.id for table in self.content.tables]
            if len(set(table_ids)) != len(table_ids):
                raise ValueError("Explanation table IDs must be unique")
            groups = {node.id for node in nodes if isinstance(node, CertificationGroup)}
            if any(
                table.group_id is not None and table.group_id not in groups
                for table in self.content.tables
            ):
                raise ValueError("Explanation tables must belong to an existing group")
        return self


class RequirementHeader(BaseModel):
    model_config = {"from_attributes": True}
    id: UUID
    institution_id: UUID
    lineage_id: UUID
    revision: int
    version: int
    kind: Literal["checklist", "certification", "credit_table"]
    name: str
    status: Literal["draft", "published", "withdrawn"]
    classification_revision_id: UUID | None
    curriculum_revision_id: UUID | None
    legacy_rule_id: UUID | None
    legacy_rule_version: int | None
    digest: str | None
    effective_from: date | None
    effective_to: date | None


class RequirementView(RequirementHeader):
    scope: AcademicScope
    content: Content


class RequirementList(BaseModel):
    items: list[RequirementHeader]
    next_cursor: UUID | None


class RequirementWithdrawal(StrictModel):
    client_id: UUID
    expected_version: int = Field(ge=1, strict=True)
    reason: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=1000)]
