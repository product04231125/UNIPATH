import '../auth/auth_api.dart';

/// Explicit personal criteria; this adapter never interprets free-form notes,
/// uploads local records, or requests an official graduation decision.
sealed class PersonalCondition {
  const PersonalCondition();
  Map<String, Object?> toJson();

  factory PersonalCondition.fromJson(Map<String, dynamic> value) {
    switch (value['kind']) {
      case 'minimum_credits':
        return PersonalCreditCondition(
          minimum: _amount(value['minimum'])!,
          category: value['category'] as String?,
          courseRecordIds: (value['course_record_ids'] as List?)
              ?.cast<String>(),
        );
      case 'required_courses':
        return PersonalCourseCondition(
          courses: _objects(value['courses'])
              .map(PersonalRequiredCourse.fromJson)
              .toList(),
          grades: _objects(value['grades'] ?? [])
              .map(PersonalGradeObservation.fromJson)
              .toList(),
        );
      case 'minimum_volunteer_hours':
        return PersonalVolunteerCondition(
          minimum: _amount(value['minimum'])!,
          activityIds: (value['activity_ids'] as List).cast<String>(),
        );
      case 'any_certificate':
        return PersonalCertificateCondition(
          certificates: _objects(value['certificates'])
              .map(PersonalCertificateObservation.fromJson)
              .toList(),
        );
      case 'thesis':
        return PersonalThesisCondition(
          thesisType: value['thesis_type'] as String,
          requiresApproval: value['requires_approval'] as bool? ?? true,
          acceptedGrades: (value['accepted_grades'] as List? ?? [])
              .cast<String>(),
          records: _objects(value['records'])
              .map(PersonalThesisObservation.fromJson)
              .toList(),
        );
      default:
        throw const FormatException(
          'Unsupported personal calculation condition',
        );
    }
  }
}

List<Map<String, dynamic>> _objects(Object? value) => (value as List)
    .map((item) => Map<String, dynamic>.from(item as Map))
    .toList();

String? _amount(Object? value) {
  if (value == null) return null;
  if (value is String || value is num) return value.toString();
  throw const FormatException('Expected a decimal wire value');
}

class PersonalCreditCondition extends PersonalCondition {
  const PersonalCreditCondition({
    required this.minimum,
    this.category,
    this.courseRecordIds,
  });
  final String minimum;
  final String? category;
  final List<String>? courseRecordIds;
  @override
  Map<String, Object?> toJson() => {
    'kind': 'minimum_credits',
    'minimum': minimum,
    'category': category,
    'course_record_ids': courseRecordIds,
  };
}

class PersonalRequiredCourse {
  const PersonalRequiredCourse({
    required this.curriculumCourseId,
    this.minimumCredits,
    this.minimumGradePoints,
    this.comparisonGradeScale,
  });
  final String curriculumCourseId;
  final String? minimumCredits, minimumGradePoints, comparisonGradeScale;
  factory PersonalRequiredCourse.fromJson(Map<String, dynamic> value) =>
      PersonalRequiredCourse(
        curriculumCourseId: value['curriculum_course_id'] as String,
        minimumCredits: _amount(value['minimum_credits']),
        minimumGradePoints: _amount(value['minimum_grade_points']),
        comparisonGradeScale: value['comparison_grade_scale'] as String?,
      );
  Map<String, Object?> toJson() => {
    'curriculum_course_id': curriculumCourseId,
    'minimum_credits': minimumCredits,
    'minimum_grade_points': minimumGradePoints,
    'comparison_grade_scale': comparisonGradeScale,
  };
}

class PersonalGradeObservation {
  const PersonalGradeObservation({
    required this.courseRecordId,
    required this.points,
    required this.scale,
  });
  final String courseRecordId, points, scale;
  factory PersonalGradeObservation.fromJson(Map<String, dynamic> value) =>
      PersonalGradeObservation(
        courseRecordId: value['course_record_id'] as String,
        points: _amount(value['points'])!,
        scale: value['scale'] as String,
      );
  Map<String, Object?> toJson() => {
    'course_record_id': courseRecordId,
    'points': points,
    'scale': scale,
  };
}

class PersonalCourseCondition extends PersonalCondition {
  const PersonalCourseCondition({
    required this.courses,
    this.grades = const [],
  });
  final List<PersonalRequiredCourse> courses;
  final List<PersonalGradeObservation> grades;
  @override
  Map<String, Object?> toJson() => {
    'kind': 'required_courses',
    'courses': courses.map((item) => item.toJson()).toList(),
    'grades': grades.map((item) => item.toJson()).toList(),
  };
}

class PersonalVolunteerCondition extends PersonalCondition {
  const PersonalVolunteerCondition({
    required this.minimum,
    required this.activityIds,
  });
  final String minimum;
  final List<String> activityIds;
  @override
  Map<String, Object?> toJson() => {
    'kind': 'minimum_volunteer_hours',
    'minimum': minimum,
    'activity_ids': activityIds,
  };
}

class PersonalCertificateObservation {
  const PersonalCertificateObservation({
    required this.credentialId,
    this.possession = 'unknown',
    this.validityKnown = false,
  });
  final String credentialId, possession;
  final bool validityKnown;
  factory PersonalCertificateObservation.fromJson(Map<String, dynamic> value) =>
      PersonalCertificateObservation(
        credentialId: value['credential_id'] as String,
        possession: value['possession'] as String? ?? 'unknown',
        validityKnown: value['validity_known'] as bool? ?? false,
      );
  Map<String, Object?> toJson() => {
    'credential_id': credentialId,
    'possession': possession,
    'validity_known': validityKnown,
  };
}

class PersonalCertificateCondition extends PersonalCondition {
  const PersonalCertificateCondition({required this.certificates});
  final List<PersonalCertificateObservation> certificates;
  @override
  Map<String, Object?> toJson() => {
    'kind': 'any_certificate',
    'certificates': certificates.map((item) => item.toJson()).toList(),
  };
}

class PersonalThesisObservation {
  const PersonalThesisObservation({
    required this.achievementId,
    this.completion = 'unknown',
    this.approval = 'needs_review',
  });
  final String achievementId, completion, approval;
  factory PersonalThesisObservation.fromJson(Map<String, dynamic> value) =>
      PersonalThesisObservation(
        achievementId: value['achievement_id'] as String,
        completion: value['completion'] as String? ?? 'unknown',
        approval: value['approval'] as String? ?? 'needs_review',
      );
  Map<String, Object?> toJson() => {
    'achievement_id': achievementId,
    'completion': completion,
    'approval': approval,
  };
}

class PersonalThesisCondition extends PersonalCondition {
  const PersonalThesisCondition({
    required this.thesisType,
    required this.records,
    this.requiresApproval = true,
    this.acceptedGrades = const [],
  });
  final String thesisType;
  final bool requiresApproval;
  final List<String> acceptedGrades;
  final List<PersonalThesisObservation> records;
  @override
  Map<String, Object?> toJson() => {
    'kind': 'thesis',
    'thesis_type': thesisType,
    'requires_approval': requiresApproval,
    'accepted_grades': acceptedGrades,
    'records': records.map((item) => item.toJson()).toList(),
  };
}

class PersonalRuleCalculation {
  const PersonalRuleCalculation({
    required this.ruleId,
    required this.expectedVersion,
    required this.condition,
  });
  final String ruleId;
  final int expectedVersion;
  final PersonalCondition condition;
  Map<String, Object?> toJson() => {
    'rule_id': ruleId,
    'expected_version': expectedVersion,
    'condition': condition.toJson(),
  };
}

class PersonalSourceVersion {
  const PersonalSourceVersion({
    required this.kind,
    required this.recordId,
    required this.version,
  });
  final String kind, recordId;
  final int version;
  factory PersonalSourceVersion.fromJson(Map<String, dynamic> value) =>
      PersonalSourceVersion(
        kind: value['kind'] as String,
        recordId: value['record_id'] as String,
        version: value['version'] as int,
      );
  Map<String, Object?> toJson() => {
    'kind': kind,
    'record_id': recordId,
    'version': version,
  };
}

class PersonalEvaluationRequest {
  const PersonalEvaluationRequest({
    required this.curriculumId,
    required this.expectedCurriculumVersion,
    this.clientId,
    this.asOf,
    this.calculations = const [],
    this.expectedSourceVersions = const [],
  });
  final String curriculumId;
  final int expectedCurriculumVersion;
  final String? clientId, asOf;
  final List<PersonalRuleCalculation> calculations;
  final List<PersonalSourceVersion> expectedSourceVersions;
  Map<String, Object?> toJson() => {
    'curriculum_id': curriculumId,
    'expected_curriculum_version': expectedCurriculumVersion,
    'client_id': clientId,
    'as_of': asOf,
    'calculations': calculations.map((item) => item.toJson()).toList(),
    'expected_source_versions': expectedSourceVersions
        .map((item) => item.toJson())
        .toList(),
  };
}

enum PersonalEvaluationStatus {
  satisfied,
  notSatisfied,
  needsReview,
  notApplicable,
}

PersonalEvaluationStatus _status(Object? value) => switch (value) {
  'satisfied' => PersonalEvaluationStatus.satisfied,
  'not_satisfied' => PersonalEvaluationStatus.notSatisfied,
  'needs_review' => PersonalEvaluationStatus.needsReview,
  'not_applicable' => PersonalEvaluationStatus.notApplicable,
  _ => throw const FormatException('Unsupported personal calculation status'),
};

class PersonalEvaluationSummary {
  PersonalEvaluationSummary.fromJson(Map<String, dynamic> value)
    : id = value['id'] as String,
      ownerId = value['owner_id'] as String,
      clientId = value['client_id'] as String?,
      version = value['version'] as int,
      curriculumId = value['curriculum_id'] as String,
      curriculumVersion = value['curriculum_version'] as int,
      curriculumTitle = value['curriculum_title'] as String,
      evaluatedOn = value['evaluated_on'] as String,
      createdAt = DateTime.parse(value['created_at'] as String),
      status = _status(value['status']),
      reason = value['reason'] as String {
    if (value['official'] != false ||
        value['label'] != personalLabel ||
        version != 1) {
      throw const FormatException('Expected an immutable personal calculation');
    }
  }
  static const personalLabel = '개인 기준 계산 · 학교 공식 판정 아님';
  String get label => personalLabel;
  final String id, ownerId, curriculumId, curriculumTitle, evaluatedOn, reason;
  final String? clientId;
  final int version, curriculumVersion;
  final DateTime createdAt;
  final PersonalEvaluationStatus status;
}

class PersonalEvaluationItem {
  PersonalEvaluationItem.fromJson(Map<String, dynamic> value)
    : ruleId = value['rule_id'] as String,
      ruleVersion = value['rule_version'] as int,
      title = value['title'] as String,
      status = _status(value['status']),
      reason = value['reason'] as String,
      current = _amount(value['current']),
      requiredValue = _amount(value['required']),
      deficit = _amount(value['deficit']),
      missingCourseIds = List.unmodifiable(
        (value['missing_course_ids'] as List? ?? []).cast<String>(),
      ),
      uncertainCourseIds = List.unmodifiable(
        (value['uncertain_course_ids'] as List? ?? []).cast<String>(),
      ),
      evidenceRecordIds = List.unmodifiable(
        (value['evidence_record_ids'] as List? ?? []).cast<String>(),
      ),
      condition = value['condition'] == null
          ? null
          : PersonalCondition.fromJson(
              Map<String, dynamic>.from(value['condition'] as Map),
            );
  final String ruleId, title, reason;
  final int ruleVersion;
  final PersonalEvaluationStatus status;
  final String? current, requiredValue, deficit;
  final List<String> missingCourseIds, uncertainCourseIds, evidenceRecordIds;
  final PersonalCondition? condition;
}

class PersonalEvaluation extends PersonalEvaluationSummary {
  PersonalEvaluation.fromJson(super.value)
    : results = List.unmodifiable(
        _objects(value['results']).map(PersonalEvaluationItem.fromJson),
      ),
      sourceVersions = List.unmodifiable(
        _objects(value['source_versions']).map(PersonalSourceVersion.fromJson),
      ),
      super.fromJson();
  final List<PersonalEvaluationItem> results;
  final List<PersonalSourceVersion> sourceVersions;
}

class PersonalEvaluationPage {
  PersonalEvaluationPage(List<PersonalEvaluationSummary> items, this.nextCursor)
    : items = List.unmodifiable(items);
  final List<PersonalEvaluationSummary> items;
  final String? nextCursor;
}

class PersonalEvaluationApi {
  const PersonalEvaluationApi(this.api, {required this.ownerId});
  final ApiGateway api;
  final String ownerId;
  PersonalEvaluation _detail(Map<String, dynamic> value) {
    final result = PersonalEvaluation.fromJson(value);
    _check(result);
    return result;
  }

  void _check(PersonalEvaluationSummary value) {
    if (value.ownerId != ownerId) {
      throw const FormatException('Unexpected calculation owner');
    }
  }

  Future<PersonalEvaluation> create(PersonalEvaluationRequest request) async =>
      _detail(
        (await api.request(
          'POST',
          'me/personal-evaluations',
          request.toJson(),
        ))!,
      );
  Future<PersonalEvaluation> get(String id) async =>
      _detail((await api.request('GET', 'me/personal-evaluations/$id'))!);
  Future<PersonalEvaluationPage> list({
    String? curriculumId,
    String? cursor,
    int limit = 100,
  }) async {
    final query = Uri(
      queryParameters: {
        'limit': '$limit',
        'curriculum_id': ?curriculumId,
        'cursor': ?cursor,
      },
    ).query;
    final value = (await api.request('GET', 'me/personal-evaluations?$query'))!;
    final rows = _objects(value['items'])
        .map(PersonalEvaluationSummary.fromJson)
        .toList();
    for (final row in rows) {
      _check(row);
    }
    return PersonalEvaluationPage(rows, value['next_cursor'] as String?);
  }

  Future<void> remove(String id, {required int expectedVersion}) async {
    await api.request(
      'DELETE',
      'me/personal-evaluations/$id?expected_version=$expectedVersion',
    );
  }
}
