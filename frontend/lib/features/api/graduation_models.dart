// GENERATED: scripts/export_graduation_contracts.py.
// eligible_as_of is historical; always check evaluated_on and current_usable.
import 'rule_program_models.dart';

abstract interface class GraduationPayload {
  Map<String, Object?> toJson();
}

String _decimal(Object? value) {
  if (value is String || (value is num && value.isFinite)) {
    return value.toString();
  }
  throw const FormatException('Expected decimal wire value');
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

class GraduationContext implements GraduationPayload {
  const GraduationContext({
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
  factory GraduationContext.fromJson(Map<String, dynamic> value) =>
      GraduationContext(
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

class CatalogPreview implements GraduationPayload {
  const CatalogPreview({
    required this.context,
    required this.asOf,
    required this.status,
    required this.reason,
    required this.programs,
    required this.issues,
    required this.snapshotDigest,
    required this.reviewable,
  });
  final GraduationContext context;
  final String asOf;
  final String status;
  final String reason;
  final List<OfficialPublicProgram> programs;
  final List<OfficialSelectionIssue> issues;
  final String snapshotDigest;
  final bool reviewable;
  factory CatalogPreview.fromJson(Map<String, dynamic> value) => CatalogPreview(
    context: GraduationContext.fromJson(
      Map<String, dynamic>.from(value['context'] as Map),
    ),
    asOf: value['as_of'] as String,
    status: _choice(value['status'], [
      "available",
      "needs_review",
      "not_applicable",
    ]),
    reason: value['reason'] as String,
    programs: List.unmodifiable(
      (value['programs'] as List).map(
        (v) =>
            OfficialPublicProgram.fromJson(Map<String, dynamic>.from(v as Map)),
      ),
    ),
    issues: List.unmodifiable(
      (value['issues'] as List).map(
        (v) => OfficialSelectionIssue.fromJson(
          Map<String, dynamic>.from(v as Map),
        ),
      ),
    ),
    snapshotDigest: value['snapshot_digest'] as String,
    reviewable: value['reviewable'] as bool,
  );
  @override
  Map<String, Object?> toJson() => {
    'context': context.toJson(),
    'as_of': asOf,
    'status': status,
    'reason': reason,
    'programs': programs.map((v) => v.toJson()).toList(),
    'issues': issues.map((v) => v.toJson()).toList(),
    'snapshot_digest': snapshotDigest,
    'reviewable': reviewable,
  };
}

class CatalogReviewCreate implements GraduationPayload {
  const CatalogReviewCreate({
    required this.context,
    required this.asOf,
    required this.clientId,
    required this.expectedCatalogDigest,
    required this.allRequirementsReviewed,
    required this.allLevelsReviewed,
    required this.sourcesReviewed,
    required this.reviewNote,
    this.replacesReviewId,
    this.expectedReplacedVersion,
  });
  final GraduationContext context;
  final String asOf;
  final String clientId;
  final String expectedCatalogDigest;
  final bool allRequirementsReviewed;
  final bool allLevelsReviewed;
  final bool sourcesReviewed;
  final String reviewNote;
  final String? replacesReviewId;
  final int? expectedReplacedVersion;
  factory CatalogReviewCreate.fromJson(Map<String, dynamic> value) =>
      CatalogReviewCreate(
        context: GraduationContext.fromJson(
          Map<String, dynamic>.from(value['context'] as Map),
        ),
        asOf: value['as_of'] as String,
        clientId: value['client_id'] as String,
        expectedCatalogDigest: value['expected_catalog_digest'] as String,
        allRequirementsReviewed: value['all_requirements_reviewed'] as bool,
        allLevelsReviewed: value['all_levels_reviewed'] as bool,
        sourcesReviewed: value['sources_reviewed'] as bool,
        reviewNote: value['review_note'] as String,
        replacesReviewId: value['replaces_review_id'] == null
            ? null
            : value['replaces_review_id'] as String,
        expectedReplacedVersion: value['expected_replaced_version'] == null
            ? null
            : value['expected_replaced_version'] as int,
      );
  @override
  Map<String, Object?> toJson() => {
    'context': context.toJson(),
    'as_of': asOf,
    'client_id': clientId,
    'expected_catalog_digest': expectedCatalogDigest,
    'all_requirements_reviewed': allRequirementsReviewed,
    'all_levels_reviewed': allLevelsReviewed,
    'sources_reviewed': sourcesReviewed,
    'review_note': reviewNote,
    'replaces_review_id': replacesReviewId,
    'expected_replaced_version': expectedReplacedVersion,
  };
}

class CatalogReviewRevoke implements GraduationPayload {
  const CatalogReviewRevoke({
    required this.expectedVersion,
    required this.reason,
  });
  final int expectedVersion;
  final String reason;
  factory CatalogReviewRevoke.fromJson(Map<String, dynamic> value) =>
      CatalogReviewRevoke(
        expectedVersion: value['expected_version'] as int,
        reason: value['reason'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'expected_version': expectedVersion,
    'reason': reason,
  };
}

class CatalogReviewHeader implements GraduationPayload {
  const CatalogReviewHeader({
    required this.id,
    required this.clientId,
    required this.context,
    required this.asOf,
    required this.status,
    required this.version,
    required this.snapshotDigest,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String clientId;
  final GraduationContext context;
  final String asOf;
  final String status;
  final int version;
  final String snapshotDigest;
  final DateTime createdAt;
  final DateTime updatedAt;
  factory CatalogReviewHeader.fromJson(Map<String, dynamic> value) =>
      CatalogReviewHeader(
        id: value['id'] as String,
        clientId: value['client_id'] as String,
        context: GraduationContext.fromJson(
          Map<String, dynamic>.from(value['context'] as Map),
        ),
        asOf: value['as_of'] as String,
        status: _choice(value['status'], ["approved", "revoked", "superseded"]),
        version: value['version'] as int,
        snapshotDigest: value['snapshot_digest'] as String,
        createdAt: DateTime.parse(value['created_at'] as String),
        updatedAt: DateTime.parse(value['updated_at'] as String),
      );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'client_id': clientId,
    'context': context.toJson(),
    'as_of': asOf,
    'status': status,
    'version': version,
    'snapshot_digest': snapshotDigest,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}

class CatalogReviewView implements GraduationPayload {
  const CatalogReviewView({
    required this.id,
    required this.clientId,
    required this.context,
    required this.asOf,
    required this.status,
    required this.version,
    required this.snapshotDigest,
    required this.createdAt,
    required this.updatedAt,
    required this.reviewedBy,
    required this.reviewNote,
    required this.snapshot,
    required this.usable,
    required this.issues,
  });
  final String id;
  final String clientId;
  final GraduationContext context;
  final String asOf;
  final String status;
  final int version;
  final String snapshotDigest;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? reviewedBy;
  final String reviewNote;
  final CatalogPreview snapshot;
  final bool usable;
  final List<String> issues;
  factory CatalogReviewView.fromJson(Map<String, dynamic> value) =>
      CatalogReviewView(
        id: value['id'] as String,
        clientId: value['client_id'] as String,
        context: GraduationContext.fromJson(
          Map<String, dynamic>.from(value['context'] as Map),
        ),
        asOf: value['as_of'] as String,
        status: _choice(value['status'], ["approved", "revoked", "superseded"]),
        version: value['version'] as int,
        snapshotDigest: value['snapshot_digest'] as String,
        createdAt: DateTime.parse(value['created_at'] as String),
        updatedAt: DateTime.parse(value['updated_at'] as String),
        reviewedBy: value['reviewed_by'] == null
            ? null
            : value['reviewed_by'] as String,
        reviewNote: value['review_note'] as String,
        snapshot: CatalogPreview.fromJson(
          Map<String, dynamic>.from(value['snapshot'] as Map),
        ),
        usable: value['usable'] as bool,
        issues: List.unmodifiable(
          (value['issues'] as List).map((v) => v as String),
        ),
      );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'client_id': clientId,
    'context': context.toJson(),
    'as_of': asOf,
    'status': status,
    'version': version,
    'snapshot_digest': snapshotDigest,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'reviewed_by': reviewedBy,
    'review_note': reviewNote,
    'snapshot': snapshot.toJson(),
    'usable': usable,
    'issues': issues.map((v) => v).toList(),
  };
}

class CatalogReviewList implements GraduationPayload {
  const CatalogReviewList({required this.items, this.nextCursor});
  final List<CatalogReviewHeader> items;
  final String? nextCursor;
  factory CatalogReviewList.fromJson(Map<String, dynamic> value) =>
      CatalogReviewList(
        items: List.unmodifiable(
          (value['items'] as List).map(
            (v) => CatalogReviewHeader.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
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

class CatalogReviewEvent implements GraduationPayload {
  const CatalogReviewEvent({
    required this.id,
    required this.reviewId,
    required this.actorId,
    required this.version,
    required this.action,
    required this.reason,
    required this.occurredAt,
  });
  final String id;
  final String reviewId;
  final String? actorId;
  final int version;
  final String action;
  final String reason;
  final DateTime occurredAt;
  factory CatalogReviewEvent.fromJson(Map<String, dynamic> value) =>
      CatalogReviewEvent(
        id: value['id'] as String,
        reviewId: value['review_id'] as String,
        actorId: value['actor_id'] == null ? null : value['actor_id'] as String,
        version: value['version'] as int,
        action: _choice(value['action'], ["approved", "revoked", "superseded"]),
        reason: value['reason'] as String,
        occurredAt: DateTime.parse(value['occurred_at'] as String),
      );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'review_id': reviewId,
    'actor_id': actorId,
    'version': version,
    'action': action,
    'reason': reason,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
  };
}

class CatalogReviewEvents implements GraduationPayload {
  const CatalogReviewEvents({required this.items});
  final List<CatalogReviewEvent> items;
  factory CatalogReviewEvents.fromJson(Map<String, dynamic> value) =>
      CatalogReviewEvents(
        items: List.unmodifiable(
          (value['items'] as List).map(
            (v) => CatalogReviewEvent.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          ),
        ),
      );
  @override
  Map<String, Object?> toJson() => {
    'items': items.map((v) => v.toJson()).toList(),
  };
}

class GraduationAuditCreate implements GraduationPayload {
  const GraduationAuditCreate({
    required this.context,
    required this.asOf,
    required this.clientId,
  });
  final GraduationContext context;
  final String asOf;
  final String clientId;
  factory GraduationAuditCreate.fromJson(Map<String, dynamic> value) =>
      GraduationAuditCreate(
        context: GraduationContext.fromJson(
          Map<String, dynamic>.from(value['context'] as Map),
        ),
        asOf: value['as_of'] as String,
        clientId: value['client_id'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'context': context.toJson(),
    'as_of': asOf,
    'client_id': clientId,
  };
}

class AuditEvidence implements GraduationPayload {
  const AuditEvidence({
    required this.chunkId,
    required this.knowledgeDocumentId,
    required this.knowledgeVersion,
    required this.documentId,
    required this.documentVersion,
    required this.title,
    required this.sourceUrl,
    required this.page,
    required this.contentHash,
    required this.documentHash,
  });
  final String chunkId;
  final String knowledgeDocumentId;
  final int knowledgeVersion;
  final String documentId;
  final int documentVersion;
  final String title;
  final String sourceUrl;
  final int page;
  final String contentHash;
  final String documentHash;
  factory AuditEvidence.fromJson(Map<String, dynamic> value) => AuditEvidence(
    chunkId: value['chunk_id'] as String,
    knowledgeDocumentId: value['knowledge_document_id'] as String,
    knowledgeVersion: value['knowledge_version'] as int,
    documentId: value['document_id'] as String,
    documentVersion: value['document_version'] as int,
    title: value['title'] as String,
    sourceUrl: value['source_url'] as String,
    page: value['page'] as int,
    contentHash: value['content_hash'] as String,
    documentHash: value['document_hash'] as String,
  );
  @override
  Map<String, Object?> toJson() => {
    'chunk_id': chunkId,
    'knowledge_document_id': knowledgeDocumentId,
    'knowledge_version': knowledgeVersion,
    'document_id': documentId,
    'document_version': documentVersion,
    'title': title,
    'source_url': sourceUrl,
    'page': page,
    'content_hash': contentHash,
    'document_hash': documentHash,
  };
}

class AuditedRule implements GraduationPayload {
  const AuditedRule({
    required this.ruleId,
    required this.sourceVersion,
    required this.title,
    required this.condition,
    required this.evidence,
    required this.references,
  });
  final String ruleId;
  final int sourceVersion;
  final String title;
  final OfficialCondition condition;
  final List<AuditEvidence> evidence;
  final List<OfficialReferenceSnapshot> references;
  factory AuditedRule.fromJson(Map<String, dynamic> value) => AuditedRule(
    ruleId: value['rule_id'] as String,
    sourceVersion: value['source_version'] as int,
    title: value['title'] as String,
    condition: OfficialCondition.fromJson(
      Map<String, dynamic>.from(value['condition'] as Map),
    ),
    evidence: List.unmodifiable(
      (value['evidence'] as List).map(
        (v) => AuditEvidence.fromJson(Map<String, dynamic>.from(v as Map)),
      ),
    ),
    references: List.unmodifiable(
      (value['references'] as List).map(
        (v) => OfficialReferenceSnapshot.fromJson(
          Map<String, dynamic>.from(v as Map),
        ),
      ),
    ),
  );
  @override
  Map<String, Object?> toJson() => {
    'rule_id': ruleId,
    'source_version': sourceVersion,
    'title': title,
    'condition': condition.toJson(),
    'evidence': evidence.map((v) => v.toJson()).toList(),
    'references': references.map((v) => v.toJson()).toList(),
  };
}

class AuditedProgram implements GraduationPayload {
  const AuditedProgram({
    required this.id,
    required this.version,
    required this.ruleSetId,
    required this.ruleId,
    required this.sourceVersion,
    required this.name,
    required this.rules,
  });
  final String id;
  final int version;
  final String? ruleSetId;
  final String? ruleId;
  final int sourceVersion;
  final String name;
  final List<AuditedRule> rules;
  factory AuditedProgram.fromJson(Map<String, dynamic> value) => AuditedProgram(
    id: value['id'] as String,
    version: value['version'] as int,
    ruleSetId: value['rule_set_id'] == null
        ? null
        : value['rule_set_id'] as String,
    ruleId: value['rule_id'] == null ? null : value['rule_id'] as String,
    sourceVersion: value['source_version'] as int,
    name: value['name'] as String,
    rules: List.unmodifiable(
      (value['rules'] as List).map(
        (v) => AuditedRule.fromJson(Map<String, dynamic>.from(v as Map)),
      ),
    ),
  );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'rule_set_id': ruleSetId,
    'rule_id': ruleId,
    'source_version': sourceVersion,
    'name': name,
    'rules': rules.map((v) => v.toJson()).toList(),
  };
}

class AuditedBatch implements GraduationPayload {
  const AuditedBatch({
    required this.id,
    required this.version,
    required this.kind,
    required this.dataDigest,
    required this.sourceId,
    required this.sourceVersion,
    required this.sourceSha256,
  });
  final String id;
  final int version;
  final String kind;
  final String dataDigest;
  final String sourceId;
  final int sourceVersion;
  final String sourceSha256;
  factory AuditedBatch.fromJson(Map<String, dynamic> value) => AuditedBatch(
    id: value['id'] as String,
    version: value['version'] as int,
    kind: _choice(value['kind'], [
      "academics",
      "volunteers",
      "certificates",
      "theses",
    ]),
    dataDigest: value['data_digest'] as String,
    sourceId: value['source_id'] as String,
    sourceVersion: value['source_version'] as int,
    sourceSha256: value['source_sha256'] as String,
  );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'kind': kind,
    'data_digest': dataDigest,
    'source_id': sourceId,
    'source_version': sourceVersion,
    'source_sha256': sourceSha256,
  };
}

class AuditRecordEvidence implements GraduationPayload {
  const AuditRecordEvidence({
    required this.recordId,
    required this.batchId,
    required this.clientId,
    required this.kind,
    required this.sourcePage,
  });
  final String recordId;
  final String batchId;
  final String clientId;
  final String kind;
  final int sourcePage;
  factory AuditRecordEvidence.fromJson(Map<String, dynamic> value) =>
      AuditRecordEvidence(
        recordId: value['record_id'] as String,
        batchId: value['batch_id'] as String,
        clientId: value['client_id'] as String,
        kind: _choice(value['kind'], [
          "academics",
          "volunteers",
          "certificates",
          "theses",
        ]),
        sourcePage: value['source_page'] as int,
      );
  @override
  Map<String, Object?> toJson() => {
    'record_id': recordId,
    'batch_id': batchId,
    'client_id': clientId,
    'kind': kind,
    'source_page': sourcePage,
  };
}

class AuditIssue implements GraduationPayload {
  const AuditIssue({required this.kind, required this.reason});
  final String kind;
  final String reason;
  factory AuditIssue.fromJson(Map<String, dynamic> value) => AuditIssue(
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

class AuditResultItem implements GraduationPayload {
  const AuditResultItem({
    required this.ruleSetId,
    required this.ruleSetVersion,
    required this.ruleId,
    required this.title,
    required this.status,
    required this.reason,
    this.current,
    this.required,
    this.deficit,
    this.missingCourseIds = const [],
    this.uncertainCourseIds = const [],
    this.evidenceRecordIds = const [],
  });
  final String ruleSetId;
  final int ruleSetVersion;
  final String ruleId;
  final String title;
  final String status;
  final String reason;
  final String? current;
  final String? required;
  final String? deficit;
  final List<String> missingCourseIds;
  final List<String> uncertainCourseIds;
  final List<String> evidenceRecordIds;
  factory AuditResultItem.fromJson(Map<String, dynamic> value) =>
      AuditResultItem(
        ruleSetId: value['rule_set_id'] as String,
        ruleSetVersion: value['rule_set_version'] as int,
        ruleId: value['rule_id'] as String,
        title: value['title'] as String,
        status: _choice(value['status'], [
          "satisfied",
          "not_satisfied",
          "needs_review",
          "not_applicable",
        ]),
        reason: value['reason'] as String,
        current: value['current'] == null ? null : _decimal(value['current']),
        required: value['required'] == null
            ? null
            : _decimal(value['required']),
        deficit: value['deficit'] == null ? null : _decimal(value['deficit']),
        missingCourseIds: value['missing_course_ids'] == null
            ? const []
            : List.unmodifiable(
                (value['missing_course_ids'] as List).map((v) => v as String),
              ),
        uncertainCourseIds: value['uncertain_course_ids'] == null
            ? const []
            : List.unmodifiable(
                (value['uncertain_course_ids'] as List).map((v) => v as String),
              ),
        evidenceRecordIds: value['evidence_record_ids'] == null
            ? const []
            : List.unmodifiable(
                (value['evidence_record_ids'] as List).map((v) => v as String),
              ),
      );
  @override
  Map<String, Object?> toJson() => {
    'rule_set_id': ruleSetId,
    'rule_set_version': ruleSetVersion,
    'rule_id': ruleId,
    'title': title,
    'status': status,
    'reason': reason,
    'current': current,
    'required': required,
    'deficit': deficit,
    'missing_course_ids': missingCourseIds.map((v) => v).toList(),
    'uncertain_course_ids': uncertainCourseIds.map((v) => v).toList(),
    'evidence_record_ids': evidenceRecordIds.map((v) => v).toList(),
  };
}

class GraduationAuditHeader implements GraduationPayload {
  const GraduationAuditHeader({
    required this.id,
    required this.ownerId,
    required this.clientId,
    this.version = 1,
    required this.context,
    required this.evaluatedOn,
    required this.createdAt,
    this.official = true,
    this.label = "학교 검토 자료 기준 졸업요건 감사",
    required this.status,
    required this.reason,
    required this.catalogComplete,
    required this.eligibleAsOf,
  });
  final String id;
  final String ownerId;
  final String clientId;
  final int version;
  final GraduationContext context;
  final String evaluatedOn;
  final DateTime createdAt;
  final bool official;
  final String label;
  final String status;
  final String reason;
  final bool catalogComplete;
  final bool eligibleAsOf;
  factory GraduationAuditHeader.fromJson(Map<String, dynamic> value) =>
      GraduationAuditHeader(
        id: value['id'] as String,
        ownerId: value['owner_id'] as String,
        clientId: value['client_id'] as String,
        version: value['version'] == null
            ? 1
            : _constant(value['version'], 1) as int,
        context: GraduationContext.fromJson(
          Map<String, dynamic>.from(value['context'] as Map),
        ),
        evaluatedOn: value['evaluated_on'] as String,
        createdAt: DateTime.parse(value['created_at'] as String),
        official: value['official'] == null
            ? true
            : _constant(value['official'], true) as bool,
        label: value['label'] == null
            ? "학교 검토 자료 기준 졸업요건 감사"
            : _constant(
                value['label'],
                "\ud559\uad50 \uac80\ud1a0 \uc790\ub8cc \uae30\uc900 \uc878\uc5c5\uc694\uac74 \uac10\uc0ac",
              ) as String,
        status: _choice(value['status'], [
          "satisfied",
          "not_satisfied",
          "needs_review",
          "not_applicable",
        ]),
        reason: value['reason'] as String,
        catalogComplete: value['catalog_complete'] as bool,
        eligibleAsOf: value['eligible_as_of'] as bool,
      );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'owner_id': ownerId,
    'client_id': clientId,
    'version': version,
    'context': context.toJson(),
    'evaluated_on': evaluatedOn,
    'created_at': createdAt.toUtc().toIso8601String(),
    'official': official,
    'label': label,
    'status': status,
    'reason': reason,
    'catalog_complete': catalogComplete,
    'eligible_as_of': eligibleAsOf,
  };
}

class GraduationAuditView implements GraduationPayload {
  const GraduationAuditView({
    required this.id,
    required this.ownerId,
    required this.clientId,
    this.version = 1,
    required this.context,
    required this.evaluatedOn,
    required this.createdAt,
    this.official = true,
    this.label = "학교 검토 자료 기준 졸업요건 감사",
    required this.status,
    required this.reason,
    required this.catalogComplete,
    required this.eligibleAsOf,
    required this.catalogReviewId,
    required this.catalogReviewVersion,
    required this.catalogDigest,
    required this.criteria,
    required this.records,
    required this.recordEvidence,
    required this.results,
    required this.issues,
    required this.currentUsable,
    required this.currentIssues,
  });
  final String id;
  final String ownerId;
  final String clientId;
  final int version;
  final GraduationContext context;
  final String evaluatedOn;
  final DateTime createdAt;
  final bool official;
  final String label;
  final String status;
  final String reason;
  final bool catalogComplete;
  final bool eligibleAsOf;
  final String? catalogReviewId;
  final int? catalogReviewVersion;
  final String catalogDigest;
  final List<AuditedProgram> criteria;
  final List<AuditedBatch> records;
  final List<AuditRecordEvidence> recordEvidence;
  final List<AuditResultItem> results;
  final List<AuditIssue> issues;
  final bool currentUsable;
  final List<AuditIssue> currentIssues;
  factory GraduationAuditView.fromJson(Map<String, dynamic> value) =>
      GraduationAuditView(
        id: value['id'] as String,
        ownerId: value['owner_id'] as String,
        clientId: value['client_id'] as String,
        version: value['version'] == null
            ? 1
            : _constant(value['version'], 1) as int,
        context: GraduationContext.fromJson(
          Map<String, dynamic>.from(value['context'] as Map),
        ),
        evaluatedOn: value['evaluated_on'] as String,
        createdAt: DateTime.parse(value['created_at'] as String),
        official: value['official'] == null
            ? true
            : _constant(value['official'], true) as bool,
        label: value['label'] == null
            ? "학교 검토 자료 기준 졸업요건 감사"
            : _constant(
                value['label'],
                "\ud559\uad50 \uac80\ud1a0 \uc790\ub8cc \uae30\uc900 \uc878\uc5c5\uc694\uac74 \uac10\uc0ac",
              ) as String,
        status: _choice(value['status'], [
          "satisfied",
          "not_satisfied",
          "needs_review",
          "not_applicable",
        ]),
        reason: value['reason'] as String,
        catalogComplete: value['catalog_complete'] as bool,
        eligibleAsOf: value['eligible_as_of'] as bool,
        catalogReviewId: value['catalog_review_id'] == null
            ? null
            : value['catalog_review_id'] as String,
        catalogReviewVersion: value['catalog_review_version'] == null
            ? null
            : value['catalog_review_version'] as int,
        catalogDigest: value['catalog_digest'] as String,
        criteria: List.unmodifiable(
          (value['criteria'] as List).map(
            (v) => AuditedProgram.fromJson(Map<String, dynamic>.from(v as Map)),
          ),
        ),
        records: List.unmodifiable(
          (value['records'] as List).map(
            (v) => AuditedBatch.fromJson(Map<String, dynamic>.from(v as Map)),
          ),
        ),
        recordEvidence: List.unmodifiable(
          (value['record_evidence'] as List).map(
            (v) => AuditRecordEvidence.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          ),
        ),
        results: List.unmodifiable(
          (value['results'] as List).map(
            (v) =>
                AuditResultItem.fromJson(Map<String, dynamic>.from(v as Map)),
          ),
        ),
        issues: List.unmodifiable(
          (value['issues'] as List).map(
            (v) => AuditIssue.fromJson(Map<String, dynamic>.from(v as Map)),
          ),
        ),
        currentUsable: value['current_usable'] as bool,
        currentIssues: List.unmodifiable(
          (value['current_issues'] as List).map(
            (v) => AuditIssue.fromJson(Map<String, dynamic>.from(v as Map)),
          ),
        ),
      );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'owner_id': ownerId,
    'client_id': clientId,
    'version': version,
    'context': context.toJson(),
    'evaluated_on': evaluatedOn,
    'created_at': createdAt.toUtc().toIso8601String(),
    'official': official,
    'label': label,
    'status': status,
    'reason': reason,
    'catalog_complete': catalogComplete,
    'eligible_as_of': eligibleAsOf,
    'catalog_review_id': catalogReviewId,
    'catalog_review_version': catalogReviewVersion,
    'catalog_digest': catalogDigest,
    'criteria': criteria.map((v) => v.toJson()).toList(),
    'records': records.map((v) => v.toJson()).toList(),
    'record_evidence': recordEvidence.map((v) => v.toJson()).toList(),
    'results': results.map((v) => v.toJson()).toList(),
    'issues': issues.map((v) => v.toJson()).toList(),
    'current_usable': currentUsable,
    'current_issues': currentIssues.map((v) => v.toJson()).toList(),
  };
}

class GraduationAuditList implements GraduationPayload {
  const GraduationAuditList({required this.items, this.nextCursor});
  final List<GraduationAuditHeader> items;
  final String? nextCursor;
  factory GraduationAuditList.fromJson(Map<String, dynamic> value) =>
      GraduationAuditList(
        items: List.unmodifiable(
          (value['items'] as List).map(
            (v) => GraduationAuditHeader.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
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
