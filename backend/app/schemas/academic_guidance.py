"""Click-through reference guidance. Selecting a node never judges eligibility."""

from enum import StrEnum
from typing import Annotated, Literal
from uuid import UUID

from fastapi import Path
from pydantic import Field

from app.schemas.auth import StrictModel
from app.schemas.graduation import AuditIssue, GraduationContext

NodeId = Annotated[str, Path(pattern=r"^[A-Za-z0-9:_-]{1,200}$")]
AssetId = Annotated[str, Path(pattern=r"^[0-9a-f]{64}$")]


class GuidanceState(StrEnum):
    READY = "ready"
    NEEDS_SELECTION = "needs_selection"
    NEEDS_INPUT = "needs_input"
    UNAVAILABLE = "unavailable"


class GuidanceReason(StrEnum):
    MENU = "menu"
    UNKNOWN_NODE = "unknown_node"
    APPROVED_CONTENT_NOT_CONFIGURED = "approved_content_not_configured"
    VERIFIED_AUDIT_REQUIRED = "verified_audit_required"
    AUDIT_RENDERED = "audit_rendered"
    INVALID_AUDIT_PROJECTION = "invalid_audit_projection"
    CALENDAR_SNAPSHOT = "calendar_snapshot"
    DEPARTMENT_OVERVIEW = "department_overview"
    DEPARTMENT_SECTION = "department_section"
    DEPARTMENT_CONTENT_PENDING = "department_content_pending"
    REGULATION_EXCERPT = "regulation_excerpt"
    REGULATION_PAGE = "regulation_page"
    UNIVERSITY_REGULATION = "university_regulation"
    UNIVERSITY_PDF_PAGE = "university_pdf_page"
    SCHOLARSHIP_OVERVIEW = "scholarship_overview"
    SCHOLARSHIP_SECTION = "scholarship_section"
    SCHOLARSHIP_TABLE = "scholarship_table"
    SCHOLARSHIP_TABLE_ROW = "scholarship_table_row"
    CAREER_INPUTS_REQUIRED = "career_inputs_required"
    CAREER_SOURCES = "career_sources"


class GuidanceCardType(StrEnum):
    AUDIT_REQUIREMENT = "audit_requirement"
    CALENDAR_EVENT = "calendar_event"
    REFERENCE_TEXT = "reference_text"
    REFERENCE_TABLE = "reference_table"
    REGULATION_EXCERPT = "regulation_excerpt"
    REGULATION_METADATA = "regulation_metadata"
    REGULATION_PAGE = "regulation_page"


class GuidanceButton(StrictModel):
    id: str
    label: str
    action: Literal["select_node"]
    node_id: str
    availability: Literal["available", "content_pending"]


class GuidanceSource(StrictModel):
    type: (
        Literal["official_calendar", "official_pdf", "official_website", "provided_pdf"] | None
    ) = None
    title: str | None = None
    source_url: str | None = None
    page: int | None = None
    sha256: str | None = None
    fetched_at: str | None = None
    # Serve through GET /me/academic-guidance/assets/{asset_id}; never a file path.
    asset_id: str | None = None
    document_id: str | None = None
    filename: str | None = None
    chunk_id: UUID | None = None
    knowledge_document_id: UUID | None = None
    knowledge_version: int | None = None
    document_version: int | None = None
    content_hash: str | None = None
    document_hash: str | None = None


class GuidanceTableCell(StrictModel):
    text: str
    rowspan: int
    colspan: int
    header: bool


class GuidanceTable(StrictModel):
    caption: str | None = None
    rows: list[list[GuidanceTableCell]]
    grid: list[list[str | None]]


class GuidanceQuantities(StrictModel):
    # Exact decimal strings; null never means zero.
    current: str | None = None
    required: str | None = None
    deficit: str | None = None


class GuidanceCard(StrictModel):
    type: GuidanceCardType
    title: str
    body: str
    sources: list[GuidanceSource] = Field(default_factory=list)
    start_date: str | None = None
    end_date: str | None = None
    date_text: str | None = None
    tables: list[list[list[str | None]]] | None = None
    table: GuidanceTable | None = None
    extraction_status: Literal["text_extracted", "ocr_unreviewed"] | None = None
    preferred_view: Literal["image"] | None = None
    image_asset_id: str | None = None
    # Audit requirement cards present the Rule Engine result; they do not recompute it.
    template_id: str | None = None
    rule_id: UUID | None = None
    rule_set_id: UUID | None = None
    rule_set_version: int | None = None
    kind: str | None = None
    status: str | None = None
    reason: str | None = None
    unit: str | None = None
    quantities: GuidanceQuantities | None = None
    missing_courses: list[str] = Field(default_factory=list)
    uncertain_courses: list[str] = Field(default_factory=list)
    source_state: Literal["available", "unavailable"] | None = None
    evidence_record_ids: list[UUID] = Field(default_factory=list)


class GuidanceCoverage(StrictModel):
    listed: int
    attachments: int
    without_attachments: int
    ocr_pages: int


class GuidanceWorkflow(StrictModel):
    id: str
    requires_authenticated_user: bool
    record_kinds: list[str]
    job_selection: str
    region_selection: str
    steps: list[str]


class GuidanceAudit(StrictModel):
    id: UUID
    context: GraduationContext
    evaluated_on: str
    status: str
    reason: str
    current_usable: bool
    catalog_complete: bool


class AcademicGuidance(StrictModel):
    schema_version: Literal["academic-click-v3"]
    node_id: str | None
    title: str | None = None
    state: GuidanceState
    reason: GuidanceReason
    message: str
    cards: list[GuidanceCard]
    warnings: list[str]
    buttons: list[GuidanceButton]
    fetched_at: str | None = None
    snapshot_stale: bool | None = None
    source: GuidanceSource | None = None
    scope: str | None = None
    campus: str | None = None
    coverage: GuidanceCoverage | None = None
    listing_status: Literal["listed", "moved", "withdrawn"] | None = None
    attachment_state: Literal["not_listed"] | None = None
    workflow: GuidanceWorkflow | None = None
    integration_state: Literal["connected", "adapter_not_connected"] | None = None
    missing_fields: list[str] = Field(default_factory=list)
    audit: GuidanceAudit | None = None
    issues: list[AuditIssue] = Field(default_factory=list)
    notice: str | None = None
