// GENERATED from backend Pydantic DTOs; run scripts/export_student_contracts.py.
// Dates/UUIDs/Decimals stay wire strings. Instants are explicit DateTime values.
// These models do not upload, replace or remove existing local student data.

abstract interface class StudentPayload {
  Map<String, Object?> toJson();
}

String _decimal(Object? value) {
  if (value is String || value is num) return value.toString();
  throw const FormatException('Expected a decimal wire value');
}

class StudentRecordReference implements StudentPayload {
  const StudentRecordReference({required this.kind, required this.recordId});
  final String kind;
  final String recordId;
  factory StudentRecordReference.fromJson(Map<String, dynamic> value) =>
      StudentRecordReference(
        kind: value['kind'] as String,
        recordId: value['record_id'] as String,
      );
  @override
  Map<String, Object?> toJson() => {'kind': kind, 'record_id': recordId};
}

class StudentProfileData implements StudentPayload {
  const StudentProfileData({
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
  factory StudentProfileData.fromJson(Map<String, dynamic> value) =>
      StudentProfileData(
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
            : value['week_starts_on'] as String,
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

class StudentProfileView implements StudentPayload {
  const StudentProfileView({
    this.school = "",
    this.department = "",
    this.admissionYear,
    this.track,
    this.academicYearOverride,
    this.weekStartsOn = "sunday",
    this.institutionId,
    this.departmentId,
    this.curriculumId,
    required this.ownerId,
    required this.version,
    this.createdAt,
    this.updatedAt,
    this.official = false,
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
  final String ownerId;
  final int version;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool official;
  factory StudentProfileView.fromJson(Map<String, dynamic> value) =>
      StudentProfileView(
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
            : value['week_starts_on'] as String,
        institutionId: value['institution_id'] == null
            ? null
            : value['institution_id'] as String,
        departmentId: value['department_id'] == null
            ? null
            : value['department_id'] as String,
        curriculumId: value['curriculum_id'] == null
            ? null
            : value['curriculum_id'] as String,
        ownerId: value['owner_id'] as String,
        version: value['version'] as int,
        createdAt: value['created_at'] == null
            ? null
            : DateTime.parse(value['created_at'] as String),
        updatedAt: value['updated_at'] == null
            ? null
            : DateTime.parse(value['updated_at'] as String),
        official: value['official'] == null ? false : value['official'] as bool,
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
    'owner_id': ownerId,
    'version': version,
    'created_at': createdAt?.toUtc().toIso8601String(),
    'updated_at': updatedAt?.toUtc().toIso8601String(),
    'official': official,
  };
}

class StudentEventCreate implements StudentPayload {
  const StudentEventCreate({
    required this.title,
    this.detail = "",
    this.clientId,
    required this.startsAt,
    required this.endsAt,
    required this.timeZone,
    required this.category,
  });
  final String title;
  final String detail;
  final String? clientId;
  final DateTime startsAt;
  final DateTime endsAt;
  final String timeZone;
  final String category;
  factory StudentEventCreate.fromJson(Map<String, dynamic> value) =>
      StudentEventCreate(
        title: value['title'] as String,
        detail: value['detail'] == null ? "" : value['detail'] as String,
        clientId: value['client_id'] == null
            ? null
            : value['client_id'] as String,
        startsAt: DateTime.parse(value['starts_at'] as String),
        endsAt: DateTime.parse(value['ends_at'] as String),
        timeZone: value['time_zone'] as String,
        category: value['category'] as String,
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

class StudentCourseRecordCreate implements StudentPayload {
  const StudentCourseRecordCreate({
    required this.title,
    this.detail = "",
    this.clientId,
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
  final String? clientId;
  final String term;
  final String category;
  final String credits;
  final String section;
  final String courseCode;
  final String grade;
  final String completion;
  factory StudentCourseRecordCreate.fromJson(Map<String, dynamic> value) =>
      StudentCourseRecordCreate(
        title: value['title'] as String,
        detail: value['detail'] == null ? "" : value['detail'] as String,
        clientId: value['client_id'] == null
            ? null
            : value['client_id'] as String,
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
            : value['completion'] as String,
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

class StudentActivityRecordCreate implements StudentPayload {
  const StudentActivityRecordCreate({
    required this.title,
    this.detail = "",
    this.clientId,
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
  final String? clientId;
  final String? startedOn;
  final String? endedOn;
  final String organization;
  final String role;
  final String? reportedHours;
  final String? approvedHours;
  final String? approval;
  final String? observedOn;
  factory StudentActivityRecordCreate.fromJson(
    Map<String, dynamic> value,
  ) => StudentActivityRecordCreate(
    title: value['title'] as String,
    detail: value['detail'] == null ? "" : value['detail'] as String,
    clientId: value['client_id'] == null ? null : value['client_id'] as String,
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
    approval: value['approval'] == null ? null : value['approval'] as String,
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

class StudentExperienceRecordCreate implements StudentPayload {
  const StudentExperienceRecordCreate({
    required this.title,
    this.detail = "",
    this.clientId,
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
  final String? clientId;
  final String? startedOn;
  final String? endedOn;
  final String experienceType;
  final String organization;
  final String role;
  final String result;
  final String statusLabel;
  factory StudentExperienceRecordCreate.fromJson(Map<String, dynamic> value) =>
      StudentExperienceRecordCreate(
        title: value['title'] as String,
        detail: value['detail'] == null ? "" : value['detail'] as String,
        clientId: value['client_id'] == null
            ? null
            : value['client_id'] as String,
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

class StudentCredentialRecordCreate implements StudentPayload {
  const StudentCredentialRecordCreate({
    required this.title,
    this.detail = "",
    this.clientId,
    this.provider = "",
    this.level = "",
    this.earnedOn,
    this.expiresOn,
    this.statusLabel = "",
    this.evidenceUrl = "",
  });
  final String title;
  final String detail;
  final String? clientId;
  final String provider;
  final String level;
  final String? earnedOn;
  final String? expiresOn;
  final String statusLabel;
  final String evidenceUrl;
  factory StudentCredentialRecordCreate.fromJson(
    Map<String, dynamic> value,
  ) => StudentCredentialRecordCreate(
    title: value['title'] as String,
    detail: value['detail'] == null ? "" : value['detail'] as String,
    clientId: value['client_id'] == null ? null : value['client_id'] as String,
    provider: value['provider'] == null ? "" : value['provider'] as String,
    level: value['level'] == null ? "" : value['level'] as String,
    earnedOn: value['earned_on'] == null ? null : value['earned_on'] as String,
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

class StudentAchievementRecordCreate implements StudentPayload {
  const StudentAchievementRecordCreate({
    required this.title,
    this.detail = "",
    this.clientId,
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
  final String? clientId;
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
  factory StudentAchievementRecordCreate.fromJson(Map<String, dynamic> value) =>
      StudentAchievementRecordCreate(
        title: value['title'] as String,
        detail: value['detail'] == null ? "" : value['detail'] as String,
        clientId: value['client_id'] == null
            ? null
            : value['client_id'] as String,
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

class StudentPersonalCurriculumCreate implements StudentPayload {
  const StudentPersonalCurriculumCreate({
    required this.title,
    this.detail = "",
    this.clientId,
    required this.school,
    required this.department,
    required this.admissionYear,
    required this.curriculumYear,
    this.evidenceUrl = "",
  });
  final String title;
  final String detail;
  final String? clientId;
  final String school;
  final String department;
  final int admissionYear;
  final int curriculumYear;
  final String evidenceUrl;
  factory StudentPersonalCurriculumCreate.fromJson(
    Map<String, dynamic> value,
  ) => StudentPersonalCurriculumCreate(
    title: value['title'] as String,
    detail: value['detail'] == null ? "" : value['detail'] as String,
    clientId: value['client_id'] == null ? null : value['client_id'] as String,
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

class StudentPersonalCurriculumCourseCreate implements StudentPayload {
  const StudentPersonalCurriculumCourseCreate({
    required this.title,
    this.detail = "",
    this.clientId,
    required this.curriculumId,
    this.courseRecordId,
    this.courseCode = "",
    required this.category,
    required this.credits,
    required this.required,
  });
  final String title;
  final String detail;
  final String? clientId;
  final String curriculumId;
  final String? courseRecordId;
  final String courseCode;
  final String category;
  final String credits;
  final bool required;
  factory StudentPersonalCurriculumCourseCreate.fromJson(
    Map<String, dynamic> value,
  ) => StudentPersonalCurriculumCourseCreate(
    title: value['title'] as String,
    detail: value['detail'] == null ? "" : value['detail'] as String,
    clientId: value['client_id'] == null ? null : value['client_id'] as String,
    curriculumId: value['curriculum_id'] as String,
    courseRecordId: value['course_record_id'] == null
        ? null
        : value['course_record_id'] as String,
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
    'curriculum_id': curriculumId,
    'course_record_id': courseRecordId,
    'course_code': courseCode,
    'category': category,
    'credits': credits,
    'required': required,
  };
}

class StudentPersonalGraduationRuleCreate implements StudentPayload {
  const StudentPersonalGraduationRuleCreate({
    required this.title,
    this.detail = "",
    this.clientId,
    required this.curriculumId,
    this.curriculumCourseId,
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
  final String? clientId;
  final String curriculumId;
  final String? curriculumCourseId;
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
  final StudentRecordReference? relatedRecord;
  factory StudentPersonalGraduationRuleCreate.fromJson(
    Map<String, dynamic> value,
  ) => StudentPersonalGraduationRuleCreate(
    title: value['title'] as String,
    detail: value['detail'] == null ? "" : value['detail'] as String,
    clientId: value['client_id'] == null ? null : value['client_id'] as String,
    curriculumId: value['curriculum_id'] as String,
    curriculumCourseId: value['curriculum_course_id'] == null
        ? null
        : value['curriculum_course_id'] as String,
    ruleCode: value['rule_code'] == null ? "" : value['rule_code'] as String,
    ruleType: value['rule_type'] as String,
    scope: value['scope'] as String,
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
        : StudentRecordReference.fromJson(
            Map<String, dynamic>.from(value['related_record'] as Map),
          ),
  );
  @override
  Map<String, Object?> toJson() => {
    'title': title,
    'detail': detail,
    'client_id': clientId,
    'curriculum_id': curriculumId,
    'curriculum_course_id': curriculumCourseId,
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

class StudentPortfolioCompositionCreate implements StudentPayload {
  const StudentPortfolioCompositionCreate({
    required this.title,
    this.detail = "",
    this.clientId,
    this.audience = "private",
    this.reviewed = false,
    this.sources = const [],
  });
  final String title;
  final String detail;
  final String? clientId;
  final String audience;
  final bool reviewed;
  final List<StudentRecordReference> sources;
  factory StudentPortfolioCompositionCreate.fromJson(
    Map<String, dynamic> value,
  ) => StudentPortfolioCompositionCreate(
    title: value['title'] as String,
    detail: value['detail'] == null ? "" : value['detail'] as String,
    clientId: value['client_id'] == null ? null : value['client_id'] as String,
    audience: value['audience'] == null
        ? "private"
        : value['audience'] as String,
    reviewed: value['reviewed'] == null ? false : value['reviewed'] as bool,
    sources: value['sources'] == null
        ? const []
        : List.unmodifiable(
            (value['sources'] as List).map(
              (v) => StudentRecordReference.fromJson(
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

class StudentApplicationDocumentCreate implements StudentPayload {
  const StudentApplicationDocumentCreate({
    required this.title,
    this.detail = "",
    this.clientId,
    required this.target,
    required this.role,
    required this.documentType,
    this.body = "",
    this.sources = const [],
  });
  final String title;
  final String detail;
  final String? clientId;
  final String target;
  final String role;
  final String documentType;
  final String body;
  final List<StudentRecordReference> sources;
  factory StudentApplicationDocumentCreate.fromJson(
    Map<String, dynamic> value,
  ) => StudentApplicationDocumentCreate(
    title: value['title'] as String,
    detail: value['detail'] == null ? "" : value['detail'] as String,
    clientId: value['client_id'] == null ? null : value['client_id'] as String,
    target: value['target'] as String,
    role: value['role'] as String,
    documentType: value['document_type'] as String,
    body: value['body'] == null ? "" : value['body'] as String,
    sources: value['sources'] == null
        ? const []
        : List.unmodifiable(
            (value['sources'] as List).map(
              (v) => StudentRecordReference.fromJson(
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

class StudentInstitutionView implements StudentPayload {
  const StudentInstitutionView({
    required this.id,
    required this.name,
    this.countryCode = "",
    this.officialUrl = "",
    this.version = 1,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String name;
  final String countryCode;
  final String officialUrl;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  factory StudentInstitutionView.fromJson(Map<String, dynamic> value) =>
      StudentInstitutionView(
        id: value['id'] as String,
        name: value['name'] as String,
        countryCode: value['country_code'] == null
            ? ""
            : value['country_code'] as String,
        officialUrl: value['official_url'] == null
            ? ""
            : value['official_url'] as String,
        version: value['version'] == null ? 1 : value['version'] as int,
        createdAt: DateTime.parse(value['created_at'] as String),
        updatedAt: DateTime.parse(value['updated_at'] as String),
      );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'country_code': countryCode,
    'official_url': officialUrl,
    'version': version,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}

class StudentDepartmentPublicView implements StudentPayload {
  const StudentDepartmentPublicView({
    required this.id,
    required this.version,
    required this.name,
    required this.institutionId,
    required this.code,
  });
  final String id;
  final int version;
  final String name;
  final String institutionId;
  final String code;
  factory StudentDepartmentPublicView.fromJson(Map<String, dynamic> value) =>
      StudentDepartmentPublicView(
        id: value['id'] as String,
        version: value['version'] as int,
        name: value['name'] as String,
        institutionId: value['institution_id'] as String,
        code: value['code'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'name': name,
    'institution_id': institutionId,
    'code': code,
  };
}

class StudentCurriculumPublicView implements StudentPayload {
  const StudentCurriculumPublicView({
    required this.id,
    required this.version,
    required this.name,
    required this.institutionId,
    required this.departmentId,
    required this.year,
  });
  final String id;
  final int version;
  final String name;
  final String institutionId;
  final String departmentId;
  final int year;
  factory StudentCurriculumPublicView.fromJson(Map<String, dynamic> value) =>
      StudentCurriculumPublicView(
        id: value['id'] as String,
        version: value['version'] as int,
        name: value['name'] as String,
        institutionId: value['institution_id'] as String,
        departmentId: value['department_id'] as String,
        year: value['year'] as int,
      );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'name': name,
    'institution_id': institutionId,
    'department_id': departmentId,
    'year': year,
  };
}

class StudentCoursePublicView implements StudentPayload {
  const StudentCoursePublicView({
    required this.id,
    required this.version,
    required this.name,
    required this.institutionId,
    required this.code,
    required this.credits,
  });
  final String id;
  final int version;
  final String name;
  final String institutionId;
  final String code;
  final String credits;
  factory StudentCoursePublicView.fromJson(Map<String, dynamic> value) =>
      StudentCoursePublicView(
        id: value['id'] as String,
        version: value['version'] as int,
        name: value['name'] as String,
        institutionId: value['institution_id'] as String,
        code: value['code'] as String,
        credits: _decimal(value['credits']),
      );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'name': name,
    'institution_id': institutionId,
    'code': code,
    'credits': credits,
  };
}

class StudentCurriculumCoursePublicView implements StudentPayload {
  const StudentCurriculumCoursePublicView({
    required this.id,
    required this.version,
    required this.name,
    required this.institutionId,
    required this.curriculumId,
    required this.courseId,
    required this.category,
    required this.required,
  });
  final String id;
  final int version;
  final String name;
  final String institutionId;
  final String curriculumId;
  final String courseId;
  final String category;
  final bool required;
  factory StudentCurriculumCoursePublicView.fromJson(
    Map<String, dynamic> value,
  ) => StudentCurriculumCoursePublicView(
    id: value['id'] as String,
    version: value['version'] as int,
    name: value['name'] as String,
    institutionId: value['institution_id'] as String,
    curriculumId: value['curriculum_id'] as String,
    courseId: value['course_id'] as String,
    category: value['category'] as String,
    required: value['required'] as bool,
  );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'name': name,
    'institution_id': institutionId,
    'curriculum_id': curriculumId,
    'course_id': courseId,
    'category': category,
    'required': required,
  };
}

class StudentRuleSetPublicView implements StudentPayload {
  const StudentRuleSetPublicView({
    required this.id,
    required this.version,
    required this.status,
    required this.lineageId,
    required this.revision,
    required this.appliedAt,
    required this.name,
    required this.institutionId,
    this.departmentId,
    this.curriculumId,
    this.effectiveFrom,
    this.effectiveTo,
  });
  final String id;
  final int version;
  final String status;
  final String lineageId;
  final int revision;
  final DateTime appliedAt;
  final String name;
  final String institutionId;
  final String? departmentId;
  final String? curriculumId;
  final String? effectiveFrom;
  final String? effectiveTo;
  factory StudentRuleSetPublicView.fromJson(Map<String, dynamic> value) =>
      StudentRuleSetPublicView(
        id: value['id'] as String,
        version: value['version'] as int,
        status: value['status'] as String,
        lineageId: value['lineage_id'] as String,
        revision: value['revision'] as int,
        appliedAt: DateTime.parse(value['applied_at'] as String),
        name: value['name'] as String,
        institutionId: value['institution_id'] as String,
        departmentId: value['department_id'] == null
            ? null
            : value['department_id'] as String,
        curriculumId: value['curriculum_id'] == null
            ? null
            : value['curriculum_id'] as String,
        effectiveFrom: value['effective_from'] == null
            ? null
            : value['effective_from'] as String,
        effectiveTo: value['effective_to'] == null
            ? null
            : value['effective_to'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'status': status,
    'lineage_id': lineageId,
    'revision': revision,
    'applied_at': appliedAt.toUtc().toIso8601String(),
    'name': name,
    'institution_id': institutionId,
    'department_id': departmentId,
    'curriculum_id': curriculumId,
    'effective_from': effectiveFrom,
    'effective_to': effectiveTo,
  };
}

class StudentRulePublicView implements StudentPayload {
  const StudentRulePublicView({
    required this.id,
    required this.version,
    required this.status,
    required this.lineageId,
    required this.revision,
    required this.appliedAt,
    required this.name,
    required this.institutionId,
    this.departmentId,
    this.curriculumId,
    this.effectiveFrom,
    this.effectiveTo,
    this.ruleSetId,
    required this.ruleType,
    required this.definition,
    this.sourceUrl = "",
  });
  final String id;
  final int version;
  final String status;
  final String lineageId;
  final int revision;
  final DateTime appliedAt;
  final String name;
  final String institutionId;
  final String? departmentId;
  final String? curriculumId;
  final String? effectiveFrom;
  final String? effectiveTo;
  final String? ruleSetId;
  final String ruleType;
  final String definition;
  final String sourceUrl;
  factory StudentRulePublicView.fromJson(Map<String, dynamic> value) =>
      StudentRulePublicView(
        id: value['id'] as String,
        version: value['version'] as int,
        status: value['status'] as String,
        lineageId: value['lineage_id'] as String,
        revision: value['revision'] as int,
        appliedAt: DateTime.parse(value['applied_at'] as String),
        name: value['name'] as String,
        institutionId: value['institution_id'] as String,
        departmentId: value['department_id'] == null
            ? null
            : value['department_id'] as String,
        curriculumId: value['curriculum_id'] == null
            ? null
            : value['curriculum_id'] as String,
        effectiveFrom: value['effective_from'] == null
            ? null
            : value['effective_from'] as String,
        effectiveTo: value['effective_to'] == null
            ? null
            : value['effective_to'] as String,
        ruleSetId: value['rule_set_id'] == null
            ? null
            : value['rule_set_id'] as String,
        ruleType: value['rule_type'] as String,
        definition: value['definition'] as String,
        sourceUrl: value['source_url'] == null
            ? ""
            : value['source_url'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'status': status,
    'lineage_id': lineageId,
    'revision': revision,
    'applied_at': appliedAt.toUtc().toIso8601String(),
    'name': name,
    'institution_id': institutionId,
    'department_id': departmentId,
    'curriculum_id': curriculumId,
    'effective_from': effectiveFrom,
    'effective_to': effectiveTo,
    'rule_set_id': ruleSetId,
    'rule_type': ruleType,
    'definition': definition,
    'source_url': sourceUrl,
  };
}

class StudentDocumentPublicView implements StudentPayload {
  const StudentDocumentPublicView({
    required this.id,
    required this.version,
    required this.status,
    required this.lineageId,
    required this.revision,
    required this.appliedAt,
    required this.name,
    required this.institutionId,
    this.departmentId,
    this.curriculumId,
    this.effectiveFrom,
    this.effectiveTo,
    required this.sourceUrl,
    required this.documentType,
    this.ruleId,
  });
  final String id;
  final int version;
  final String status;
  final String lineageId;
  final int revision;
  final DateTime appliedAt;
  final String name;
  final String institutionId;
  final String? departmentId;
  final String? curriculumId;
  final String? effectiveFrom;
  final String? effectiveTo;
  final String sourceUrl;
  final String documentType;
  final String? ruleId;
  factory StudentDocumentPublicView.fromJson(Map<String, dynamic> value) =>
      StudentDocumentPublicView(
        id: value['id'] as String,
        version: value['version'] as int,
        status: value['status'] as String,
        lineageId: value['lineage_id'] as String,
        revision: value['revision'] as int,
        appliedAt: DateTime.parse(value['applied_at'] as String),
        name: value['name'] as String,
        institutionId: value['institution_id'] as String,
        departmentId: value['department_id'] == null
            ? null
            : value['department_id'] as String,
        curriculumId: value['curriculum_id'] == null
            ? null
            : value['curriculum_id'] as String,
        effectiveFrom: value['effective_from'] == null
            ? null
            : value['effective_from'] as String,
        effectiveTo: value['effective_to'] == null
            ? null
            : value['effective_to'] as String,
        sourceUrl: value['source_url'] as String,
        documentType: value['document_type'] as String,
        ruleId: value['rule_id'] == null ? null : value['rule_id'] as String,
      );
  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'status': status,
    'lineage_id': lineageId,
    'revision': revision,
    'applied_at': appliedAt.toUtc().toIso8601String(),
    'name': name,
    'institution_id': institutionId,
    'department_id': departmentId,
    'curriculum_id': curriculumId,
    'effective_from': effectiveFrom,
    'effective_to': effectiveTo,
    'source_url': sourceUrl,
    'document_type': documentType,
    'rule_id': ruleId,
  };
}
