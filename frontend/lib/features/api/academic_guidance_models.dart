// GENERATED: scripts/export_academic_guidance_contracts.py.
// Reference guidance never judges eligibility. No storage or UI effects.
abstract interface class AcademicGuidancePayload {
  Map<String, Object?> toJson();
}

Object _constant(Object? value, Object expected) {
  if (value != expected) {
    throw const FormatException('Unexpected contract constant');
  }
  return expected;
}

String _choice(Object? value, List<String> allowed) {
  if (value is! String || !allowed.contains(value)) {
    throw const FormatException('Unknown contract value');
  }
  return value;
}

class GuidanceButton implements AcademicGuidancePayload {
  const GuidanceButton({
    required this.id,
    required this.label,
    required this.action,
    required this.nodeId,
    required this.availability,
  });
  final String id;
  final String label;
  final String action;
  final String nodeId;
  final String availability;
  factory GuidanceButton.fromJson(Map<String, dynamic> value) => GuidanceButton(
    id: value['id'] as String,
    label: value['label'] as String,
    action: _constant(value['action'], "select_node") as String,
    nodeId: value['node_id'] as String,
    availability: _choice(value['availability'], [
      "available",
      "content_pending",
    ]),
  );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'action': action,
    'node_id': nodeId,
    'availability': availability,
  };
}

class GuidanceSource implements AcademicGuidancePayload {
  const GuidanceSource({
    this.type,
    this.title,
    this.sourceUrl,
    this.page,
    this.sha256,
    this.fetchedAt,
    this.assetId,
    this.documentId,
    this.filename,
    this.chunkId,
    this.knowledgeDocumentId,
    this.knowledgeVersion,
    this.documentVersion,
    this.contentHash,
    this.documentHash,
  });
  final String? type;
  final String? title;
  final String? sourceUrl;
  final int? page;
  final String? sha256;
  final String? fetchedAt;
  final String? assetId;
  final String? documentId;
  final String? filename;
  final String? chunkId;
  final String? knowledgeDocumentId;
  final int? knowledgeVersion;
  final int? documentVersion;
  final String? contentHash;
  final String? documentHash;
  factory GuidanceSource.fromJson(Map<String, dynamic> value) => GuidanceSource(
    type: value['type'] == null
        ? null
        : _choice(value['type'], [
            "official_calendar",
            "official_pdf",
            "official_website",
            "provided_pdf",
          ]),
    title: value['title'] == null ? null : value['title'] as String,
    sourceUrl: value['source_url'] == null
        ? null
        : value['source_url'] as String,
    page: value['page'] == null ? null : value['page'] as int,
    sha256: value['sha256'] == null ? null : value['sha256'] as String,
    fetchedAt: value['fetched_at'] == null
        ? null
        : value['fetched_at'] as String,
    assetId: value['asset_id'] == null ? null : value['asset_id'] as String,
    documentId: value['document_id'] == null
        ? null
        : value['document_id'] as String,
    filename: value['filename'] == null ? null : value['filename'] as String,
    chunkId: value['chunk_id'] == null ? null : value['chunk_id'] as String,
    knowledgeDocumentId: value['knowledge_document_id'] == null
        ? null
        : value['knowledge_document_id'] as String,
    knowledgeVersion: value['knowledge_version'] == null
        ? null
        : value['knowledge_version'] as int,
    documentVersion: value['document_version'] == null
        ? null
        : value['document_version'] as int,
    contentHash: value['content_hash'] == null
        ? null
        : value['content_hash'] as String,
    documentHash: value['document_hash'] == null
        ? null
        : value['document_hash'] as String,
  );
  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'title': title,
    'source_url': sourceUrl,
    'page': page,
    'sha256': sha256,
    'fetched_at': fetchedAt,
    'asset_id': assetId,
    'document_id': documentId,
    'filename': filename,
    'chunk_id': chunkId,
    'knowledge_document_id': knowledgeDocumentId,
    'knowledge_version': knowledgeVersion,
    'document_version': documentVersion,
    'content_hash': contentHash,
    'document_hash': documentHash,
  };
}

class GuidanceTableCell implements AcademicGuidancePayload {
  const GuidanceTableCell({
    required this.text,
    required this.rowspan,
    required this.colspan,
    required this.header,
  });
  final String text;
  final int rowspan;
  final int colspan;
  final bool header;
  factory GuidanceTableCell.fromJson(Map<String, dynamic> value) =>
      GuidanceTableCell(
        text: value['text'] as String,
        rowspan: value['rowspan'] as int,
        colspan: value['colspan'] as int,
        header: value['header'] as bool,
      );
  @override
  Map<String, Object?> toJson() => {
    'text': text,
    'rowspan': rowspan,
    'colspan': colspan,
    'header': header,
  };
}

class GuidanceTable implements AcademicGuidancePayload {
  const GuidanceTable({this.caption, required this.rows, required this.grid});
  final String? caption;
  final List<List<GuidanceTableCell>> rows;
  final List<List<String?>> grid;
  factory GuidanceTable.fromJson(Map<String, dynamic> value) => GuidanceTable(
    caption: value['caption'] == null ? null : value['caption'] as String,
    rows: List.unmodifiable(
      (value['rows'] as List).map(
        (v) => List<GuidanceTableCell>.unmodifiable(
          (v as List).map(
            (v) =>
                GuidanceTableCell.fromJson(Map<String, dynamic>.from(v as Map)),
          ),
        ),
      ),
    ),
    grid: List.unmodifiable(
      (value['grid'] as List).map(
        (v) => List<String?>.unmodifiable(
          (v as List).map((v) => v == null ? null : v as String),
        ),
      ),
    ),
  );
  @override
  Map<String, Object?> toJson() => {
    'caption': caption,
    'rows': rows.map((v) => v.map((v) => v.toJson()).toList()).toList(),
    'grid': grid.map((v) => v.map((v) => v).toList()).toList(),
  };
}

class GuidanceQuantities implements AcademicGuidancePayload {
  const GuidanceQuantities({this.current, this.required, this.deficit});
  final String? current;
  final String? required;
  final String? deficit;
  factory GuidanceQuantities.fromJson(Map<String, dynamic> value) =>
      GuidanceQuantities(
        current: value['current'] == null ? null : value['current'] as String,
        required: value['required'] == null
            ? null
            : value['required'] as String,
        deficit: value['deficit'] == null ? null : value['deficit'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'current': current,
    'required': required,
    'deficit': deficit,
  };
}

class GuidanceCard implements AcademicGuidancePayload {
  const GuidanceCard({
    required this.type,
    required this.title,
    required this.body,
    this.sources = const [],
    this.startDate,
    this.endDate,
    this.dateText,
    this.tables,
    this.table,
    this.extractionStatus,
    this.preferredView,
    this.imageAssetId,
    this.templateId,
    this.ruleId,
    this.ruleSetId,
    this.ruleSetVersion,
    this.kind,
    this.status,
    this.reason,
    this.unit,
    this.quantities,
    this.missingCourses = const [],
    this.uncertainCourses = const [],
    this.sourceState,
    this.evidenceRecordIds = const [],
  });
  final String type;
  final String title;
  final String body;
  final List<GuidanceSource> sources;
  final String? startDate;
  final String? endDate;
  final String? dateText;
  final List<List<List<String?>>>? tables;
  final GuidanceTable? table;
  final String? extractionStatus;
  final String? preferredView;
  final String? imageAssetId;
  final String? templateId;
  final String? ruleId;
  final String? ruleSetId;
  final int? ruleSetVersion;
  final String? kind;
  final String? status;
  final String? reason;
  final String? unit;
  final GuidanceQuantities? quantities;
  final List<String> missingCourses;
  final List<String> uncertainCourses;
  final String? sourceState;
  final List<String> evidenceRecordIds;
  factory GuidanceCard.fromJson(Map<String, dynamic> value) => GuidanceCard(
    type: _choice(value['type'], [
      "audit_requirement",
      "calendar_event",
      "reference_text",
      "reference_table",
      "regulation_excerpt",
      "regulation_metadata",
      "regulation_page",
    ]),
    title: value['title'] as String,
    body: value['body'] as String,
    sources: value['sources'] == null
        ? const []
        : List.unmodifiable(
            (value['sources'] as List).map(
              (v) =>
                  GuidanceSource.fromJson(Map<String, dynamic>.from(v as Map)),
            ),
          ),
    startDate: value['start_date'] == null
        ? null
        : value['start_date'] as String,
    endDate: value['end_date'] == null ? null : value['end_date'] as String,
    dateText: value['date_text'] == null ? null : value['date_text'] as String,
    tables: value['tables'] == null
        ? null
        : List.unmodifiable(
            (value['tables'] as List).map(
              (v) => List<List<String?>>.unmodifiable(
                (v as List).map(
                  (v) => List<String?>.unmodifiable(
                    (v as List).map((v) => v == null ? null : v as String),
                  ),
                ),
              ),
            ),
          ),
    table: value['table'] == null
        ? null
        : GuidanceTable.fromJson(
            Map<String, dynamic>.from(value['table'] as Map),
          ),
    extractionStatus: value['extraction_status'] == null
        ? null
        : _choice(value['extraction_status'], [
            "text_extracted",
            "ocr_unreviewed",
          ]),
    preferredView: value['preferred_view'] == null
        ? null
        : _constant(value['preferred_view'], "image") as String,
    imageAssetId: value['image_asset_id'] == null
        ? null
        : value['image_asset_id'] as String,
    templateId: value['template_id'] == null
        ? null
        : value['template_id'] as String,
    ruleId: value['rule_id'] == null ? null : value['rule_id'] as String,
    ruleSetId: value['rule_set_id'] == null
        ? null
        : value['rule_set_id'] as String,
    ruleSetVersion: value['rule_set_version'] == null
        ? null
        : value['rule_set_version'] as int,
    kind: value['kind'] == null ? null : value['kind'] as String,
    status: value['status'] == null ? null : value['status'] as String,
    reason: value['reason'] == null ? null : value['reason'] as String,
    unit: value['unit'] == null ? null : value['unit'] as String,
    quantities: value['quantities'] == null
        ? null
        : GuidanceQuantities.fromJson(
            Map<String, dynamic>.from(value['quantities'] as Map),
          ),
    missingCourses: value['missing_courses'] == null
        ? const []
        : List.unmodifiable(
            (value['missing_courses'] as List).map((v) => v as String),
          ),
    uncertainCourses: value['uncertain_courses'] == null
        ? const []
        : List.unmodifiable(
            (value['uncertain_courses'] as List).map((v) => v as String),
          ),
    sourceState: value['source_state'] == null
        ? null
        : _choice(value['source_state'], ["available", "unavailable"]),
    evidenceRecordIds: value['evidence_record_ids'] == null
        ? const []
        : List.unmodifiable(
            (value['evidence_record_ids'] as List).map((v) => v as String),
          ),
  );
  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'title': title,
    'body': body,
    'sources': sources.map((v) => v.toJson()).toList(),
    'start_date': startDate,
    'end_date': endDate,
    'date_text': dateText,
    'tables': tables
        ?.map((v) => v.map((v) => v.map((v) => v).toList()).toList())
        .toList(),
    'table': table?.toJson(),
    'extraction_status': extractionStatus,
    'preferred_view': preferredView,
    'image_asset_id': imageAssetId,
    'template_id': templateId,
    'rule_id': ruleId,
    'rule_set_id': ruleSetId,
    'rule_set_version': ruleSetVersion,
    'kind': kind,
    'status': status,
    'reason': reason,
    'unit': unit,
    'quantities': quantities?.toJson(),
    'missing_courses': missingCourses.map((v) => v).toList(),
    'uncertain_courses': uncertainCourses.map((v) => v).toList(),
    'source_state': sourceState,
    'evidence_record_ids': evidenceRecordIds.map((v) => v).toList(),
  };
}

class GuidanceCoverage implements AcademicGuidancePayload {
  const GuidanceCoverage({
    required this.listed,
    required this.attachments,
    required this.withoutAttachments,
    required this.ocrPages,
  });
  final int listed;
  final int attachments;
  final int withoutAttachments;
  final int ocrPages;
  factory GuidanceCoverage.fromJson(Map<String, dynamic> value) =>
      GuidanceCoverage(
        listed: value['listed'] as int,
        attachments: value['attachments'] as int,
        withoutAttachments: value['without_attachments'] as int,
        ocrPages: value['ocr_pages'] as int,
      );
  @override
  Map<String, Object?> toJson() => {
    'listed': listed,
    'attachments': attachments,
    'without_attachments': withoutAttachments,
    'ocr_pages': ocrPages,
  };
}

class GuidanceWorkflow implements AcademicGuidancePayload {
  const GuidanceWorkflow({
    required this.id,
    required this.requiresAuthenticatedUser,
    required this.recordKinds,
    required this.jobSelection,
    required this.regionSelection,
    required this.steps,
  });
  final String id;
  final bool requiresAuthenticatedUser;
  final List<String> recordKinds;
  final String jobSelection;
  final String regionSelection;
  final List<String> steps;
  factory GuidanceWorkflow.fromJson(Map<String, dynamic> value) =>
      GuidanceWorkflow(
        id: value['id'] as String,
        requiresAuthenticatedUser: value['requires_authenticated_user'] as bool,
        recordKinds: List.unmodifiable(
          (value['record_kinds'] as List).map((v) => v as String),
        ),
        jobSelection: value['job_selection'] as String,
        regionSelection: value['region_selection'] as String,
        steps: List.unmodifiable(
          (value['steps'] as List).map((v) => v as String),
        ),
      );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'requires_authenticated_user': requiresAuthenticatedUser,
    'record_kinds': recordKinds.map((v) => v).toList(),
    'job_selection': jobSelection,
    'region_selection': regionSelection,
    'steps': steps.map((v) => v).toList(),
  };
}

class GuidanceGraduationContext implements AcademicGuidancePayload {
  const GuidanceGraduationContext({
    required this.institutionId,
    required this.departmentId,
    required this.curriculumId,
    required this.admissionYear,
    required this.track,
  });
  final String institutionId;
  final String departmentId;
  final String curriculumId;
  final int admissionYear;
  final String track;
  factory GuidanceGraduationContext.fromJson(Map<String, dynamic> value) =>
      GuidanceGraduationContext(
        institutionId: value['institution_id'] as String,
        departmentId: value['department_id'] as String,
        curriculumId: value['curriculum_id'] as String,
        admissionYear: value['admission_year'] as int,
        track: value['track'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'institution_id': institutionId,
    'department_id': departmentId,
    'curriculum_id': curriculumId,
    'admission_year': admissionYear,
    'track': track,
  };
}

class GuidanceAuditIssue implements AcademicGuidancePayload {
  const GuidanceAuditIssue({required this.kind, required this.reason});
  final String kind;
  final String reason;
  factory GuidanceAuditIssue.fromJson(Map<String, dynamic> value) =>
      GuidanceAuditIssue(
        kind: _choice(value['kind'], [
          "catalog",
          "records",
          "academics",
          "volunteers",
          "certificates",
          "theses",
        ]),
        reason: value['reason'] as String,
      );
  @override
  Map<String, Object?> toJson() => {'kind': kind, 'reason': reason};
}

class GuidanceAudit implements AcademicGuidancePayload {
  const GuidanceAudit({
    required this.id,
    required this.context,
    required this.evaluatedOn,
    required this.status,
    required this.reason,
    required this.currentUsable,
    required this.catalogComplete,
  });
  final String id;
  final GuidanceGraduationContext context;
  final String evaluatedOn;
  final String status;
  final String reason;
  final bool currentUsable;
  final bool catalogComplete;
  factory GuidanceAudit.fromJson(Map<String, dynamic> value) => GuidanceAudit(
    id: value['id'] as String,
    context: GuidanceGraduationContext.fromJson(
      Map<String, dynamic>.from(value['context'] as Map),
    ),
    evaluatedOn: value['evaluated_on'] as String,
    status: value['status'] as String,
    reason: value['reason'] as String,
    currentUsable: value['current_usable'] as bool,
    catalogComplete: value['catalog_complete'] as bool,
  );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'context': context.toJson(),
    'evaluated_on': evaluatedOn,
    'status': status,
    'reason': reason,
    'current_usable': currentUsable,
    'catalog_complete': catalogComplete,
  };
}

class AcademicGuidance implements AcademicGuidancePayload {
  const AcademicGuidance({
    required this.schemaVersion,
    required this.nodeId,
    this.title,
    required this.state,
    required this.reason,
    required this.message,
    required this.cards,
    required this.warnings,
    required this.buttons,
    this.fetchedAt,
    this.snapshotStale,
    this.source,
    this.scope,
    this.campus,
    this.coverage,
    this.listingStatus,
    this.attachmentState,
    this.workflow,
    this.integrationState,
    this.missingFields = const [],
    this.audit,
    this.issues = const [],
    this.notice,
  });
  final String schemaVersion;
  final String? nodeId;
  final String? title;
  final String state;
  final String reason;
  final String message;
  final List<GuidanceCard> cards;
  final List<String> warnings;
  final List<GuidanceButton> buttons;
  final String? fetchedAt;
  final bool? snapshotStale;
  final GuidanceSource? source;
  final String? scope;
  final String? campus;
  final GuidanceCoverage? coverage;
  final String? listingStatus;
  final String? attachmentState;
  final GuidanceWorkflow? workflow;
  final String? integrationState;
  final List<String> missingFields;
  final GuidanceAudit? audit;
  final List<GuidanceAuditIssue> issues;
  final String? notice;
  factory AcademicGuidance.fromJson(Map<String, dynamic> value) =>
      AcademicGuidance(
        schemaVersion:
            _constant(value['schema_version'], "academic-click-v3") as String,
        nodeId: value['node_id'] == null ? null : value['node_id'] as String,
        title: value['title'] == null ? null : value['title'] as String,
        state: _choice(value['state'], [
          "ready",
          "needs_selection",
          "needs_input",
          "unavailable",
        ]),
        reason: _choice(value['reason'], [
          "menu",
          "unknown_node",
          "approved_content_not_configured",
          "verified_audit_required",
          "audit_rendered",
          "invalid_audit_projection",
          "calendar_snapshot",
          "department_overview",
          "department_section",
          "department_content_pending",
          "regulation_excerpt",
          "regulation_page",
          "university_regulation",
          "university_pdf_page",
          "scholarship_overview",
          "scholarship_section",
          "scholarship_table",
          "scholarship_table_row",
          "career_inputs_required",
          "career_sources",
          "school_required",
          "school_guidance_not_connected",
        ]),
        message: value['message'] as String,
        cards: List.unmodifiable(
          (value['cards'] as List).map(
            (v) => GuidanceCard.fromJson(Map<String, dynamic>.from(v as Map)),
          ),
        ),
        warnings: List.unmodifiable(
          (value['warnings'] as List).map((v) => v as String),
        ),
        buttons: List.unmodifiable(
          (value['buttons'] as List).map(
            (v) => GuidanceButton.fromJson(Map<String, dynamic>.from(v as Map)),
          ),
        ),
        fetchedAt: value['fetched_at'] == null
            ? null
            : value['fetched_at'] as String,
        snapshotStale: value['snapshot_stale'] == null
            ? null
            : value['snapshot_stale'] as bool,
        source: value['source'] == null
            ? null
            : GuidanceSource.fromJson(
                Map<String, dynamic>.from(value['source'] as Map),
              ),
        scope: value['scope'] == null ? null : value['scope'] as String,
        campus: value['campus'] == null ? null : value['campus'] as String,
        coverage: value['coverage'] == null
            ? null
            : GuidanceCoverage.fromJson(
                Map<String, dynamic>.from(value['coverage'] as Map),
              ),
        listingStatus: value['listing_status'] == null
            ? null
            : _choice(value['listing_status'], [
                "listed",
                "moved",
                "withdrawn",
              ]),
        attachmentState: value['attachment_state'] == null
            ? null
            : _constant(value['attachment_state'], "not_listed") as String,
        workflow: value['workflow'] == null
            ? null
            : GuidanceWorkflow.fromJson(
                Map<String, dynamic>.from(value['workflow'] as Map),
              ),
        integrationState: value['integration_state'] == null
            ? null
            : _choice(value['integration_state'], [
                "connected",
                "adapter_not_connected",
              ]),
        missingFields: value['missing_fields'] == null
            ? const []
            : List.unmodifiable(
                (value['missing_fields'] as List).map((v) => v as String),
              ),
        audit: value['audit'] == null
            ? null
            : GuidanceAudit.fromJson(
                Map<String, dynamic>.from(value['audit'] as Map),
              ),
        issues: value['issues'] == null
            ? const []
            : List.unmodifiable(
                (value['issues'] as List).map(
                  (v) => GuidanceAuditIssue.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              ),
        notice: value['notice'] == null ? null : value['notice'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'node_id': nodeId,
    'title': title,
    'state': state,
    'reason': reason,
    'message': message,
    'cards': cards.map((v) => v.toJson()).toList(),
    'warnings': warnings.map((v) => v).toList(),
    'buttons': buttons.map((v) => v.toJson()).toList(),
    'fetched_at': fetchedAt,
    'snapshot_stale': snapshotStale,
    'source': source?.toJson(),
    'scope': scope,
    'campus': campus,
    'coverage': coverage?.toJson(),
    'listing_status': listingStatus,
    'attachment_state': attachmentState,
    'workflow': workflow?.toJson(),
    'integration_state': integrationState,
    'missing_fields': missingFields.map((v) => v).toList(),
    'audit': audit?.toJson(),
    'issues': issues.map((v) => v.toJson()).toList(),
    'notice': notice,
  };
}

class GuidanceCitationApplicability implements AcademicGuidancePayload {
  const GuidanceCitationApplicability({
    required this.institutionId,
    required this.departmentId,
    required this.curriculumId,
    required this.sourceVersion,
    required this.knowledgeDocumentId,
    required this.knowledgeVersion,
    required this.effectiveFrom,
    required this.effectiveTo,
    required this.sourceCheckedOn,
    required this.admissionYears,
    required this.tracks,
  });
  final String institutionId;
  final String? departmentId;
  final String? curriculumId;
  final int sourceVersion;
  final String knowledgeDocumentId;
  final int knowledgeVersion;
  final String? effectiveFrom;
  final String? effectiveTo;
  final String sourceCheckedOn;
  final List<int> admissionYears;
  final List<String> tracks;
  factory GuidanceCitationApplicability.fromJson(Map<String, dynamic> value) =>
      GuidanceCitationApplicability(
        institutionId: value['institution_id'] as String,
        departmentId: value['department_id'] == null
            ? null
            : value['department_id'] as String,
        curriculumId: value['curriculum_id'] == null
            ? null
            : value['curriculum_id'] as String,
        sourceVersion: value['source_version'] as int,
        knowledgeDocumentId: value['knowledge_document_id'] as String,
        knowledgeVersion: value['knowledge_version'] as int,
        effectiveFrom: value['effective_from'] == null
            ? null
            : value['effective_from'] as String,
        effectiveTo: value['effective_to'] == null
            ? null
            : value['effective_to'] as String,
        sourceCheckedOn: value['source_checked_on'] as String,
        admissionYears: List.unmodifiable(
          (value['admission_years'] as List).map((v) => v as int),
        ),
        tracks: List.unmodifiable(
          (value['tracks'] as List).map((v) => v as String),
        ),
      );
  @override
  Map<String, Object?> toJson() => {
    'institution_id': institutionId,
    'department_id': departmentId,
    'curriculum_id': curriculumId,
    'source_version': sourceVersion,
    'knowledge_document_id': knowledgeDocumentId,
    'knowledge_version': knowledgeVersion,
    'effective_from': effectiveFrom,
    'effective_to': effectiveTo,
    'source_checked_on': sourceCheckedOn,
    'admission_years': admissionYears.map((v) => v).toList(),
    'tracks': tracks.map((v) => v).toList(),
  };
}

class GuidanceSchoolCitation implements AcademicGuidancePayload {
  const GuidanceSchoolCitation({
    required this.chunkId,
    required this.documentId,
    required this.title,
    required this.sourceUrl,
    required this.page,
    required this.excerpt,
    this.applicability,
  });
  final String chunkId;
  final String documentId;
  final String title;
  final String sourceUrl;
  final int page;
  final String excerpt;
  final GuidanceCitationApplicability? applicability;
  factory GuidanceSchoolCitation.fromJson(Map<String, dynamic> value) =>
      GuidanceSchoolCitation(
        chunkId: value['chunk_id'] as String,
        documentId: value['document_id'] as String,
        title: value['title'] as String,
        sourceUrl: value['source_url'] as String,
        page: value['page'] as int,
        excerpt: value['excerpt'] as String,
        applicability: value['applicability'] == null
            ? null
            : GuidanceCitationApplicability.fromJson(
                Map<String, dynamic>.from(value['applicability'] as Map),
              ),
      );
  @override
  Map<String, Object?> toJson() => {
    'chunk_id': chunkId,
    'document_id': documentId,
    'title': title,
    'source_url': sourceUrl,
    'page': page,
    'excerpt': excerpt,
    'applicability': applicability?.toJson(),
  };
}

class GuidanceSchoolEvidence implements AcademicGuidancePayload {
  const GuidanceSchoolEvidence({
    required this.queryId,
    required this.status,
    required this.reason,
    this.sources = const [],
    this.missingFields = const [],
  });
  final String queryId;
  final String status;
  final String reason;
  final List<GuidanceSchoolCitation> sources;
  final List<String> missingFields;
  factory GuidanceSchoolEvidence.fromJson(Map<String, dynamic> value) =>
      GuidanceSchoolEvidence(
        queryId: value['query_id'] as String,
        status: _choice(value['status'], [
          "evidence_found",
          "insufficient_evidence",
          "needs_user_input",
          "failed",
        ]),
        reason: _choice(value['reason'], [
          "approved_sources_found",
          "no_approved_matching_evidence",
          "academic_scope_required",
          "conflicting_admission_year",
          "rule_engine_required",
          "document_context_not_approved_or_incomplete",
          "rag_processing_failed",
        ]),
        sources: value['sources'] == null
            ? const []
            : List.unmodifiable(
                (value['sources'] as List).map(
                  (v) => GuidanceSchoolCitation.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              ),
        missingFields: value['missing_fields'] == null
            ? const []
            : List.unmodifiable(
                (value['missing_fields'] as List).map((v) => v as String),
              ),
      );
  @override
  Map<String, Object?> toJson() => {
    'query_id': queryId,
    'status': status,
    'reason': reason,
    'sources': sources.map((v) => v.toJson()).toList(),
    'missing_fields': missingFields.map((v) => v).toList(),
  };
}

class GuidanceRecordSelection implements AcademicGuidancePayload {
  const GuidanceRecordSelection({
    required this.kind,
    required this.recordId,
    required this.expectedVersion,
  });
  final String kind;
  final String recordId;
  final int expectedVersion;
  factory GuidanceRecordSelection.fromJson(Map<String, dynamic> value) =>
      GuidanceRecordSelection(
        kind: _choice(value['kind'], [
          "course",
          "activity",
          "experience",
          "credential",
          "achievement",
        ]),
        recordId: value['record_id'] as String,
        expectedVersion: value['expected_version'] as int,
      );
  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'record_id': recordId,
    'expected_version': expectedVersion,
  };
}

class GuidanceSchoolContext implements AcademicGuidancePayload {
  const GuidanceSchoolContext({
    required this.institutionId,
    required this.departmentId,
    this.curriculumId,
    this.admissionYear,
    this.track,
  });
  final String institutionId;
  final String departmentId;
  final String? curriculumId;
  final int? admissionYear;
  final String? track;
  factory GuidanceSchoolContext.fromJson(Map<String, dynamic> value) =>
      GuidanceSchoolContext(
        institutionId: value['institution_id'] as String,
        departmentId: value['department_id'] as String,
        curriculumId: value['curriculum_id'] == null
            ? null
            : value['curriculum_id'] as String,
        admissionYear: value['admission_year'] == null
            ? null
            : value['admission_year'] as int,
        track: value['track'] == null ? null : value['track'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'institution_id': institutionId,
    'department_id': departmentId,
    'curriculum_id': curriculumId,
    'admission_year': admissionYear,
    'track': track,
  };
}

class PersonalizedGuidanceRequest implements AcademicGuidancePayload {
  const PersonalizedGuidanceRequest({
    this.records = const [],
    required this.question,
    required this.context,
    this.externalProcessingConsent = false,
  });
  final List<GuidanceRecordSelection> records;
  final String question;
  final GuidanceSchoolContext context;
  final bool externalProcessingConsent;
  factory PersonalizedGuidanceRequest.fromJson(Map<String, dynamic> value) =>
      PersonalizedGuidanceRequest(
        records: value['records'] == null
            ? const []
            : List.unmodifiable(
                (value['records'] as List).map(
                  (v) => GuidanceRecordSelection.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              ),
        question: value['question'] as String,
        context: GuidanceSchoolContext.fromJson(
          Map<String, dynamic>.from(value['context'] as Map),
        ),
        externalProcessingConsent: value['external_processing_consent'] == null
            ? false
            : value['external_processing_consent'] as bool,
      );
  @override
  Map<String, Object?> toJson() => {
    'records': records.map((v) => v.toJson()).toList(),
    'question': question,
    'context': context.toJson(),
    'external_processing_consent': externalProcessingConsent,
  };
}

class GuidancePersonalEvidence implements AcademicGuidancePayload {
  const GuidancePersonalEvidence({
    required this.kind,
    required this.recordId,
    required this.version,
    this.origin = "personal",
    this.official = false,
    required this.title,
    required this.text,
    required this.truncated,
  });
  final String kind;
  final String recordId;
  final int version;
  final String origin;
  final bool official;
  final String title;
  final String text;
  final bool truncated;
  factory GuidancePersonalEvidence.fromJson(Map<String, dynamic> value) =>
      GuidancePersonalEvidence(
        kind: _choice(value['kind'], [
          "course",
          "activity",
          "experience",
          "credential",
          "achievement",
        ]),
        recordId: value['record_id'] as String,
        version: value['version'] as int,
        origin: value['origin'] == null
            ? "personal"
            : _constant(value['origin'], "personal") as String,
        official: value['official'] == null
            ? false
            : _constant(value['official'], false) as bool,
        title: value['title'] as String,
        text: value['text'] as String,
        truncated: value['truncated'] as bool,
      );
  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'record_id': recordId,
    'version': version,
    'origin': origin,
    'official': official,
    'title': title,
    'text': text,
    'truncated': truncated,
  };
}

class GuidancePersonalContext implements AcademicGuidancePayload {
  const GuidancePersonalContext({required this.records, this.official = false});
  final List<GuidancePersonalEvidence> records;
  final bool official;
  factory GuidancePersonalContext.fromJson(Map<String, dynamic> value) =>
      GuidancePersonalContext(
        records: List.unmodifiable(
          (value['records'] as List).map(
            (v) => GuidancePersonalEvidence.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          ),
        ),
        official: value['official'] == null
            ? false
            : _constant(value['official'], false) as bool,
      );
  @override
  Map<String, Object?> toJson() => {
    'records': records.map((v) => v.toJson()).toList(),
    'official': official,
  };
}

class GuidancePersonalCitation implements AcademicGuidancePayload {
  const GuidancePersonalCitation({
    required this.kind,
    required this.recordId,
    required this.version,
    required this.excerpt,
  });
  final String kind;
  final String recordId;
  final int version;
  final String excerpt;
  factory GuidancePersonalCitation.fromJson(Map<String, dynamic> value) =>
      GuidancePersonalCitation(
        kind: _choice(value['kind'], [
          "course",
          "activity",
          "experience",
          "credential",
          "achievement",
        ]),
        recordId: value['record_id'] as String,
        version: value['version'] as int,
        excerpt: value['excerpt'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'record_id': recordId,
    'version': version,
    'excerpt': excerpt,
  };
}

class PersonalizedGuidanceResponse implements AcademicGuidancePayload {
  const PersonalizedGuidanceResponse({
    required this.queryId,
    required this.status,
    required this.reason,
    this.official = false,
    this.answer,
    required this.school,
    required this.personal,
    this.schoolChunkIds = const [],
    this.personalCitations = const [],
    this.missingFields = const [],
  });
  final String queryId;
  final String status;
  final String reason;
  final bool official;
  final String? answer;
  final GuidanceSchoolEvidence school;
  final GuidancePersonalContext personal;
  final List<String> schoolChunkIds;
  final List<GuidancePersonalCitation> personalCitations;
  final List<String> missingFields;
  factory PersonalizedGuidanceResponse.fromJson(Map<String, dynamic> value) =>
      PersonalizedGuidanceResponse(
        queryId: value['query_id'] as String,
        status: _choice(value['status'], [
          "grounded",
          "evidence_only",
          "needs_user_input",
          "insufficient_evidence",
          "failed",
        ]),
        reason: _choice(value['reason'], [
          "generated_from_separated_evidence",
          "generator_not_configured",
          "school_evidence_unavailable",
          "personal_records_required",
          "external_processing_consent_required",
          "generator_reported_insufficient_evidence",
          "generation_failed",
        ]),
        official: value['official'] == null
            ? false
            : _constant(value['official'], false) as bool,
        answer: value['answer'] == null ? null : value['answer'] as String,
        school: GuidanceSchoolEvidence.fromJson(
          Map<String, dynamic>.from(value['school'] as Map),
        ),
        personal: GuidancePersonalContext.fromJson(
          Map<String, dynamic>.from(value['personal'] as Map),
        ),
        schoolChunkIds: value['school_chunk_ids'] == null
            ? const []
            : List.unmodifiable(
                (value['school_chunk_ids'] as List).map((v) => v as String),
              ),
        personalCitations: value['personal_citations'] == null
            ? const []
            : List.unmodifiable(
                (value['personal_citations'] as List).map(
                  (v) => GuidancePersonalCitation.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              ),
        missingFields: value['missing_fields'] == null
            ? const []
            : List.unmodifiable(
                (value['missing_fields'] as List).map(
                  (v) => _choice(v, ["records", "external_processing_consent"]),
                ),
              ),
      );
  @override
  Map<String, Object?> toJson() => {
    'query_id': queryId,
    'status': status,
    'reason': reason,
    'official': official,
    'answer': answer,
    'school': school.toJson(),
    'personal': personal.toJson(),
    'school_chunk_ids': schoolChunkIds.map((v) => v).toList(),
    'personal_citations': personalCitations.map((v) => v.toJson()).toList(),
    'missing_fields': missingFields.map((v) => v).toList(),
  };
}

class GuidanceBundle implements AcademicGuidancePayload {
  const GuidanceBundle({
    required this.bundleId,
    required this.name,
    required this.sourceSchool,
    required this.officialUrl,
    required this.schemaVersion,
    required this.edition,
    required this.fetchedAt,
    required this.availability,
  });
  final String bundleId;
  final String name;
  final String sourceSchool;
  final String officialUrl;
  final String schemaVersion;
  final String edition;
  final DateTime fetchedAt;
  final String availability;
  factory GuidanceBundle.fromJson(Map<String, dynamic> value) => GuidanceBundle(
    bundleId: value['bundle_id'] as String,
    name: value['name'] as String,
    sourceSchool: value['source_school'] as String,
    officialUrl: value['official_url'] as String,
    schemaVersion: value['schema_version'] as String,
    edition: value['edition'] as String,
    fetchedAt: DateTime.parse(value['fetched_at'] as String),
    availability: _choice(value['availability'], ["available", "unavailable"]),
  );
  @override
  Map<String, Object?> toJson() => {
    'bundle_id': bundleId,
    'name': name,
    'source_school': sourceSchool,
    'official_url': officialUrl,
    'schema_version': schemaVersion,
    'edition': edition,
    'fetched_at': fetchedAt.toUtc().toIso8601String(),
    'availability': availability,
  };
}

class GuidanceBundleList implements AcademicGuidancePayload {
  const GuidanceBundleList({required this.items, this.nextCursor});
  final List<GuidanceBundle> items;
  final String? nextCursor;
  factory GuidanceBundleList.fromJson(Map<String, dynamic> value) =>
      GuidanceBundleList(
        items: List.unmodifiable(
          (value['items'] as List).map(
            (v) => GuidanceBundle.fromJson(Map<String, dynamic>.from(v as Map)),
          ),
        ),
        nextCursor: value['next_cursor'] == null
            ? null
            : value['next_cursor'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'items': items.map((v) => v.toJson()).toList(),
    'next_cursor': nextCursor,
  };
}

class GuidanceBindingView implements AcademicGuidancePayload {
  const GuidanceBindingView({
    required this.institutionId,
    required this.state,
    required this.version,
    this.bundleId,
    this.boundEdition,
    this.bundle,
    this.editionChanged = false,
    this.updatedBy,
    this.updatedAt,
  });
  final String institutionId;
  final String state;
  final int version;
  final String? bundleId;
  final String? boundEdition;
  final GuidanceBundle? bundle;
  final bool editionChanged;
  final String? updatedBy;
  final DateTime? updatedAt;
  factory GuidanceBindingView.fromJson(Map<String, dynamic> value) =>
      GuidanceBindingView(
        institutionId: value['institution_id'] as String,
        state: _choice(value['state'], ["unbound", "bound", "unavailable"]),
        version: value['version'] as int,
        bundleId: value['bundle_id'] == null
            ? null
            : value['bundle_id'] as String,
        boundEdition: value['bound_edition'] == null
            ? null
            : value['bound_edition'] as String,
        bundle: value['bundle'] == null
            ? null
            : GuidanceBundle.fromJson(
                Map<String, dynamic>.from(value['bundle'] as Map),
              ),
        editionChanged: value['edition_changed'] == null
            ? false
            : value['edition_changed'] as bool,
        updatedBy: value['updated_by'] == null
            ? null
            : value['updated_by'] as String,
        updatedAt: value['updated_at'] == null
            ? null
            : DateTime.parse(value['updated_at'] as String),
      );
  @override
  Map<String, Object?> toJson() => {
    'institution_id': institutionId,
    'state': state,
    'version': version,
    'bundle_id': bundleId,
    'bound_edition': boundEdition,
    'bundle': bundle?.toJson(),
    'edition_changed': editionChanged,
    'updated_by': updatedBy,
    'updated_at': updatedAt?.toUtc().toIso8601String(),
  };
}

class GuidanceBindingSave implements AcademicGuidancePayload {
  const GuidanceBindingSave({
    required this.bundleId,
    required this.edition,
    required this.expectedVersion,
  });
  final String bundleId;
  final String edition;
  final int expectedVersion;
  factory GuidanceBindingSave.fromJson(Map<String, dynamic> value) =>
      GuidanceBindingSave(
        bundleId: value['bundle_id'] as String,
        edition: value['edition'] as String,
        expectedVersion: value['expected_version'] as int,
      );
  @override
  Map<String, Object?> toJson() => {
    'bundle_id': bundleId,
    'edition': edition,
    'expected_version': expectedVersion,
  };
}

class StudentGuidanceBinding implements AcademicGuidancePayload {
  const StudentGuidanceBinding({
    required this.state,
    this.institutionId,
    this.bundle,
  });
  final String state;
  final String? institutionId;
  final GuidanceBundle? bundle;
  factory StudentGuidanceBinding.fromJson(Map<String, dynamic> value) =>
      StudentGuidanceBinding(
        state: _choice(value['state'], [
          "school_required",
          "unbound",
          "bound",
          "unavailable",
        ]),
        institutionId: value['institution_id'] == null
            ? null
            : value['institution_id'] as String,
        bundle: value['bundle'] == null
            ? null
            : GuidanceBundle.fromJson(
                Map<String, dynamic>.from(value['bundle'] as Map),
              ),
      );
  @override
  Map<String, Object?> toJson() => {
    'state': state,
    'institution_id': institutionId,
    'bundle': bundle?.toJson(),
  };
}
