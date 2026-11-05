// GENERATED: scripts/export_official_record_contracts.py.
// Reviewed records remain separate from personal inputs and graduation decisions.
abstract interface class SchoolRecordPayload {
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

sealed class SchoolRecordData implements SchoolRecordPayload {
  const SchoolRecordData();
  String get kind;
  factory SchoolRecordData.fromJson(Map<String, dynamic> value) =>
      switch (value['kind']) {
        'academics' => SchoolRecordAcademicData.fromJson(value),
        'volunteers' => SchoolRecordVolunteerData.fromJson(value),
        'certificates' => SchoolRecordCertificateData.fromJson(value),
        'theses' => SchoolRecordThesisData.fromJson(value),
        _ => throw const FormatException('Unknown school record kind'),
      };
}

class SchoolRecordContext implements SchoolRecordPayload {
  const SchoolRecordContext({
    this.departmentId,
    this.curriculumId,
    this.admissionYear,
    this.track,
  });
  final String? departmentId;
  final String? curriculumId;
  final int? admissionYear;
  final String? track;
  factory SchoolRecordContext.fromJson(Map<String, dynamic> value) =>
      SchoolRecordContext(
        departmentId: value['department_id'] == null
            ? null
            : value['department_id'] as String,
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
    'department_id': departmentId,
    'curriculum_id': curriculumId,
    'admission_year': admissionYear,
    'track': track,
  };
}

class SchoolRecordAcademicRecord implements SchoolRecordPayload {
  const SchoolRecordAcademicRecord({
    required this.clientId,
    required this.sourcePage,
    required this.courseId,
    required this.expectedCourseVersion,
    required this.completionStatus,
    this.earnedCredits,
    this.category,
    this.originalGrade,
    this.gradePoints,
    this.gradeScale,
  });
  final String clientId;
  final int sourcePage;
  final String courseId;
  final int expectedCourseVersion;
  final String completionStatus;
  final String? earnedCredits;
  final String? category;
  final String? originalGrade;
  final String? gradePoints;
  final String? gradeScale;
  factory SchoolRecordAcademicRecord.fromJson(Map<String, dynamic> value) =>
      SchoolRecordAcademicRecord(
        clientId: value['client_id'] as String,
        sourcePage: value['source_page'] as int,
        courseId: value['course_id'] as String,
        expectedCourseVersion: value['expected_course_version'] as int,
        completionStatus: _choice(value['completion_status'], [
          "completed",
          "failed",
          "in_progress",
          "needs_review",
        ]),
        earnedCredits: value['earned_credits'] == null
            ? null
            : _decimal(value['earned_credits']),
        category: value['category'] == null
            ? null
            : value['category'] as String,
        originalGrade: value['original_grade'] == null
            ? null
            : value['original_grade'] as String,
        gradePoints: value['grade_points'] == null
            ? null
            : _decimal(value['grade_points']),
        gradeScale: value['grade_scale'] == null
            ? null
            : value['grade_scale'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'client_id': clientId,
    'source_page': sourcePage,
    'course_id': courseId,
    'expected_course_version': expectedCourseVersion,
    'completion_status': completionStatus,
    'earned_credits': earnedCredits,
    'category': category,
    'original_grade': originalGrade,
    'grade_points': gradePoints,
    'grade_scale': gradeScale,
  };
}

class SchoolRecordVolunteerRecord implements SchoolRecordPayload {
  const SchoolRecordVolunteerRecord({
    required this.clientId,
    required this.sourcePage,
    required this.approvalStatus,
    this.approvedHours,
  });
  final String clientId;
  final int sourcePage;
  final String approvalStatus;
  final String? approvedHours;
  factory SchoolRecordVolunteerRecord.fromJson(Map<String, dynamic> value) =>
      SchoolRecordVolunteerRecord(
        clientId: value['client_id'] as String,
        sourcePage: value['source_page'] as int,
        approvalStatus: _choice(value['approval_status'], [
          "approved",
          "pending",
          "rejected",
          "needs_review",
        ]),
        approvedHours: value['approved_hours'] == null
            ? null
            : _decimal(value['approved_hours']),
      );
  @override
  Map<String, Object?> toJson() => {
    'client_id': clientId,
    'source_page': sourcePage,
    'approval_status': approvalStatus,
    'approved_hours': approvedHours,
  };
}

class SchoolRecordCertificateRecord implements SchoolRecordPayload {
  const SchoolRecordCertificateRecord({
    required this.clientId,
    required this.sourcePage,
    required this.certificateId,
    required this.expectedCertificateVersion,
    required this.approvalStatus,
    this.expiresOn,
    this.validityKnown = false,
  });
  final String clientId;
  final int sourcePage;
  final String certificateId;
  final int expectedCertificateVersion;
  final String approvalStatus;
  final String? expiresOn;
  final bool validityKnown;
  factory SchoolRecordCertificateRecord.fromJson(Map<String, dynamic> value) =>
      SchoolRecordCertificateRecord(
        clientId: value['client_id'] as String,
        sourcePage: value['source_page'] as int,
        certificateId: value['certificate_id'] as String,
        expectedCertificateVersion:
            value['expected_certificate_version'] as int,
        approvalStatus: _choice(value['approval_status'], [
          "approved",
          "pending",
          "rejected",
          "needs_review",
        ]),
        expiresOn: value['expires_on'] == null
            ? null
            : value['expires_on'] as String,
        validityKnown: value['validity_known'] == null
            ? false
            : value['validity_known'] as bool,
      );
  @override
  Map<String, Object?> toJson() => {
    'client_id': clientId,
    'source_page': sourcePage,
    'certificate_id': certificateId,
    'expected_certificate_version': expectedCertificateVersion,
    'approval_status': approvalStatus,
    'expires_on': expiresOn,
    'validity_known': validityKnown,
  };
}

class SchoolRecordThesisRecord implements SchoolRecordPayload {
  const SchoolRecordThesisRecord({
    required this.clientId,
    required this.sourcePage,
    required this.thesisType,
    required this.approvalStatus,
    required this.isCompleted,
    this.grade,
  });
  final String clientId;
  final int sourcePage;
  final String thesisType;
  final String approvalStatus;
  final bool? isCompleted;
  final String? grade;
  factory SchoolRecordThesisRecord.fromJson(Map<String, dynamic> value) =>
      SchoolRecordThesisRecord(
        clientId: value['client_id'] as String,
        sourcePage: value['source_page'] as int,
        thesisType: value['thesis_type'] as String,
        approvalStatus: _choice(value['approval_status'], [
          "approved",
          "pending",
          "rejected",
          "needs_review",
        ]),
        isCompleted: value['is_completed'] == null
            ? null
            : value['is_completed'] as bool,
        grade: value['grade'] == null ? null : value['grade'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'client_id': clientId,
    'source_page': sourcePage,
    'thesis_type': thesisType,
    'approval_status': approvalStatus,
    'is_completed': isCompleted,
    'grade': grade,
  };
}

class SchoolRecordAcademicData extends SchoolRecordData {
  const SchoolRecordAcademicData({
    required this.pageCount,
    required this.recordsAsOf,
    required this.coverage,
    required this.context,
    required this.kind,
    required this.records,
  });
  final int pageCount;
  final String recordsAsOf;
  final String coverage;
  final SchoolRecordContext context;
  @override
  final String kind;
  final List<SchoolRecordAcademicRecord> records;
  factory SchoolRecordAcademicData.fromJson(Map<String, dynamic> value) =>
      SchoolRecordAcademicData(
        pageCount: value['page_count'] as int,
        recordsAsOf: value['records_as_of'] as String,
        coverage: _choice(value['coverage'], ["complete", "partial"]),
        context: SchoolRecordContext.fromJson(
          Map<String, dynamic>.from(value['context'] as Map),
        ),
        kind: _constant(value['kind'], "academics") as String,
        records: List.unmodifiable(
          (value['records'] as List).map(
            (v) => SchoolRecordAcademicRecord.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          ),
        ),
      );
  @override
  Map<String, Object?> toJson() => {
    'page_count': pageCount,
    'records_as_of': recordsAsOf,
    'coverage': coverage,
    'context': context.toJson(),
    'kind': kind,
    'records': records.map((v) => v.toJson()).toList(),
  };
}

class SchoolRecordVolunteerData extends SchoolRecordData {
  const SchoolRecordVolunteerData({
    required this.pageCount,
    required this.recordsAsOf,
    required this.coverage,
    required this.context,
    required this.kind,
    required this.records,
  });
  final int pageCount;
  final String recordsAsOf;
  final String coverage;
  final SchoolRecordContext context;
  @override
  final String kind;
  final List<SchoolRecordVolunteerRecord> records;
  factory SchoolRecordVolunteerData.fromJson(Map<String, dynamic> value) =>
      SchoolRecordVolunteerData(
        pageCount: value['page_count'] as int,
        recordsAsOf: value['records_as_of'] as String,
        coverage: _choice(value['coverage'], ["complete", "partial"]),
        context: SchoolRecordContext.fromJson(
          Map<String, dynamic>.from(value['context'] as Map),
        ),
        kind: _constant(value['kind'], "volunteers") as String,
        records: List.unmodifiable(
          (value['records'] as List).map(
            (v) => SchoolRecordVolunteerRecord.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          ),
        ),
      );
  @override
  Map<String, Object?> toJson() => {
    'page_count': pageCount,
    'records_as_of': recordsAsOf,
    'coverage': coverage,
    'context': context.toJson(),
    'kind': kind,
    'records': records.map((v) => v.toJson()).toList(),
  };
}

class SchoolRecordCertificateData extends SchoolRecordData {
  const SchoolRecordCertificateData({
    required this.pageCount,
    required this.recordsAsOf,
    required this.coverage,
    required this.context,
    required this.kind,
    required this.records,
  });
  final int pageCount;
  final String recordsAsOf;
  final String coverage;
  final SchoolRecordContext context;
  @override
  final String kind;
  final List<SchoolRecordCertificateRecord> records;
  factory SchoolRecordCertificateData.fromJson(Map<String, dynamic> value) =>
      SchoolRecordCertificateData(
        pageCount: value['page_count'] as int,
        recordsAsOf: value['records_as_of'] as String,
        coverage: _choice(value['coverage'], ["complete", "partial"]),
        context: SchoolRecordContext.fromJson(
          Map<String, dynamic>.from(value['context'] as Map),
        ),
        kind: _constant(value['kind'], "certificates") as String,
        records: List.unmodifiable(
          (value['records'] as List).map(
            (v) => SchoolRecordCertificateRecord.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          ),
        ),
      );
  @override
  Map<String, Object?> toJson() => {
    'page_count': pageCount,
    'records_as_of': recordsAsOf,
    'coverage': coverage,
    'context': context.toJson(),
    'kind': kind,
    'records': records.map((v) => v.toJson()).toList(),
  };
}

class SchoolRecordThesisData extends SchoolRecordData {
  const SchoolRecordThesisData({
    required this.pageCount,
    required this.recordsAsOf,
    required this.coverage,
    required this.context,
    required this.kind,
    required this.records,
  });
  final int pageCount;
  final String recordsAsOf;
  final String coverage;
  final SchoolRecordContext context;
  @override
  final String kind;
  final List<SchoolRecordThesisRecord> records;
  factory SchoolRecordThesisData.fromJson(Map<String, dynamic> value) =>
      SchoolRecordThesisData(
        pageCount: value['page_count'] as int,
        recordsAsOf: value['records_as_of'] as String,
        coverage: _choice(value['coverage'], ["complete", "partial"]),
        context: SchoolRecordContext.fromJson(
          Map<String, dynamic>.from(value['context'] as Map),
        ),
        kind: _constant(value['kind'], "theses") as String,
        records: List.unmodifiable(
          (value['records'] as List).map(
            (v) => SchoolRecordThesisRecord.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          ),
        ),
      );
  @override
  Map<String, Object?> toJson() => {
    'page_count': pageCount,
    'records_as_of': recordsAsOf,
    'coverage': coverage,
    'context': context.toJson(),
    'kind': kind,
    'records': records.map((v) => v.toJson()).toList(),
  };
}

class SchoolRecordBatchCreate implements SchoolRecordPayload {
  const SchoolRecordBatchCreate({
    required this.sourceId,
    required this.expectedSourceVersion,
    required this.clientId,
    required this.data,
  });
  final String sourceId;
  final int expectedSourceVersion;
  final String clientId;
  final SchoolRecordData data;
  factory SchoolRecordBatchCreate.fromJson(Map<String, dynamic> value) =>
      SchoolRecordBatchCreate(
        sourceId: value['source_id'] as String,
        expectedSourceVersion: value['expected_source_version'] as int,
        clientId: value['client_id'] as String,
        data: SchoolRecordData.fromJson(
          Map<String, dynamic>.from(value['data'] as Map),
        ),
      );
  @override
  Map<String, Object?> toJson() => {
    'source_id': sourceId,
    'expected_source_version': expectedSourceVersion,
    'client_id': clientId,
    'data': data.toJson(),
  };
}

class SchoolRecordBatchReplace implements SchoolRecordPayload {
  const SchoolRecordBatchReplace({
    required this.expectedVersion,
    required this.data,
  });
  final int expectedVersion;
  final SchoolRecordData data;
  factory SchoolRecordBatchReplace.fromJson(Map<String, dynamic> value) =>
      SchoolRecordBatchReplace(
        expectedVersion: value['expected_version'] as int,
        data: SchoolRecordData.fromJson(
          Map<String, dynamic>.from(value['data'] as Map),
        ),
      );
  @override
  Map<String, Object?> toJson() => {
    'expected_version': expectedVersion,
    'data': data.toJson(),
  };
}

class SchoolRecordBatchApprove implements SchoolRecordPayload {
  const SchoolRecordBatchApprove({
    required this.expectedVersion,
    required this.expectedSourceSha256,
    required this.recordsReviewed,
    required this.contextReviewed,
    required this.coverageReviewed,
    this.replacesBatchId,
    this.expectedReplacedVersion,
  });
  final int expectedVersion;
  final String expectedSourceSha256;
  final bool recordsReviewed;
  final bool contextReviewed;
  final bool coverageReviewed;
  final String? replacesBatchId;
  final int? expectedReplacedVersion;
  factory SchoolRecordBatchApprove.fromJson(Map<String, dynamic> value) =>
      SchoolRecordBatchApprove(
        expectedVersion: value['expected_version'] as int,
        expectedSourceSha256: value['expected_source_sha256'] as String,
        recordsReviewed: value['records_reviewed'] as bool,
        contextReviewed: value['context_reviewed'] as bool,
        coverageReviewed: value['coverage_reviewed'] as bool,
        replacesBatchId: value['replaces_batch_id'] == null
            ? null
            : value['replaces_batch_id'] as String,
        expectedReplacedVersion: value['expected_replaced_version'] == null
            ? null
            : value['expected_replaced_version'] as int,
      );
  @override
  Map<String, Object?> toJson() => {
    'expected_version': expectedVersion,
    'expected_source_sha256': expectedSourceSha256,
    'records_reviewed': recordsReviewed,
    'context_reviewed': contextReviewed,
    'coverage_reviewed': coverageReviewed,
    'replaces_batch_id': replacesBatchId,
    'expected_replaced_version': expectedReplacedVersion,
  };
}

class SchoolRecordBatchRevoke implements SchoolRecordPayload {
  const SchoolRecordBatchRevoke({
    required this.expectedVersion,
    required this.reason,
  });
  final int expectedVersion;
  final String reason;
  factory SchoolRecordBatchRevoke.fromJson(Map<String, dynamic> value) =>
      SchoolRecordBatchRevoke(
        expectedVersion: value['expected_version'] as int,
        reason: value['reason'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'expected_version': expectedVersion,
    'reason': reason,
  };
}

class SchoolRecordReferenceSnapshot implements SchoolRecordPayload {
  const SchoolRecordReferenceSnapshot({
    required this.kind,
    required this.id,
    required this.version,
    required this.code,
    required this.name,
    this.providerId,
    this.providerVersion,
    this.providerName,
  });
  final String kind;
  final String id;
  final int version;
  final String code;
  final String name;
  final String? providerId;
  final int? providerVersion;
  final String? providerName;
  factory SchoolRecordReferenceSnapshot.fromJson(Map<String, dynamic> value) =>
      SchoolRecordReferenceSnapshot(
        kind: _choice(value['kind'], ["course", "certificate"]),
        id: value['id'] as String,
        version: value['version'] as int,
        code: value['code'] as String,
        name: value['name'] as String,
        providerId: value['provider_id'] == null
            ? null
            : value['provider_id'] as String,
        providerVersion: value['provider_version'] == null
            ? null
            : value['provider_version'] as int,
        providerName: value['provider_name'] == null
            ? null
            : value['provider_name'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'id': id,
    'version': version,
    'code': code,
    'name': name,
    'provider_id': providerId,
    'provider_version': providerVersion,
    'provider_name': providerName,
  };
}

class SchoolRecordBatchHeader implements SchoolRecordPayload {
  const SchoolRecordBatchHeader({
    required this.id,
    required this.ownerId,
    required this.sourceId,
    required this.sourceVersion,
    required this.sourceSha256,
    required this.institutionId,
    required this.clientId,
    required this.kind,
    required this.status,
    required this.version,
    required this.context,
    required this.coverage,
    required this.pageCount,
    required this.recordsAsOf,
    required this.recordCount,
    required this.usableForAudit,
    required this.issues,
    this.graduationEligible = false,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String ownerId;
  final String sourceId;
  final int sourceVersion;
  final String sourceSha256;
  final String institutionId;
  final String clientId;
  final String kind;
  final String status;
  final int version;
  final SchoolRecordContext context;
  final String coverage;
  final int pageCount;
  final String recordsAsOf;
  final int recordCount;
  final bool usableForAudit;
  final List<String> issues;
  final bool graduationEligible;
  final DateTime createdAt;
  final DateTime updatedAt;
  factory SchoolRecordBatchHeader.fromJson(Map<String, dynamic> value) =>
      SchoolRecordBatchHeader(
        id: value['id'] as String,
        ownerId: value['owner_id'] as String,
        sourceId: value['source_id'] as String,
        sourceVersion: value['source_version'] as int,
        sourceSha256: value['source_sha256'] as String,
        institutionId: value['institution_id'] as String,
        clientId: value['client_id'] as String,
        kind: _choice(value['kind'], [
          "academics",
          "volunteers",
          "certificates",
          "theses",
        ]),
        status: _choice(value['status'], [
          "draft",
          "approved",
          "revoked",
          "superseded",
          "discarded",
        ]),
        version: value['version'] as int,
        context: SchoolRecordContext.fromJson(
          Map<String, dynamic>.from(value['context'] as Map),
        ),
        coverage: _choice(value['coverage'], ["complete", "partial"]),
        pageCount: value['page_count'] as int,
        recordsAsOf: value['records_as_of'] as String,
        recordCount: value['record_count'] as int,
        usableForAudit: value['usable_for_audit'] as bool,
        issues: List.unmodifiable(
          (value['issues'] as List).map(
            (v) => _choice(v, [
              "source_unavailable",
              "source_changed",
              "reference_changed",
              "context_incomplete",
              "partial_records",
              "not_approved",
              "snapshot_date_mismatch",
            ]),
          ),
        ),
        graduationEligible: value['graduation_eligible'] == null
            ? false
            : _constant(value['graduation_eligible'], false) as bool,
        createdAt: DateTime.parse(value['created_at'] as String),
        updatedAt: DateTime.parse(value['updated_at'] as String),
      );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'owner_id': ownerId,
    'source_id': sourceId,
    'source_version': sourceVersion,
    'source_sha256': sourceSha256,
    'institution_id': institutionId,
    'client_id': clientId,
    'kind': kind,
    'status': status,
    'version': version,
    'context': context.toJson(),
    'coverage': coverage,
    'page_count': pageCount,
    'records_as_of': recordsAsOf,
    'record_count': recordCount,
    'usable_for_audit': usableForAudit,
    'issues': issues.map((v) => v).toList(),
    'graduation_eligible': graduationEligible,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}

class SchoolRecordBatchView implements SchoolRecordPayload {
  const SchoolRecordBatchView({
    required this.id,
    required this.ownerId,
    required this.sourceId,
    required this.sourceVersion,
    required this.sourceSha256,
    required this.institutionId,
    required this.clientId,
    required this.kind,
    required this.status,
    required this.version,
    required this.context,
    required this.coverage,
    required this.pageCount,
    required this.recordsAsOf,
    required this.recordCount,
    required this.usableForAudit,
    required this.issues,
    this.graduationEligible = false,
    required this.createdAt,
    required this.updatedAt,
    required this.data,
    required this.references,
  });
  final String id;
  final String ownerId;
  final String sourceId;
  final int sourceVersion;
  final String sourceSha256;
  final String institutionId;
  final String clientId;
  final String kind;
  final String status;
  final int version;
  final SchoolRecordContext context;
  final String coverage;
  final int pageCount;
  final String recordsAsOf;
  final int recordCount;
  final bool usableForAudit;
  final List<String> issues;
  final bool graduationEligible;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SchoolRecordData data;
  final List<SchoolRecordReferenceSnapshot> references;
  factory SchoolRecordBatchView.fromJson(Map<String, dynamic> value) =>
      SchoolRecordBatchView(
        id: value['id'] as String,
        ownerId: value['owner_id'] as String,
        sourceId: value['source_id'] as String,
        sourceVersion: value['source_version'] as int,
        sourceSha256: value['source_sha256'] as String,
        institutionId: value['institution_id'] as String,
        clientId: value['client_id'] as String,
        kind: _choice(value['kind'], [
          "academics",
          "volunteers",
          "certificates",
          "theses",
        ]),
        status: _choice(value['status'], [
          "draft",
          "approved",
          "revoked",
          "superseded",
          "discarded",
        ]),
        version: value['version'] as int,
        context: SchoolRecordContext.fromJson(
          Map<String, dynamic>.from(value['context'] as Map),
        ),
        coverage: _choice(value['coverage'], ["complete", "partial"]),
        pageCount: value['page_count'] as int,
        recordsAsOf: value['records_as_of'] as String,
        recordCount: value['record_count'] as int,
        usableForAudit: value['usable_for_audit'] as bool,
        issues: List.unmodifiable(
          (value['issues'] as List).map(
            (v) => _choice(v, [
              "source_unavailable",
              "source_changed",
              "reference_changed",
              "context_incomplete",
              "partial_records",
              "not_approved",
              "snapshot_date_mismatch",
            ]),
          ),
        ),
        graduationEligible: value['graduation_eligible'] == null
            ? false
            : _constant(value['graduation_eligible'], false) as bool,
        createdAt: DateTime.parse(value['created_at'] as String),
        updatedAt: DateTime.parse(value['updated_at'] as String),
        data: SchoolRecordData.fromJson(
          Map<String, dynamic>.from(value['data'] as Map),
        ),
        references: List.unmodifiable(
          (value['references'] as List).map(
            (v) => SchoolRecordReferenceSnapshot.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          ),
        ),
      );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'owner_id': ownerId,
    'source_id': sourceId,
    'source_version': sourceVersion,
    'source_sha256': sourceSha256,
    'institution_id': institutionId,
    'client_id': clientId,
    'kind': kind,
    'status': status,
    'version': version,
    'context': context.toJson(),
    'coverage': coverage,
    'page_count': pageCount,
    'records_as_of': recordsAsOf,
    'record_count': recordCount,
    'usable_for_audit': usableForAudit,
    'issues': issues.map((v) => v).toList(),
    'graduation_eligible': graduationEligible,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'data': data.toJson(),
    'references': references.map((v) => v.toJson()).toList(),
  };
}

class SchoolRecordBatchList implements SchoolRecordPayload {
  const SchoolRecordBatchList({required this.items, this.nextCursor});
  final List<SchoolRecordBatchHeader> items;
  final String? nextCursor;
  factory SchoolRecordBatchList.fromJson(Map<String, dynamic> value) =>
      SchoolRecordBatchList(
        items: List.unmodifiable(
          (value['items'] as List).map(
            (v) => SchoolRecordBatchHeader.fromJson(
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

class SchoolRecordBatchEventView implements SchoolRecordPayload {
  const SchoolRecordBatchEventView({
    required this.id,
    required this.batchId,
    required this.actorId,
    required this.action,
    required this.version,
    required this.reason,
    required this.occurredAt,
  });
  final String id;
  final String batchId;
  final String? actorId;
  final String action;
  final int version;
  final String reason;
  final DateTime occurredAt;
  factory SchoolRecordBatchEventView.fromJson(Map<String, dynamic> value) =>
      SchoolRecordBatchEventView(
        id: value['id'] as String,
        batchId: value['batch_id'] as String,
        actorId: value['actor_id'] == null ? null : value['actor_id'] as String,
        action: _choice(value['action'], [
          "created",
          "replaced",
          "approved",
          "revoked",
          "superseded",
          "source_revoked",
          "source_withdrawn",
          "discarded",
        ]),
        version: value['version'] as int,
        reason: value['reason'] as String,
        occurredAt: DateTime.parse(value['occurred_at'] as String),
      );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'batch_id': batchId,
    'actor_id': actorId,
    'action': action,
    'version': version,
    'reason': reason,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
  };
}

class SchoolRecordBatchEventList implements SchoolRecordPayload {
  const SchoolRecordBatchEventList({required this.items});
  final List<SchoolRecordBatchEventView> items;
  factory SchoolRecordBatchEventList.fromJson(Map<String, dynamic> value) =>
      SchoolRecordBatchEventList(
        items: List.unmodifiable(
          (value['items'] as List).map(
            (v) => SchoolRecordBatchEventView.fromJson(
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
