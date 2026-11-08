"""Student transport types; administrator documents remain read-only."""

from datetime import date, datetime
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import Field, model_validator

from app.schemas.academic_requirements import Content
from app.schemas.academic_workspace import AcademicCurriculumCourseView, Credits
from app.schemas.auth import StrictModel


class StudentAcademicCommand(StrictModel):
    client_id: UUID
    expected_version: int = Field(ge=0, strict=True)


class StudentAcademicContextInput(StrictModel):
    id: UUID | None = None
    department_id: UUID
    track_id: UUID
    curriculum_revision_id: UUID
    admission_year: int = Field(ge=1000, le=9999, strict=True)
    primary: bool = Field(strict=True)


class StudentAcademicCourseEntry(AcademicCurriculumCourseView):
    classification_label: str


class StudentAcademicContextView(StudentAcademicContextInput):
    id: UUID
    institution_id: UUID
    department_name: str
    track_name: str
    curriculum_name: str
    curriculum_revision: int
    courses: list[StudentAcademicCourseEntry]


class StudentAcademicContextsSave(StudentAcademicCommand):
    contexts: list[StudentAcademicContextInput] = Field(max_length=20)

    @model_validator(mode="after")
    def unique(self):
        if self.contexts and sum(c.primary for c in self.contexts) != 1:
            raise ValueError("Choose exactly one primary context")
        ids = [c.id for c in self.contexts if c.id]
        if len(set(ids)) != len(ids):
            raise ValueError("Context IDs must be unique")
        keys = [(c.department_id, c.track_id, c.curriculum_revision_id) for c in self.contexts]
        if len(set(keys)) != len(keys):
            raise ValueError("Do not repeat an academic context")
        return self


class StudentAcademicWorkspaceView(StrictModel):
    owner_id: UUID
    version: int
    institution_id: UUID | None
    contexts: list[StudentAcademicContextView]
    issues: list[str]


class StudentAcademicChoice(StrictModel):
    id: UUID
    name: str


class StudentAcademicCurriculumOption(StudentAcademicChoice):
    revision: int
    lineage_id: UUID
    scope: dict


class StudentAcademicOptions(StrictModel):
    institution_id: UUID
    departments: list[StudentAcademicChoice]
    tracks: list[StudentAcademicChoice]
    curricula: list[StudentAcademicCurriculumOption]


class StudentAcademicRecordReference(StrictModel):
    kind: Literal["course", "activity", "experience", "credential", "achievement"]
    record_id: UUID
    expected_version: int = Field(ge=1, strict=True)


class StudentAcademicResponseSave(StudentAcademicCommand):
    activation_id: UUID
    value: bool | None = Field(strict=True)
    records: list[StudentAcademicRecordReference] = Field(default_factory=list, max_length=100)

    @model_validator(mode="after")
    def unique(self):
        keys = [(r.kind, r.record_id) for r in self.records]
        if len(keys) != len(set(keys)):
            raise ValueError("Record references must be unique")
        return self


class StudentAcademicRecordSnapshot(StrictModel):
    kind: str
    record_id: UUID
    version: int
    title: str
    available: bool
    current_version: int | None


class StudentAcademicResponseView(StrictModel):
    item_id: UUID
    value: bool | None
    previous_value: bool | None
    version: int
    confirmed_at: datetime
    stale: bool
    records: list[StudentAcademicRecordSnapshot]


class StudentAcademicDocumentView(StrictModel):
    id: UUID
    lineage_id: UUID
    revision: int
    name: str
    kind: Literal["checklist", "certification", "credit_table"]
    content: Content
    context_ids: list[UUID]
    node_contexts: dict[str, list[UUID]]
    status: Literal["published", "withdrawn"]
    usable: bool = True
    effective_from: date | None = None
    effective_to: date | None = None
    responses: list[StudentAcademicResponseView] = Field(default_factory=list)
    group_results: dict[str, Literal["satisfied", "not_satisfied", "needs_review"]] = Field(
        default_factory=dict
    )


class StudentAcademicChange(StrictModel):
    name: str
    kind: Literal["added", "removed", "changed"]
    detail: str


class StudentAcademicCurriculumUpdate(StrictModel):
    context_id: UUID
    current_revision_id: UUID
    new_revision_id: UUID
    name: str
    revision: int


class StudentAcademicPreview(StrictModel):
    owner_id: UUID
    workspace_version: int
    active_activation_id: UUID | None
    digest: str
    issues: list[str]
    documents: list[StudentAcademicDocumentView]
    changes: list[StudentAcademicChange]
    curriculum_updates: list[StudentAcademicCurriculumUpdate] = Field(default_factory=list)


class StudentAcademicActivate(StudentAcademicCommand):
    expected_digest: str = Field(pattern=r"^[0-9a-f]{64}$")


class StudentAcademicRequirements(StrictModel):
    owner_id: UUID
    workspace_version: int
    activation_id: UUID | None
    issues: list[str]
    documents: list[StudentAcademicDocumentView]


class StudentAcademicCourseSave(StudentAcademicCommand):
    context_id: UUID
    entry_id: UUID
    expected_record_version: int = Field(ge=1, strict=True)
    result: Literal["completed", "not_completed", "needs_review"]
    earned_credits: Credits | None = None
    included: bool = Field(default=True, strict=True)

    @model_validator(mode="after")
    def credits(self):
        if self.result == "completed" and self.earned_credits is None:
            raise ValueError("Completed records require earned credits")
        return self


class StudentAcademicCourseView(StrictModel):
    id: UUID
    owner_id: UUID
    course_record_id: UUID
    context_id: UUID
    entry_id: UUID
    record_version: int
    result: str
    earned_credits: Decimal | None
    included: bool
    version: int


class StudentAcademicCreditEvidence(StrictModel):
    record_id: UUID
    context_id: UUID | None
    title: str
    state: Literal["included", "excluded", "needs_review"]
    reason: str
    credits: Decimal | None


class StudentAcademicCreditCell(StrictModel):
    row_id: UUID
    header_id: UUID
    target: Decimal | None
    earned: Decimal | None
    remaining: Decimal | None
    status: Literal["satisfied", "not_satisfied", "needs_review", "not_applicable", "no_target"]
    evidence: list[StudentAcademicCreditEvidence]
    issues: list[str] = Field(default_factory=list)


class StudentAcademicHistoryItem(StrictModel):
    id: UUID
    created_at: datetime
    active: bool
    document_count: int


class StudentAcademicHistory(StrictModel):
    owner_id: UUID
    items: list[StudentAcademicHistoryItem]


class StudentAcademicCreditTable(StrictModel):
    requirement_revision_id: UUID
    cells: list[StudentAcademicCreditCell]


class StudentAcademicCreditProgress(StrictModel):
    owner_id: UUID
    activation_id: UUID | None
    issues: list[str]
    tables: list[StudentAcademicCreditTable]
    links: list[StudentAcademicCourseView]
