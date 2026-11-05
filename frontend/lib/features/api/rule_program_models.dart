// GENERATED from Pydantic: scripts/export_rule_program_contracts.py.
// UUIDs/dates/decimal amounts remain strings; no UI or persistence effects.
abstract interface class OfficialPayload {
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

sealed class OfficialCondition implements OfficialPayload {
  const OfficialCondition();
  String get kind;
  factory OfficialCondition.fromJson(Map<String, dynamic> value) =>
      switch (value['kind']) {
        'minimum_credits' => OfficialCreditCriterion.fromJson(value),
        'required_courses' => OfficialCourseCriterion.fromJson(value),
        'minimum_volunteer_hours' => OfficialVolunteerCriterion.fromJson(value),
        'any_certificate' => OfficialCertificateCriterion.fromJson(value),
        'thesis' => OfficialThesisCriterion.fromJson(value),
        'manual_review' => OfficialManualCriterion.fromJson(value),
        _ => throw const FormatException('Unknown execution criterion'),
      };
}

class OfficialProgramRequiredCourse implements OfficialPayload {
  const OfficialProgramRequiredCourse({
    required this.courseId,
    required this.expectedVersion,
    this.minimumCredits,
    this.minimumGradePoints,
    this.comparisonGradeScale,
  });
  final String courseId;
  final int expectedVersion;
  final String? minimumCredits;
  final String? minimumGradePoints;
  final String? comparisonGradeScale;
  factory OfficialProgramRequiredCourse.fromJson(Map<String, dynamic> value) =>
      OfficialProgramRequiredCourse(
        courseId: value['course_id'] as String,
        expectedVersion: value['expected_version'] as int,
        minimumCredits: value['minimum_credits'] == null
            ? null
            : _decimal(value['minimum_credits']),
        minimumGradePoints: value['minimum_grade_points'] == null
            ? null
            : _decimal(value['minimum_grade_points']),
        comparisonGradeScale: value['comparison_grade_scale'] == null
            ? null
            : value['comparison_grade_scale'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'course_id': courseId,
    'expected_version': expectedVersion,
    'minimum_credits': minimumCredits,
    'minimum_grade_points': minimumGradePoints,
    'comparison_grade_scale': comparisonGradeScale,
  };
}

class OfficialCertificateChoice implements OfficialPayload {
  const OfficialCertificateChoice({
    required this.certificateId,
    required this.expectedVersion,
  });
  final String certificateId;
  final int expectedVersion;
  factory OfficialCertificateChoice.fromJson(Map<String, dynamic> value) =>
      OfficialCertificateChoice(
        certificateId: value['certificate_id'] as String,
        expectedVersion: value['expected_version'] as int,
      );
  @override
  Map<String, Object?> toJson() => {
    'certificate_id': certificateId,
    'expected_version': expectedVersion,
  };
}

class OfficialCreditCriterion extends OfficialCondition {
  const OfficialCreditCriterion({
    required this.kind,
    required this.minimum,
    this.category,
  });
  @override
  final String kind;
  final String minimum;
  final String? category;
  factory OfficialCreditCriterion.fromJson(Map<String, dynamic> value) =>
      OfficialCreditCriterion(
        kind: _constant(value['kind'], "minimum_credits") as String,
        minimum: _decimal(value['minimum']),
        category: value['category'] == null
            ? null
            : value['category'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'minimum': minimum,
    'category': category,
  };
}

class OfficialCourseCriterion extends OfficialCondition {
  const OfficialCourseCriterion({required this.kind, required this.courses});
  @override
  final String kind;
  final List<OfficialProgramRequiredCourse> courses;
  factory OfficialCourseCriterion.fromJson(Map<String, dynamic> value) =>
      OfficialCourseCriterion(
        kind: _constant(value['kind'], "required_courses") as String,
        courses: List.unmodifiable(
          (value['courses'] as List).map(
            (v) => OfficialProgramRequiredCourse.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          ),
        ),
      );
  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'courses': courses.map((v) => v.toJson()).toList(),
  };
}

class OfficialVolunteerCriterion extends OfficialCondition {
  const OfficialVolunteerCriterion({required this.kind, required this.minimum});
  @override
  final String kind;
  final String minimum;
  factory OfficialVolunteerCriterion.fromJson(Map<String, dynamic> value) =>
      OfficialVolunteerCriterion(
        kind: _constant(value['kind'], "minimum_volunteer_hours") as String,
        minimum: _decimal(value['minimum']),
      );
  @override
  Map<String, Object?> toJson() => {'kind': kind, 'minimum': minimum};
}

class OfficialCertificateCriterion extends OfficialCondition {
  const OfficialCertificateCriterion({
    required this.kind,
    required this.certificates,
  });
  @override
  final String kind;
  final List<OfficialCertificateChoice> certificates;
  factory OfficialCertificateCriterion.fromJson(Map<String, dynamic> value) =>
      OfficialCertificateCriterion(
        kind: _constant(value['kind'], "any_certificate") as String,
        certificates: List.unmodifiable(
          (value['certificates'] as List).map(
            (v) => OfficialCertificateChoice.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          ),
        ),
      );
  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'certificates': certificates.map((v) => v.toJson()).toList(),
  };
}

class OfficialThesisCriterion extends OfficialCondition {
  const OfficialThesisCriterion({
    required this.kind,
    required this.thesisType,
    this.requiresApproval = true,
    this.acceptedGrades = const [],
  });
  @override
  final String kind;
  final String thesisType;
  final bool requiresApproval;
  final List<String> acceptedGrades;
  factory OfficialThesisCriterion.fromJson(Map<String, dynamic> value) =>
      OfficialThesisCriterion(
        kind: _constant(value['kind'], "thesis") as String,
        thesisType: value['thesis_type'] as String,
        requiresApproval: value['requires_approval'] == null
            ? true
            : value['requires_approval'] as bool,
        acceptedGrades: value['accepted_grades'] == null
            ? const []
            : List.unmodifiable(
                (value['accepted_grades'] as List).map((v) => v as String),
              ),
      );
  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'thesis_type': thesisType,
    'requires_approval': requiresApproval,
    'accepted_grades': acceptedGrades.map((v) => v).toList(),
  };
}

class OfficialManualCriterion extends OfficialCondition {
  const OfficialManualCriterion({
    required this.kind,
    required this.instruction,
  });
  @override
  final String kind;
  final String instruction;
  factory OfficialManualCriterion.fromJson(Map<String, dynamic> value) =>
      OfficialManualCriterion(
        kind: _constant(value['kind'], "manual_review") as String,
        instruction: value['instruction'] as String,
      );
  @override
  Map<String, Object?> toJson() => {'kind': kind, 'instruction': instruction};
}

class OfficialProgramRuleInput implements OfficialPayload {
  const OfficialProgramRuleInput({
    required this.ruleId,
    required this.expectedVersion,
    required this.condition,
    required this.evidenceChunkIds,
  });
  final String ruleId;
  final int expectedVersion;
  final OfficialCondition condition;
  final List<String> evidenceChunkIds;
  factory OfficialProgramRuleInput.fromJson(Map<String, dynamic> value) =>
      OfficialProgramRuleInput(
        ruleId: value['rule_id'] as String,
        expectedVersion: value['expected_version'] as int,
        condition: OfficialCondition.fromJson(
          Map<String, dynamic>.from(value['condition'] as Map),
        ),
        evidenceChunkIds: List.unmodifiable(
          (value['evidence_chunk_ids'] as List).map((v) => v as String),
        ),
      );
  @override
  Map<String, Object?> toJson() => {
    'rule_id': ruleId,
    'expected_version': expectedVersion,
    'condition': condition.toJson(),
    'evidence_chunk_ids': evidenceChunkIds.map((v) => v).toList(),
  };
}

class OfficialProgramCreate implements OfficialPayload {
  const OfficialProgramCreate({
    required this.admissionYearFrom,
    required this.admissionYearTo,
    required this.tracks,
    this.rules = const [],
    this.ruleSetId,
    this.ruleId,
    required this.expectedSourceVersion,
  });
  final int admissionYearFrom;
  final int admissionYearTo;
  final List<String> tracks;
  final List<OfficialProgramRuleInput> rules;
  final String? ruleSetId;
  final String? ruleId;
  final int expectedSourceVersion;
  factory OfficialProgramCreate.fromJson(Map<String, dynamic> value) =>
      OfficialProgramCreate(
        admissionYearFrom: value['admission_year_from'] as int,
        admissionYearTo: value['admission_year_to'] as int,
        tracks: List.unmodifiable(
          (value['tracks'] as List).map((v) => v as String),
        ),
        rules: value['rules'] == null
            ? const []
            : List.unmodifiable(
                (value['rules'] as List).map(
                  (v) => OfficialProgramRuleInput.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              ),
        ruleSetId: value['rule_set_id'] == null
            ? null
            : value['rule_set_id'] as String,
        ruleId: value['rule_id'] == null ? null : value['rule_id'] as String,
        expectedSourceVersion: value['expected_source_version'] as int,
      );
  @override
  Map<String, Object?> toJson() => {
    'admission_year_from': admissionYearFrom,
    'admission_year_to': admissionYearTo,
    'tracks': tracks.map((v) => v).toList(),
    'rules': rules.map((v) => v.toJson()).toList(),
    'rule_set_id': ruleSetId,
    'rule_id': ruleId,
    'expected_source_version': expectedSourceVersion,
  };
}

class OfficialProgramReplace implements OfficialPayload {
  const OfficialProgramReplace({
    required this.admissionYearFrom,
    required this.admissionYearTo,
    required this.tracks,
    this.rules = const [],
    required this.expectedVersion,
  });
  final int admissionYearFrom;
  final int admissionYearTo;
  final List<String> tracks;
  final List<OfficialProgramRuleInput> rules;
  final int expectedVersion;
  factory OfficialProgramReplace.fromJson(Map<String, dynamic> value) =>
      OfficialProgramReplace(
        admissionYearFrom: value['admission_year_from'] as int,
        admissionYearTo: value['admission_year_to'] as int,
        tracks: List.unmodifiable(
          (value['tracks'] as List).map((v) => v as String),
        ),
        rules: value['rules'] == null
            ? const []
            : List.unmodifiable(
                (value['rules'] as List).map(
                  (v) => OfficialProgramRuleInput.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              ),
        expectedVersion: value['expected_version'] as int,
      );
  @override
  Map<String, Object?> toJson() => {
    'admission_year_from': admissionYearFrom,
    'admission_year_to': admissionYearTo,
    'tracks': tracks.map((v) => v).toList(),
    'rules': rules.map((v) => v.toJson()).toList(),
    'expected_version': expectedVersion,
  };
}

class OfficialProgramApprove implements OfficialPayload {
  const OfficialProgramApprove({
    required this.expectedVersion,
    required this.conditionsVerified,
    required this.sourcesVerified,
    required this.applicabilityVerified,
    required this.completeSourceContextVerified,
    required this.reviewNote,
  });
  final int expectedVersion;
  final bool conditionsVerified;
  final bool sourcesVerified;
  final bool applicabilityVerified;
  final bool completeSourceContextVerified;
  final String reviewNote;
  factory OfficialProgramApprove.fromJson(Map<String, dynamic> value) =>
      OfficialProgramApprove(
        expectedVersion: value['expected_version'] as int,
        conditionsVerified: value['conditions_verified'] as bool,
        sourcesVerified: value['sources_verified'] as bool,
        applicabilityVerified: value['applicability_verified'] as bool,
        completeSourceContextVerified:
            value['complete_source_context_verified'] as bool,
        reviewNote: value['review_note'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'expected_version': expectedVersion,
    'conditions_verified': conditionsVerified,
    'sources_verified': sourcesVerified,
    'applicability_verified': applicabilityVerified,
    'complete_source_context_verified': completeSourceContextVerified,
    'review_note': reviewNote,
  };
}

class OfficialProgramRevoke implements OfficialPayload {
  const OfficialProgramRevoke({
    required this.expectedVersion,
    required this.reason,
  });
  final int expectedVersion;
  final String reason;
  factory OfficialProgramRevoke.fromJson(Map<String, dynamic> value) =>
      OfficialProgramRevoke(
        expectedVersion: value['expected_version'] as int,
        reason: value['reason'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'expected_version': expectedVersion,
    'reason': reason,
  };
}

class OfficialEvidenceView implements OfficialPayload {
  const OfficialEvidenceView({
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
    required this.excerpt,
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
  final String excerpt;
  factory OfficialEvidenceView.fromJson(Map<String, dynamic> value) =>
      OfficialEvidenceView(
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
        excerpt: value['excerpt'] as String,
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
    'excerpt': excerpt,
  };
}

class OfficialReferenceSnapshot implements OfficialPayload {
  const OfficialReferenceSnapshot({
    required this.kind,
    required this.recordId,
    required this.version,
    required this.code,
    required this.name,
    this.providerName,
  });
  final String kind;
  final String recordId;
  final int version;
  final String code;
  final String name;
  final String? providerName;
  factory OfficialReferenceSnapshot.fromJson(Map<String, dynamic> value) =>
      OfficialReferenceSnapshot(
        kind: _choice(value['kind'], ["course", "certificate"]),
        recordId: value['record_id'] as String,
        version: value['version'] as int,
        code: value['code'] as String,
        name: value['name'] as String,
        providerName: value['provider_name'] == null
            ? null
            : value['provider_name'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'record_id': recordId,
    'version': version,
    'code': code,
    'name': name,
    'provider_name': providerName,
  };
}

class OfficialProgramRuleView implements OfficialPayload {
  const OfficialProgramRuleView({
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
  final List<OfficialEvidenceView> evidence;
  final List<OfficialReferenceSnapshot> references;
  factory OfficialProgramRuleView.fromJson(Map<String, dynamic> value) =>
      OfficialProgramRuleView(
        ruleId: value['rule_id'] as String,
        sourceVersion: value['source_version'] as int,
        title: value['title'] as String,
        condition: OfficialCondition.fromJson(
          Map<String, dynamic>.from(value['condition'] as Map),
        ),
        evidence: List.unmodifiable(
          (value['evidence'] as List).map(
            (v) => OfficialEvidenceView.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
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

class OfficialProgramHeader implements OfficialPayload {
  const OfficialProgramHeader({
    required this.id,
    required this.institutionId,
    required this.departmentId,
    required this.curriculumId,
    required this.name,
    required this.ruleSetId,
    required this.ruleId,
    required this.sourceVersion,
    required this.version,
    required this.admissionYearFrom,
    required this.admissionYearTo,
    required this.tracks,
    required this.effectiveFrom,
    required this.effectiveTo,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.approvedAt,
    required this.revokedAt,
  });
  final String id;
  final String institutionId;
  final String? departmentId;
  final String? curriculumId;
  final String name;
  final String? ruleSetId;
  final String? ruleId;
  final int sourceVersion;
  final int version;
  final int admissionYearFrom;
  final int admissionYearTo;
  final List<String> tracks;
  final String? effectiveFrom;
  final String? effectiveTo;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? approvedAt;
  final DateTime? revokedAt;
  factory OfficialProgramHeader.fromJson(Map<String, dynamic> value) =>
      OfficialProgramHeader(
        id: value['id'] as String,
        institutionId: value['institution_id'] as String,
        departmentId: value['department_id'] == null
            ? null
            : value['department_id'] as String,
        curriculumId: value['curriculum_id'] == null
            ? null
            : value['curriculum_id'] as String,
        name: value['name'] as String,
        ruleSetId: value['rule_set_id'] == null
            ? null
            : value['rule_set_id'] as String,
        ruleId: value['rule_id'] == null ? null : value['rule_id'] as String,
        sourceVersion: value['source_version'] as int,
        version: value['version'] as int,
        admissionYearFrom: value['admission_year_from'] as int,
        admissionYearTo: value['admission_year_to'] as int,
        tracks: List.unmodifiable(
          (value['tracks'] as List).map((v) => v as String),
        ),
        effectiveFrom: value['effective_from'] == null
            ? null
            : value['effective_from'] as String,
        effectiveTo: value['effective_to'] == null
            ? null
            : value['effective_to'] as String,
        status: _choice(value['status'], ["draft", "approved", "revoked"]),
        createdAt: DateTime.parse(value['created_at'] as String),
        updatedAt: DateTime.parse(value['updated_at'] as String),
        approvedAt: value['approved_at'] == null
            ? null
            : DateTime.parse(value['approved_at'] as String),
        revokedAt: value['revoked_at'] == null
            ? null
            : DateTime.parse(value['revoked_at'] as String),
      );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'institution_id': institutionId,
    'department_id': departmentId,
    'curriculum_id': curriculumId,
    'name': name,
    'rule_set_id': ruleSetId,
    'rule_id': ruleId,
    'source_version': sourceVersion,
    'version': version,
    'admission_year_from': admissionYearFrom,
    'admission_year_to': admissionYearTo,
    'tracks': tracks.map((v) => v).toList(),
    'effective_from': effectiveFrom,
    'effective_to': effectiveTo,
    'status': status,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'approved_at': approvedAt?.toUtc().toIso8601String(),
    'revoked_at': revokedAt?.toUtc().toIso8601String(),
  };
}

class OfficialProgramView implements OfficialPayload {
  const OfficialProgramView({
    required this.id,
    required this.institutionId,
    required this.departmentId,
    required this.curriculumId,
    required this.name,
    required this.ruleSetId,
    required this.ruleId,
    required this.sourceVersion,
    required this.version,
    required this.admissionYearFrom,
    required this.admissionYearTo,
    required this.tracks,
    required this.effectiveFrom,
    required this.effectiveTo,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.approvedAt,
    required this.revokedAt,
    required this.approvedBy,
    required this.reviewNote,
    required this.revokedBy,
    required this.revocationReason,
    required this.rules,
    required this.missingRuleIds,
    required this.usable,
  });
  final String id;
  final String institutionId;
  final String? departmentId;
  final String? curriculumId;
  final String name;
  final String? ruleSetId;
  final String? ruleId;
  final int sourceVersion;
  final int version;
  final int admissionYearFrom;
  final int admissionYearTo;
  final List<String> tracks;
  final String? effectiveFrom;
  final String? effectiveTo;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? approvedAt;
  final DateTime? revokedAt;
  final String? approvedBy;
  final String reviewNote;
  final String? revokedBy;
  final String revocationReason;
  final List<OfficialProgramRuleView> rules;
  final List<String> missingRuleIds;
  final bool usable;
  factory OfficialProgramView.fromJson(Map<String, dynamic> value) =>
      OfficialProgramView(
        id: value['id'] as String,
        institutionId: value['institution_id'] as String,
        departmentId: value['department_id'] == null
            ? null
            : value['department_id'] as String,
        curriculumId: value['curriculum_id'] == null
            ? null
            : value['curriculum_id'] as String,
        name: value['name'] as String,
        ruleSetId: value['rule_set_id'] == null
            ? null
            : value['rule_set_id'] as String,
        ruleId: value['rule_id'] == null ? null : value['rule_id'] as String,
        sourceVersion: value['source_version'] as int,
        version: value['version'] as int,
        admissionYearFrom: value['admission_year_from'] as int,
        admissionYearTo: value['admission_year_to'] as int,
        tracks: List.unmodifiable(
          (value['tracks'] as List).map((v) => v as String),
        ),
        effectiveFrom: value['effective_from'] == null
            ? null
            : value['effective_from'] as String,
        effectiveTo: value['effective_to'] == null
            ? null
            : value['effective_to'] as String,
        status: _choice(value['status'], ["draft", "approved", "revoked"]),
        createdAt: DateTime.parse(value['created_at'] as String),
        updatedAt: DateTime.parse(value['updated_at'] as String),
        approvedAt: value['approved_at'] == null
            ? null
            : DateTime.parse(value['approved_at'] as String),
        revokedAt: value['revoked_at'] == null
            ? null
            : DateTime.parse(value['revoked_at'] as String),
        approvedBy: value['approved_by'] == null
            ? null
            : value['approved_by'] as String,
        reviewNote: value['review_note'] as String,
        revokedBy: value['revoked_by'] == null
            ? null
            : value['revoked_by'] as String,
        revocationReason: value['revocation_reason'] as String,
        rules: List.unmodifiable(
          (value['rules'] as List).map(
            (v) => OfficialProgramRuleView.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          ),
        ),
        missingRuleIds: List.unmodifiable(
          (value['missing_rule_ids'] as List).map((v) => v as String),
        ),
        usable: value['usable'] as bool,
      );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'institution_id': institutionId,
    'department_id': departmentId,
    'curriculum_id': curriculumId,
    'name': name,
    'rule_set_id': ruleSetId,
    'rule_id': ruleId,
    'source_version': sourceVersion,
    'version': version,
    'admission_year_from': admissionYearFrom,
    'admission_year_to': admissionYearTo,
    'tracks': tracks.map((v) => v).toList(),
    'effective_from': effectiveFrom,
    'effective_to': effectiveTo,
    'status': status,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'approved_at': approvedAt?.toUtc().toIso8601String(),
    'revoked_at': revokedAt?.toUtc().toIso8601String(),
    'approved_by': approvedBy,
    'review_note': reviewNote,
    'revoked_by': revokedBy,
    'revocation_reason': revocationReason,
    'rules': rules.map((v) => v.toJson()).toList(),
    'missing_rule_ids': missingRuleIds.map((v) => v).toList(),
    'usable': usable,
  };
}

class OfficialProgramList implements OfficialPayload {
  const OfficialProgramList({required this.items, this.nextCursor});
  final List<OfficialProgramHeader> items;
  final String? nextCursor;
  factory OfficialProgramList.fromJson(Map<String, dynamic> value) =>
      OfficialProgramList(
        items: List.unmodifiable(
          (value['items'] as List).map(
            (v) => OfficialProgramHeader.fromJson(
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

class OfficialPublicProgram implements OfficialPayload {
  const OfficialPublicProgram({
    required this.id,
    required this.institutionId,
    required this.departmentId,
    required this.curriculumId,
    required this.name,
    required this.ruleSetId,
    required this.ruleId,
    required this.sourceVersion,
    required this.version,
    required this.admissionYearFrom,
    required this.admissionYearTo,
    required this.tracks,
    required this.effectiveFrom,
    required this.effectiveTo,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.approvedAt,
    required this.revokedAt,
    required this.rules,
  });
  final String id;
  final String institutionId;
  final String? departmentId;
  final String? curriculumId;
  final String name;
  final String? ruleSetId;
  final String? ruleId;
  final int sourceVersion;
  final int version;
  final int admissionYearFrom;
  final int admissionYearTo;
  final List<String> tracks;
  final String? effectiveFrom;
  final String? effectiveTo;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? approvedAt;
  final DateTime? revokedAt;
  final List<OfficialProgramRuleView> rules;
  factory OfficialPublicProgram.fromJson(Map<String, dynamic> value) =>
      OfficialPublicProgram(
        id: value['id'] as String,
        institutionId: value['institution_id'] as String,
        departmentId: value['department_id'] == null
            ? null
            : value['department_id'] as String,
        curriculumId: value['curriculum_id'] == null
            ? null
            : value['curriculum_id'] as String,
        name: value['name'] as String,
        ruleSetId: value['rule_set_id'] == null
            ? null
            : value['rule_set_id'] as String,
        ruleId: value['rule_id'] == null ? null : value['rule_id'] as String,
        sourceVersion: value['source_version'] as int,
        version: value['version'] as int,
        admissionYearFrom: value['admission_year_from'] as int,
        admissionYearTo: value['admission_year_to'] as int,
        tracks: List.unmodifiable(
          (value['tracks'] as List).map((v) => v as String),
        ),
        effectiveFrom: value['effective_from'] == null
            ? null
            : value['effective_from'] as String,
        effectiveTo: value['effective_to'] == null
            ? null
            : value['effective_to'] as String,
        status: _choice(value['status'], ["draft", "approved", "revoked"]),
        createdAt: DateTime.parse(value['created_at'] as String),
        updatedAt: DateTime.parse(value['updated_at'] as String),
        approvedAt: value['approved_at'] == null
            ? null
            : DateTime.parse(value['approved_at'] as String),
        revokedAt: value['revoked_at'] == null
            ? null
            : DateTime.parse(value['revoked_at'] as String),
        rules: List.unmodifiable(
          (value['rules'] as List).map(
            (v) => OfficialProgramRuleView.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          ),
        ),
      );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'institution_id': institutionId,
    'department_id': departmentId,
    'curriculum_id': curriculumId,
    'name': name,
    'rule_set_id': ruleSetId,
    'rule_id': ruleId,
    'source_version': sourceVersion,
    'version': version,
    'admission_year_from': admissionYearFrom,
    'admission_year_to': admissionYearTo,
    'tracks': tracks.map((v) => v).toList(),
    'effective_from': effectiveFrom,
    'effective_to': effectiveTo,
    'status': status,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'approved_at': approvedAt?.toUtc().toIso8601String(),
    'revoked_at': revokedAt?.toUtc().toIso8601String(),
    'rules': rules.map((v) => v.toJson()).toList(),
  };
}

class OfficialSelectionContext implements OfficialPayload {
  const OfficialSelectionContext({
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
  factory OfficialSelectionContext.fromJson(Map<String, dynamic> value) =>
      OfficialSelectionContext(
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

class OfficialSelectionIssue implements OfficialPayload {
  const OfficialSelectionIssue({
    required this.kind,
    required this.recordId,
    required this.reason,
  });
  final String kind;
  final String recordId;
  final String reason;
  factory OfficialSelectionIssue.fromJson(Map<String, dynamic> value) =>
      OfficialSelectionIssue(
        kind: _choice(value['kind'], ["rule_set", "rule"]),
        recordId: value['record_id'] as String,
        reason: _choice(value['reason'], [
          "execution_program_required",
          "ambiguous_rule_programs",
          "program_dependency_unavailable",
          "manual_requirement",
        ]),
      );
  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'record_id': recordId,
    'reason': reason,
  };
}

class OfficialProgramSelection implements OfficialPayload {
  const OfficialProgramSelection({
    required this.context,
    required this.asOf,
    required this.status,
    required this.reason,
    this.catalogComplete = false,
    required this.programs,
    required this.issues,
  });
  final OfficialSelectionContext context;
  final String asOf;
  final String status;
  final String reason;
  final bool catalogComplete;
  final List<OfficialPublicProgram> programs;
  final List<OfficialSelectionIssue> issues;
  factory OfficialProgramSelection.fromJson(Map<String, dynamic> value) =>
      OfficialProgramSelection(
        context: OfficialSelectionContext.fromJson(
          Map<String, dynamic>.from(value['context'] as Map),
        ),
        asOf: value['as_of'] as String,
        status: _choice(value['status'], [
          "available",
          "needs_review",
          "not_applicable",
        ]),
        reason: _choice(value['reason'], [
          "registered_programs_available",
          "rule_program_review_required",
          "no_registered_rule_metadata",
          "rule_catalog_limit_exceeded",
        ]),
        catalogComplete: value['catalog_complete'] == null
            ? false
            : _constant(value['catalog_complete'], false) as bool,
        programs: List.unmodifiable(
          (value['programs'] as List).map(
            (v) => OfficialPublicProgram.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          ),
        ),
        issues: List.unmodifiable(
          (value['issues'] as List).map(
            (v) => OfficialSelectionIssue.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          ),
        ),
      );
  @override
  Map<String, Object?> toJson() => {
    'context': context.toJson(),
    'as_of': asOf,
    'status': status,
    'reason': reason,
    'catalog_complete': catalogComplete,
    'programs': programs.map((v) => v.toJson()).toList(),
    'issues': issues.map((v) => v.toJson()).toList(),
  };
}

class CertificateRegistryProviderCreate implements OfficialPayload {
  const CertificateRegistryProviderCreate({
    required this.code,
    required this.name,
    required this.officialUrl,
  });
  final String code;
  final String name;
  final String officialUrl;
  factory CertificateRegistryProviderCreate.fromJson(
    Map<String, dynamic> value,
  ) => CertificateRegistryProviderCreate(
    code: value['code'] as String,
    name: value['name'] as String,
    officialUrl: value['official_url'] as String,
  );
  @override
  Map<String, Object?> toJson() => {
    'code': code,
    'name': name,
    'official_url': officialUrl,
  };
}

class CertificateRegistryCertificateCreate implements OfficialPayload {
  const CertificateRegistryCertificateCreate({
    required this.code,
    required this.name,
    required this.officialUrl,
    required this.providerId,
  });
  final String code;
  final String name;
  final String officialUrl;
  final String providerId;
  factory CertificateRegistryCertificateCreate.fromJson(
    Map<String, dynamic> value,
  ) => CertificateRegistryCertificateCreate(
    code: value['code'] as String,
    name: value['name'] as String,
    officialUrl: value['official_url'] as String,
    providerId: value['provider_id'] as String,
  );
  @override
  Map<String, Object?> toJson() => {
    'code': code,
    'name': name,
    'official_url': officialUrl,
    'provider_id': providerId,
  };
}

class CertificateRegistryRegistryUpdate implements OfficialPayload {
  const CertificateRegistryRegistryUpdate({
    required this.expectedVersion,
    required this.name,
    required this.officialUrl,
  });
  final int expectedVersion;
  final String name;
  final String officialUrl;
  factory CertificateRegistryRegistryUpdate.fromJson(
    Map<String, dynamic> value,
  ) => CertificateRegistryRegistryUpdate(
    expectedVersion: value['expected_version'] as int,
    name: value['name'] as String,
    officialUrl: value['official_url'] as String,
  );
  @override
  Map<String, Object?> toJson() => {
    'expected_version': expectedVersion,
    'name': name,
    'official_url': officialUrl,
  };
}

class CertificateRegistryRegistryVersion implements OfficialPayload {
  const CertificateRegistryRegistryVersion({required this.expectedVersion});
  final int expectedVersion;
  factory CertificateRegistryRegistryVersion.fromJson(
    Map<String, dynamic> value,
  ) => CertificateRegistryRegistryVersion(
    expectedVersion: value['expected_version'] as int,
  );
  @override
  Map<String, Object?> toJson() => {'expected_version': expectedVersion};
}

class CertificateRegistryProviderView implements OfficialPayload {
  const CertificateRegistryProviderView({
    required this.id,
    required this.code,
    required this.name,
    required this.officialUrl,
    required this.version,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String code;
  final String name;
  final String officialUrl;
  final int version;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  factory CertificateRegistryProviderView.fromJson(
    Map<String, dynamic> value,
  ) => CertificateRegistryProviderView(
    id: value['id'] as String,
    code: value['code'] as String,
    name: value['name'] as String,
    officialUrl: value['official_url'] as String,
    version: value['version'] as int,
    status: _choice(value['status'], ["active", "inactive"]),
    createdAt: DateTime.parse(value['created_at'] as String),
    updatedAt: DateTime.parse(value['updated_at'] as String),
  );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'official_url': officialUrl,
    'version': version,
    'status': status,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}

class CertificateRegistryCertificateView implements OfficialPayload {
  const CertificateRegistryCertificateView({
    required this.id,
    required this.code,
    required this.name,
    required this.officialUrl,
    required this.version,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.providerId,
  });
  final String id;
  final String code;
  final String name;
  final String officialUrl;
  final int version;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String providerId;
  factory CertificateRegistryCertificateView.fromJson(
    Map<String, dynamic> value,
  ) => CertificateRegistryCertificateView(
    id: value['id'] as String,
    code: value['code'] as String,
    name: value['name'] as String,
    officialUrl: value['official_url'] as String,
    version: value['version'] as int,
    status: _choice(value['status'], ["active", "inactive"]),
    createdAt: DateTime.parse(value['created_at'] as String),
    updatedAt: DateTime.parse(value['updated_at'] as String),
    providerId: value['provider_id'] as String,
  );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'official_url': officialUrl,
    'version': version,
    'status': status,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'provider_id': providerId,
  };
}

class CertificateRegistryProviderList implements OfficialPayload {
  const CertificateRegistryProviderList({required this.items, this.nextCursor});
  final List<CertificateRegistryProviderView> items;
  final String? nextCursor;
  factory CertificateRegistryProviderList.fromJson(
    Map<String, dynamic> value,
  ) => CertificateRegistryProviderList(
    items: List.unmodifiable(
      (value['items'] as List).map(
        (v) => CertificateRegistryProviderView.fromJson(
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

class CertificateRegistryCertificateList implements OfficialPayload {
  const CertificateRegistryCertificateList({
    required this.items,
    this.nextCursor,
  });
  final List<CertificateRegistryCertificateView> items;
  final String? nextCursor;
  factory CertificateRegistryCertificateList.fromJson(
    Map<String, dynamic> value,
  ) => CertificateRegistryCertificateList(
    items: List.unmodifiable(
      (value['items'] as List).map(
        (v) => CertificateRegistryCertificateView.fromJson(
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

class CertificateRegistryRegistryReference implements OfficialPayload {
  const CertificateRegistryRegistryReference({
    required this.id,
    required this.kind,
    required this.name,
  });
  final String id;
  final String kind;
  final String name;
  factory CertificateRegistryRegistryReference.fromJson(
    Map<String, dynamic> value,
  ) => CertificateRegistryRegistryReference(
    id: value['id'] as String,
    kind: _choice(value['kind'], ["rule_program", "protected_reference"]),
    name: value['name'] as String,
  );
  @override
  Map<String, Object?> toJson() => {'id': id, 'kind': kind, 'name': name};
}

class CertificateRegistryRegistryReferences implements OfficialPayload {
  const CertificateRegistryRegistryReferences({required this.items});
  final List<CertificateRegistryRegistryReference> items;
  factory CertificateRegistryRegistryReferences.fromJson(
    Map<String, dynamic> value,
  ) => CertificateRegistryRegistryReferences(
    items: List.unmodifiable(
      (value['items'] as List).map(
        (v) => CertificateRegistryRegistryReference.fromJson(
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
