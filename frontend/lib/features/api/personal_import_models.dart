// GENERATED: scripts/export_personal_import_contracts.py.
// Local reference UUIDs are explicit client IDs. No storage or upload effects.
abstract interface class PersonalImportPayload {
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

class PersonalImportEvent implements PersonalImportPayload {
  const PersonalImportEvent({
    required this.title,
    this.detail = "",
    required this.clientId,
    required this.startsAt,
    required this.endsAt,
    required this.timeZone,
    required this.category,
  });
  final String title;
  final String detail;
  final String clientId;
  final DateTime startsAt;
  final DateTime endsAt;
  final String timeZone;
  final String category;
  factory PersonalImportEvent.fromJson(Map<String, dynamic> value) =>
      PersonalImportEvent(
        title: value['title'] as String,
        detail: value['detail'] == null ? "" : value['detail'] as String,
        clientId: value['client_id'] as String,
        startsAt: DateTime.parse(value['starts_at'] as String),
        endsAt: DateTime.parse(value['ends_at'] as String),
        timeZone: value['time_zone'] as String,
        category: _choice(value['category'], [
          "academic",
          "personal",
          "activity",
          "deadline",
        ]),
      );
  @override
  Map<String, Object?> toJson() => {
    'title': title,
    'detail': detail,
    'client_id': clientId,
    'starts_at': startsAt.toUtc().toIso8601String(),
    'ends_at': endsAt.toUtc().toIso8601String(),
    'time_zone': timeZone,
    'category': category,
  };
}

class PersonalImportCourseRecord implements PersonalImportPayload {
  const PersonalImportCourseRecord({
    required this.title,
    this.detail = "",
    required this.clientId,
    required this.term,
    required this.category,
    required this.credits,
    this.section = "",
    this.courseCode = "",
    this.grade = "",
    this.completion = "planned",
  });
  final String title;
  final String detail;
  final String clientId;
  final String term;
  final String category;
  final String credits;
  final String section;
  final String courseCode;
  final String grade;
  final String completion;
  factory PersonalImportCourseRecord.fromJson(Map<String, dynamic> value) =>
      PersonalImportCourseRecord(
        title: value['title'] as String,
        detail: value['detail'] == null ? "" : value['detail'] as String,
        clientId: value['client_id'] as String,
        term: value['term'] as String,
        category: value['category'] as String,
        credits: _decimal(value['credits']),
        section: value['section'] == null ? "" : value['section'] as String,
        courseCode: value['course_code'] == null
            ? ""
            : value['course_code'] as String,
        grade: value['grade'] == null ? "" : value['grade'] as String,
        completion: value['completion'] == null
            ? "planned"
            : _choice(value['completion'], [
                "planned",
                "in_progress",
                "recorded",
              ]),
      );
  @override
  Map<String, Object?> toJson() => {
    'title': title,
    'detail': detail,
    'client_id': clientId,
    'term': term,
    'category': category,
    'credits': credits,
    'section': section,
    'course_code': courseCode,
    'grade': grade,
    'completion': completion,
  };
}

class PersonalImportActivityRecord implements PersonalImportPayload {
  const PersonalImportActivityRecord({
    required this.title,
    this.detail = "",
    required this.clientId,
    this.startedOn,
    this.endedOn,
    this.organization = "",
    this.role = "",
    this.reportedHours,
    this.approvedHours,
    this.approval,
    this.observedOn,
  });
  final String title;
  final String detail;
  final String clientId;
  final String? startedOn;
  final String? endedOn;
  final String organization;
  final String role;
  final String? reportedHours;
  final String? approvedHours;
  final String? approval;
  final String? observedOn;
  factory PersonalImportActivityRecord.fromJson(Map<String, dynamic> value) =>
      PersonalImportActivityRecord(
        title: value['title'] as String,
        detail: value['detail'] == null ? "" : value['detail'] as String,
        clientId: value['client_id'] as String,
        startedOn: value['started_on'] == null
            ? null
            : value['started_on'] as String,
        endedOn: value['ended_on'] == null ? null : value['ended_on'] as String,
        organization: value['organization'] == null
            ? ""
            : value['organization'] as String,
        role: value['role'] == null ? "" : value['role'] as String,
        reportedHours: value['reported_hours'] == null
            ? null
            : _decimal(value['reported_hours']),
        approvedHours: value['approved_hours'] == null
            ? null
            : _decimal(value['approved_hours']),
        approval: value['approval'] == null
            ? null
            : _choice(value['approval'], [
                "pending",
                "approved",
                "rejected",
                "needs_review",
              ]),
        observedOn: value['observed_on'] == null
            ? null
            : value['observed_on'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'title': title,
    'detail': detail,
    'client_id': clientId,
    'started_on': startedOn,
    'ended_on': endedOn,
    'organization': organization,
    'role': role,
    'reported_hours': reportedHours,
    'approved_hours': approvedHours,
    'approval': approval,
    'observed_on': observedOn,
  };
}

class PersonalImportExperienceRecord implements PersonalImportPayload {
  const PersonalImportExperienceRecord({
    required this.title,
    this.detail = "",
    required this.clientId,
    this.startedOn,
    this.endedOn,
    required this.experienceType,
    this.organization = "",
    this.role = "",
    this.result = "",
    this.statusLabel = "",
  });
  final String title;
  final String detail;
  final String clientId;
  final String? startedOn;
  final String? endedOn;
  final String experienceType;
  final String organization;
  final String role;
  final String result;
  final String statusLabel;
  factory PersonalImportExperienceRecord.fromJson(Map<String, dynamic> value) =>
      PersonalImportExperienceRecord(
        title: value['title'] as String,
        detail: value['detail'] == null ? "" : value['detail'] as String,
        clientId: value['client_id'] as String,
        startedOn: value['started_on'] == null
            ? null
            : value['started_on'] as String,
        endedOn: value['ended_on'] == null ? null : value['ended_on'] as String,
        experienceType: value['experience_type'] as String,
        organization: value['organization'] == null
            ? ""
            : value['organization'] as String,
        role: value['role'] == null ? "" : value['role'] as String,
        result: value['result'] == null ? "" : value['result'] as String,
        statusLabel: value['status_label'] == null
            ? ""
            : value['status_label'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'title': title,
    'detail': detail,
    'client_id': clientId,
    'started_on': startedOn,
    'ended_on': endedOn,
    'experience_type': experienceType,
    'organization': organization,
    'role': role,
    'result': result,
    'status_label': statusLabel,
  };
}

class PersonalImportCredentialRecord implements PersonalImportPayload {
  const PersonalImportCredentialRecord({
    required this.title,
    this.detail = "",
    required this.clientId,
    this.provider = "",
    this.level = "",
    this.earnedOn,
    this.expiresOn,
    this.statusLabel = "",
    this.evidenceUrl = "",
  });
  final String title;
  final String detail;
  final String clientId;
  final String provider;
  final String level;
  final String? earnedOn;
  final String? expiresOn;
  final String statusLabel;
  final String evidenceUrl;
  factory PersonalImportCredentialRecord.fromJson(Map<String, dynamic> value) =>
      PersonalImportCredentialRecord(
        title: value['title'] as String,
        detail: value['detail'] == null ? "" : value['detail'] as String,
        clientId: value['client_id'] as String,
        provider: value['provider'] == null ? "" : value['provider'] as String,
        level: value['level'] == null ? "" : value['level'] as String,
        earnedOn: value['earned_on'] == null
            ? null
            : value['earned_on'] as String,
        expiresOn: value['expires_on'] == null
            ? null
            : value['expires_on'] as String,
        statusLabel: value['status_label'] == null
            ? ""
            : value['status_label'] as String,
        evidenceUrl: value['evidence_url'] == null
            ? ""
            : value['evidence_url'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'title': title,
    'detail': detail,
    'client_id': clientId,
    'provider': provider,
    'level': level,
    'earned_on': earnedOn,
    'expires_on': expiresOn,
    'status_label': statusLabel,
    'evidence_url': evidenceUrl,
  };
}

class PersonalImportAchievementRecord implements PersonalImportPayload {
  const PersonalImportAchievementRecord({
    required this.title,
    this.detail = "",
    required this.clientId,
    this.startedOn,
    this.endedOn,
    required this.achievementType,
    this.thesisType = "",
    this.thesisStatusLabel = "",
    this.thesisGrade = "",
    this.thesisApprovedOn,
    required this.role,
    required this.result,
    this.evidenceUrl = "",
  });
  final String title;
  final String detail;
  final String clientId;
  final String? startedOn;
  final String? endedOn;
  final String achievementType;
  final String thesisType;
  final String thesisStatusLabel;
  final String thesisGrade;
  final String? thesisApprovedOn;
  final String role;
  final String result;
  final String evidenceUrl;
  factory PersonalImportAchievementRecord.fromJson(
    Map<String, dynamic> value,
  ) => PersonalImportAchievementRecord(
    title: value['title'] as String,
    detail: value['detail'] == null ? "" : value['detail'] as String,
    clientId: value['client_id'] as String,
    startedOn: value['started_on'] == null
        ? null
        : value['started_on'] as String,
    endedOn: value['ended_on'] == null ? null : value['ended_on'] as String,
    achievementType: value['achievement_type'] as String,
    thesisType: value['thesis_type'] == null
        ? ""
        : value['thesis_type'] as String,
    thesisStatusLabel: value['thesis_status_label'] == null
        ? ""
        : value['thesis_status_label'] as String,
    thesisGrade: value['thesis_grade'] == null
        ? ""
        : value['thesis_grade'] as String,
    thesisApprovedOn: value['thesis_approved_on'] == null
        ? null
        : value['thesis_approved_on'] as String,
    role: value['role'] as String,
    result: value['result'] as String,
    evidenceUrl: value['evidence_url'] == null
        ? ""
        : value['evidence_url'] as String,
  );
  @override
  Map<String, Object?> toJson() => {
    'title': title,
    'detail': detail,
    'client_id': clientId,
    'started_on': startedOn,
    'ended_on': endedOn,
    'achievement_type': achievementType,
    'thesis_type': thesisType,
    'thesis_status_label': thesisStatusLabel,
    'thesis_grade': thesisGrade,
    'thesis_approved_on': thesisApprovedOn,
    'role': role,
    'result': result,
    'evidence_url': evidenceUrl,
  };
}

class PersonalImportPersonalCurriculum implements PersonalImportPayload {
  const PersonalImportPersonalCurriculum({
    required this.title,
    this.detail = "",
    required this.clientId,
    required this.school,
    required this.department,
    required this.admissionYear,
    required this.curriculumYear,
    this.evidenceUrl = "",
  });
  final String title;
  final String detail;
  final String clientId;
  final String school;
  final String department;
  final int admissionYear;
  final int curriculumYear;
  final String evidenceUrl;
  factory PersonalImportPersonalCurriculum.fromJson(
    Map<String, dynamic> value,
  ) => PersonalImportPersonalCurriculum(
    title: value['title'] as String,
    detail: value['detail'] == null ? "" : value['detail'] as String,
    clientId: value['client_id'] as String,
    school: value['school'] as String,
    department: value['department'] as String,
    admissionYear: value['admission_year'] as int,
    curriculumYear: value['curriculum_year'] as int,
    evidenceUrl: value['evidence_url'] == null
        ? ""
        : value['evidence_url'] as String,
  );
  @override
  Map<String, Object?> toJson() => {
    'title': title,
    'detail': detail,
    'client_id': clientId,
    'school': school,
    'department': department,
    'admission_year': admissionYear,
    'curriculum_year': curriculumYear,
    'evidence_url': evidenceUrl,
  };
}

class PersonalImportRecordReference implements PersonalImportPayload {
  const PersonalImportRecordReference({
    required this.kind,
    required this.clientId,
  });
  final String kind;
  final String clientId;
  factory PersonalImportRecordReference.fromJson(Map<String, dynamic> value) =>
      PersonalImportRecordReference(
        kind: _choice(value['kind'], [
          "course",
          "activity",
          "experience",
          "credential",
          "achievement",
        ]),
        clientId: value['client_id'] as String,
      );
  @override
  Map<String, Object?> toJson() => {'kind': kind, 'client_id': clientId};
}

class PersonalImportCurriculumCourse implements PersonalImportPayload {
  const PersonalImportCurriculumCourse({
    required this.title,
    this.detail = "",
    required this.clientId,
    required this.curriculumClientId,
    this.courseRecordClientId,
    this.courseCode = "",
    required this.category,
    required this.credits,
    required this.required,
  });
  final String title;
  final String detail;
  final String clientId;
  final String curriculumClientId;
  final String? courseRecordClientId;
  final String courseCode;
  final String category;
  final String credits;
  final bool required;
  factory PersonalImportCurriculumCourse.fromJson(Map<String, dynamic> value) =>
      PersonalImportCurriculumCourse(
        title: value['title'] as String,
        detail: value['detail'] == null ? "" : value['detail'] as String,
        clientId: value['client_id'] as String,
        curriculumClientId: value['curriculum_client_id'] as String,
        courseRecordClientId: value['course_record_client_id'] == null
            ? null
            : value['course_record_client_id'] as String,
        courseCode: value['course_code'] == null
            ? ""
            : value['course_code'] as String,
        category: value['category'] as String,
        credits: _decimal(value['credits']),
        required: value['required'] as bool,
      );
  @override
  Map<String, Object?> toJson() => {
    'title': title,
    'detail': detail,
    'client_id': clientId,
    'curriculum_client_id': curriculumClientId,
    'course_record_client_id': courseRecordClientId,
    'course_code': courseCode,
    'category': category,
    'credits': credits,
    'required': required,
  };
}

class PersonalImportGraduationRule implements PersonalImportPayload {
  const PersonalImportGraduationRule({
    required this.title,
    this.detail = "",
    required this.clientId,
    required this.curriculumClientId,
    this.curriculumCourseClientId,
    this.ruleCode = "",
    required this.ruleType,
    required this.scope,
    this.requiredValue,
    this.currentValue,
    this.unit = "",
    required this.condition,
    this.effectiveFrom,
    this.effectiveTo,
    this.evidenceUrl = "",
    this.relatedRecord,
  });
  final String title;
  final String detail;
  final String clientId;
  final String curriculumClientId;
  final String? curriculumCourseClientId;
  final String ruleCode;
  final String ruleType;
  final String scope;
  final String? requiredValue;
  final String? currentValue;
  final String unit;
  final String condition;
  final String? effectiveFrom;
  final String? effectiveTo;
  final String evidenceUrl;
  final PersonalImportRecordReference? relatedRecord;
  factory PersonalImportGraduationRule.fromJson(
    Map<String, dynamic> value,
  ) => PersonalImportGraduationRule(
    title: value['title'] as String,
    detail: value['detail'] == null ? "" : value['detail'] as String,
    clientId: value['client_id'] as String,
    curriculumClientId: value['curriculum_client_id'] as String,
    curriculumCourseClientId: value['curriculum_course_client_id'] == null
        ? null
        : value['curriculum_course_client_id'] as String,
    ruleCode: value['rule_code'] == null ? "" : value['rule_code'] as String,
    ruleType: value['rule_type'] as String,
    scope: _choice(value['scope'], ["institution", "department", "curriculum"]),
    requiredValue: value['required_value'] == null
        ? null
        : _decimal(value['required_value']),
    currentValue: value['current_value'] == null
        ? null
        : _decimal(value['current_value']),
    unit: value['unit'] == null ? "" : value['unit'] as String,
    condition: value['condition'] as String,
    effectiveFrom: value['effective_from'] == null
        ? null
        : value['effective_from'] as String,
    effectiveTo: value['effective_to'] == null
        ? null
        : value['effective_to'] as String,
    evidenceUrl: value['evidence_url'] == null
        ? ""
        : value['evidence_url'] as String,
    relatedRecord: value['related_record'] == null
        ? null
        : PersonalImportRecordReference.fromJson(
            Map<String, dynamic>.from(value['related_record'] as Map),
          ),
  );
  @override
  Map<String, Object?> toJson() => {
    'title': title,
    'detail': detail,
    'client_id': clientId,
    'curriculum_client_id': curriculumClientId,
    'curriculum_course_client_id': curriculumCourseClientId,
    'rule_code': ruleCode,
    'rule_type': ruleType,
    'scope': scope,
    'required_value': requiredValue,
    'current_value': currentValue,
    'unit': unit,
    'condition': condition,
    'effective_from': effectiveFrom,
    'effective_to': effectiveTo,
    'evidence_url': evidenceUrl,
    'related_record': relatedRecord?.toJson(),
  };
}

class PersonalImportComposition implements PersonalImportPayload {
  const PersonalImportComposition({
    required this.title,
    this.detail = "",
    required this.clientId,
    this.audience = "private",
    this.reviewed = false,
    this.sources = const [],
  });
  final String title;
  final String detail;
  final String clientId;
  final String audience;
  final bool reviewed;
  final List<PersonalImportRecordReference> sources;
  factory PersonalImportComposition.fromJson(Map<String, dynamic> value) =>
      PersonalImportComposition(
        title: value['title'] as String,
        detail: value['detail'] == null ? "" : value['detail'] as String,
        clientId: value['client_id'] as String,
        audience: value['audience'] == null
            ? "private"
            : _choice(value['audience'], [
                "private",
                "application",
                "public_review",
              ]),
        reviewed: value['reviewed'] == null ? false : value['reviewed'] as bool,
        sources: value['sources'] == null
            ? const []
            : List.unmodifiable(
                (value['sources'] as List).map(
                  (v) => PersonalImportRecordReference.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              ),
      );
  @override
  Map<String, Object?> toJson() => {
    'title': title,
    'detail': detail,
    'client_id': clientId,
    'audience': audience,
    'reviewed': reviewed,
    'sources': sources.map((v) => v.toJson()).toList(),
  };
}

class PersonalImportApplicationDocument implements PersonalImportPayload {
  const PersonalImportApplicationDocument({
    required this.title,
    this.detail = "",
    required this.clientId,
    required this.target,
    required this.role,
    required this.documentType,
    this.body = "",
    this.sources = const [],
  });
  final String title;
  final String detail;
  final String clientId;
  final String target;
  final String role;
  final String documentType;
  final String body;
  final List<PersonalImportRecordReference> sources;
  factory PersonalImportApplicationDocument.fromJson(
    Map<String, dynamic> value,
  ) => PersonalImportApplicationDocument(
    title: value['title'] as String,
    detail: value['detail'] == null ? "" : value['detail'] as String,
    clientId: value['client_id'] as String,
    target: value['target'] as String,
    role: value['role'] as String,
    documentType: value['document_type'] as String,
    body: value['body'] == null ? "" : value['body'] as String,
    sources: value['sources'] == null
        ? const []
        : List.unmodifiable(
            (value['sources'] as List).map(
              (v) => PersonalImportRecordReference.fromJson(
                Map<String, dynamic>.from(v as Map),
              ),
            ),
          ),
  );
  @override
  Map<String, Object?> toJson() => {
    'title': title,
    'detail': detail,
    'client_id': clientId,
    'target': target,
    'role': role,
    'document_type': documentType,
    'body': body,
    'sources': sources.map((v) => v.toJson()).toList(),
  };
}

class PersonalImportProfile implements PersonalImportPayload {
  const PersonalImportProfile({
    this.school = "",
    this.department = "",
    this.admissionYear,
    this.track,
    this.academicYearOverride,
    this.weekStartsOn = "sunday",
    this.institutionId,
    this.departmentId,
    this.curriculumId,
  });
  final String school;
  final String department;
  final int? admissionYear;
  final String? track;
  final int? academicYearOverride;
  final String weekStartsOn;
  final String? institutionId;
  final String? departmentId;
  final String? curriculumId;
  factory PersonalImportProfile.fromJson(Map<String, dynamic> value) =>
      PersonalImportProfile(
        school: value['school'] == null ? "" : value['school'] as String,
        department: value['department'] == null
            ? ""
            : value['department'] as String,
        admissionYear: value['admission_year'] == null
            ? null
            : value['admission_year'] as int,
        track: value['track'] == null ? null : value['track'] as String,
        academicYearOverride: value['academic_year_override'] == null
            ? null
            : value['academic_year_override'] as int,
        weekStartsOn: value['week_starts_on'] == null
            ? "sunday"
            : _choice(value['week_starts_on'], [
                "sunday",
                "monday",
                "tuesday",
                "wednesday",
                "thursday",
                "friday",
                "saturday",
              ]),
        institutionId: value['institution_id'] == null
            ? null
            : value['institution_id'] as String,
        departmentId: value['department_id'] == null
            ? null
            : value['department_id'] as String,
        curriculumId: value['curriculum_id'] == null
            ? null
            : value['curriculum_id'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'school': school,
    'department': department,
    'admission_year': admissionYear,
    'track': track,
    'academic_year_override': academicYearOverride,
    'week_starts_on': weekStartsOn,
    'institution_id': institutionId,
    'department_id': departmentId,
    'curriculum_id': curriculumId,
  };
}

class PersonalImportRequest implements PersonalImportPayload {
  const PersonalImportRequest({
    required this.importId,
    required this.sourceOwnerId,
    required this.consentConfirmed,
    this.profile,
    this.events = const [],
    this.courseRecords = const [],
    this.activityRecords = const [],
    this.experienceRecords = const [],
    this.credentialRecords = const [],
    this.achievementRecords = const [],
    this.personalCurricula = const [],
    this.personalCurriculumCourses = const [],
    this.personalGraduationRules = const [],
    this.portfolioCompositions = const [],
    this.applicationDocuments = const [],
  });
  final String importId;
  final String sourceOwnerId;
  final bool consentConfirmed;
  final PersonalImportProfile? profile;
  final List<PersonalImportEvent> events;
  final List<PersonalImportCourseRecord> courseRecords;
  final List<PersonalImportActivityRecord> activityRecords;
  final List<PersonalImportExperienceRecord> experienceRecords;
  final List<PersonalImportCredentialRecord> credentialRecords;
  final List<PersonalImportAchievementRecord> achievementRecords;
  final List<PersonalImportPersonalCurriculum> personalCurricula;
  final List<PersonalImportCurriculumCourse> personalCurriculumCourses;
  final List<PersonalImportGraduationRule> personalGraduationRules;
  final List<PersonalImportComposition> portfolioCompositions;
  final List<PersonalImportApplicationDocument> applicationDocuments;
  factory PersonalImportRequest.fromJson(Map<String, dynamic> value) =>
      PersonalImportRequest(
        importId: value['import_id'] as String,
        sourceOwnerId: value['source_owner_id'] as String,
        consentConfirmed: value['consent_confirmed'] as bool,
        profile: value['profile'] == null
            ? null
            : PersonalImportProfile.fromJson(
                Map<String, dynamic>.from(value['profile'] as Map),
              ),
        events: value['events'] == null
            ? const []
            : List.unmodifiable(
                (value['events'] as List).map(
                  (v) => PersonalImportEvent.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              ),
        courseRecords: value['course_records'] == null
            ? const []
            : List.unmodifiable(
                (value['course_records'] as List).map(
                  (v) => PersonalImportCourseRecord.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              ),
        activityRecords: value['activity_records'] == null
            ? const []
            : List.unmodifiable(
                (value['activity_records'] as List).map(
                  (v) => PersonalImportActivityRecord.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              ),
        experienceRecords: value['experience_records'] == null
            ? const []
            : List.unmodifiable(
                (value['experience_records'] as List).map(
                  (v) => PersonalImportExperienceRecord.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              ),
        credentialRecords: value['credential_records'] == null
            ? const []
            : List.unmodifiable(
                (value['credential_records'] as List).map(
                  (v) => PersonalImportCredentialRecord.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              ),
        achievementRecords: value['achievement_records'] == null
            ? const []
            : List.unmodifiable(
                (value['achievement_records'] as List).map(
                  (v) => PersonalImportAchievementRecord.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              ),
        personalCurricula: value['personal_curricula'] == null
            ? const []
            : List.unmodifiable(
                (value['personal_curricula'] as List).map(
                  (v) => PersonalImportPersonalCurriculum.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              ),
        personalCurriculumCourses: value['personal_curriculum_courses'] == null
            ? const []
            : List.unmodifiable(
                (value['personal_curriculum_courses'] as List).map(
                  (v) => PersonalImportCurriculumCourse.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              ),
        personalGraduationRules: value['personal_graduation_rules'] == null
            ? const []
            : List.unmodifiable(
                (value['personal_graduation_rules'] as List).map(
                  (v) => PersonalImportGraduationRule.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              ),
        portfolioCompositions: value['portfolio_compositions'] == null
            ? const []
            : List.unmodifiable(
                (value['portfolio_compositions'] as List).map(
                  (v) => PersonalImportComposition.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              ),
        applicationDocuments: value['application_documents'] == null
            ? const []
            : List.unmodifiable(
                (value['application_documents'] as List).map(
                  (v) => PersonalImportApplicationDocument.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              ),
      );
  @override
  Map<String, Object?> toJson() => {
    'import_id': importId,
    'source_owner_id': sourceOwnerId,
    'consent_confirmed': consentConfirmed,
    'profile': profile?.toJson(),
    'events': events.map((v) => v.toJson()).toList(),
    'course_records': courseRecords.map((v) => v.toJson()).toList(),
    'activity_records': activityRecords.map((v) => v.toJson()).toList(),
    'experience_records': experienceRecords.map((v) => v.toJson()).toList(),
    'credential_records': credentialRecords.map((v) => v.toJson()).toList(),
    'achievement_records': achievementRecords.map((v) => v.toJson()).toList(),
    'personal_curricula': personalCurricula.map((v) => v.toJson()).toList(),
    'personal_curriculum_courses': personalCurriculumCourses
        .map((v) => v.toJson())
        .toList(),
    'personal_graduation_rules': personalGraduationRules
        .map((v) => v.toJson())
        .toList(),
    'portfolio_compositions': portfolioCompositions
        .map((v) => v.toJson())
        .toList(),
    'application_documents': applicationDocuments
        .map((v) => v.toJson())
        .toList(),
  };
}

class PersonalImportMapping implements PersonalImportPayload {
  const PersonalImportMapping({
    required this.resource,
    required this.clientId,
    required this.recordId,
    required this.versionAtImport,
    required this.outcome,
  });
  final String resource;
  final String clientId;
  final String recordId;
  final int versionAtImport;
  final String outcome;
  factory PersonalImportMapping.fromJson(Map<String, dynamic> value) =>
      PersonalImportMapping(
        resource: _choice(value['resource'], [
          "events",
          "course-records",
          "activity-records",
          "experience-records",
          "credential-records",
          "achievement-records",
          "personal-curricula",
          "personal-curriculum-courses",
          "personal-graduation-rules",
          "portfolio-compositions",
          "application-documents",
        ]),
        clientId: value['client_id'] as String,
        recordId: value['record_id'] as String,
        versionAtImport: value['version_at_import'] as int,
        outcome: _choice(value['outcome'], ["created", "reused"]),
      );
  @override
  Map<String, Object?> toJson() => {
    'resource': resource,
    'client_id': clientId,
    'record_id': recordId,
    'version_at_import': versionAtImport,
    'outcome': outcome,
  };
}

class PersonalImportReceipt implements PersonalImportPayload {
  const PersonalImportReceipt({
    required this.importId,
    required this.ownerId,
    required this.committedAt,
    required this.recordCount,
    required this.profileVersionAtImport,
    required this.mappings,
    required this.replayed,
    this.origin = "personal",
    this.official = false,
  });
  final String importId;
  final String ownerId;
  final DateTime committedAt;
  final int recordCount;
  final int? profileVersionAtImport;
  final List<PersonalImportMapping> mappings;
  final bool replayed;
  final String origin;
  final bool official;
  factory PersonalImportReceipt.fromJson(Map<String, dynamic> value) =>
      PersonalImportReceipt(
        importId: value['import_id'] as String,
        ownerId: value['owner_id'] as String,
        committedAt: DateTime.parse(value['committed_at'] as String),
        recordCount: value['record_count'] as int,
        profileVersionAtImport: value['profile_version_at_import'] == null
            ? null
            : value['profile_version_at_import'] as int,
        mappings: List.unmodifiable(
          (value['mappings'] as List).map(
            (v) => PersonalImportMapping.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          ),
        ),
        replayed: value['replayed'] as bool,
        origin: value['origin'] == null
            ? "personal"
            : _constant(value['origin'], "personal") as String,
        official: value['official'] == null
            ? false
            : _constant(value['official'], false) as bool,
      );
  @override
  Map<String, Object?> toJson() => {
    'import_id': importId,
    'owner_id': ownerId,
    'committed_at': committedAt.toUtc().toIso8601String(),
    'record_count': recordCount,
    'profile_version_at_import': profileVersionAtImport,
    'mappings': mappings.map((v) => v.toJson()).toList(),
    'replayed': replayed,
    'origin': origin,
    'official': official,
  };
}
