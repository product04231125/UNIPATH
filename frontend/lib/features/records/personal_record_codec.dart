import '../api/student_api.dart';
import '../api/student_api_models.dart';
import 'personal_record_repository.dart';

/// Explicit UI-to-wire mapping; no labels are promoted to official evidence.
class PersonalRecordCodec {
  const PersonalRecordCodec(this.kind);
  final PersonalRecordKind kind;
  StudentResource<StudentPayload> get resource => switch (kind) {
    PersonalRecordKind.personalSchool ||
    PersonalRecordKind.personalDepartment => throw UnsupportedError(
      'Personal schools and departments are device-local',
    ),
    PersonalRecordKind.course => StudentResources.courseRecords,
    PersonalRecordKind.activity => StudentResources.activityRecords,
    PersonalRecordKind.experience => StudentResources.experienceRecords,
    PersonalRecordKind.credential => StudentResources.credentialRecords,
    PersonalRecordKind.portfolio => StudentResources.achievementRecords,
    PersonalRecordKind.personalCurriculum => StudentResources.personalCurricula,
    PersonalRecordKind.personalCurriculumCourse =>
      StudentResources.curriculumCourses,
    PersonalRecordKind.personalGraduationRule =>
      StudentResources.graduationRules,
  };

  Map<String, String> get fields => {
    'title': 'title',
    'detail': 'detail',
    ...switch (kind) {
      PersonalRecordKind.personalSchool ||
      PersonalRecordKind.personalDepartment => <String, String>{},
      PersonalRecordKind.course => {
        'term': 'term',
        'category': 'category',
        'credits': 'credits',
        'section': 'section',
        'courseCode': 'course_code',
        'grade': 'grade',
        'completion': 'completion',
      },
      PersonalRecordKind.activity => {
        'organization': 'organization',
        'role': 'role',
        'startedOn': 'started_on',
        'endedOn': 'ended_on',
        'reportedHours': 'reported_hours',
        'approvedHours': 'approved_hours',
        'approval': 'approval',
        'observedOn': 'observed_on',
      },
      PersonalRecordKind.experience => {
        'type': 'experience_type',
        'organization': 'organization',
        'role': 'role',
        'result': 'result',
        'status': 'status_label',
        'startedOn': 'started_on',
        'endedOn': 'ended_on',
      },
      PersonalRecordKind.credential => {
        'provider': 'provider',
        'level': 'level',
        'earnedOn': 'earned_on',
        'expiresOn': 'expires_on',
        'status': 'status_label',
        'evidenceUrl': 'evidence_url',
      },
      PersonalRecordKind.portfolio => {
        'type': 'achievement_type',
        'thesisType': 'thesis_type',
        'thesisStatus': 'thesis_status_label',
        'thesisGrade': 'thesis_grade',
        'thesisApprovedOn': 'thesis_approved_on',
        'startedOn': 'started_on',
        'endedOn': 'ended_on',
        'role': 'role',
        'result': 'result',
        'evidenceUrl': 'evidence_url',
      },
      PersonalRecordKind.personalCurriculum => {
        'school': 'school',
        'department': 'department',
        'admissionYear': 'admission_year',
        'curriculumYear': 'curriculum_year',
        'evidenceUrl': 'evidence_url',
      },
      PersonalRecordKind.personalCurriculumCourse => {
        'curriculumId': 'curriculum_id',
        'courseRecordId': 'course_record_id',
        'courseCode': 'course_code',
        'category': 'category',
        'credits': 'credits',
        'requiredCourse': 'required',
      },
      PersonalRecordKind.personalGraduationRule => {
        'curriculumId': 'curriculum_id',
        'curriculumCourseId': 'curriculum_course_id',
        'ruleCode': 'rule_code',
        'ruleType': 'rule_type',
        'scope': 'scope',
        'requiredValue': 'required_value',
        'currentValue': 'current_value',
        'unit': 'unit',
        'condition': 'condition',
        'effectiveFrom': 'effective_from',
        'effectiveTo': 'effective_to',
        'evidenceUrl': 'evidence_url',
        'relatedRecord': 'related_record',
      },
    },
  };
  static const nullable = {
    'started_on',
    'ended_on',
    'earned_on',
    'expires_on',
    'observed_on',
    'thesis_approved_on',
    'reported_hours',
    'approved_hours',
    'approval',
    'course_record_id',
    'curriculum_course_id',
    'required_value',
    'current_value',
    'effective_from',
    'effective_to',
    'related_record',
  };
  static const completions = {
    '계획': 'planned',
    '수강 중': 'in_progress',
    '이수 기록': 'recorded',
  };
  static const scopes = {
    '학교 공통': 'institution',
    '학과': 'department',
    '교육과정': 'curriculum',
  };
  static const referenceKinds = {
    'course': 'course',
    'activity': 'activity',
    'experience': 'experience',
    'credential': 'credential',
    'portfolio': 'achievement',
  };

  static Map<String, Object?> reference(String value) {
    final parts = value.split('/');
    if (parts.length != 2 ||
        parts[1].isEmpty ||
        !referenceKinds.containsKey(parts[0])) {
      throw const FormatException('Invalid personal reference');
    }
    return {'kind': referenceKinds[parts[0]], 'record_id': parts[1]};
  }

  static String referenceValue(Map value) {
    final kind = referenceKinds.entries
        .where((e) => e.value == value['kind'])
        .firstOrNull
        ?.key;
    if (kind == null || value['record_id'] is! String) {
      throw const FormatException('Invalid personal reference');
    }
    return '$kind/${value['record_id']}';
  }

  StudentPayload encode(Map<String, String> values, {String? clientId}) {
    if (values.keys.any((k) => !fields.containsKey(k))) {
      throw const FormatException('Unsupported personal field');
    }
    final wire = <String, dynamic>{'client_id': clientId};
    for (final entry in fields.entries) {
      final value = values[entry.key] ?? '';
      Object? converted = value;
      if (value.isEmpty && nullable.contains(entry.value)) {
        converted = null;
      } else if (entry.key == 'completion') {
        converted = value.isEmpty ? 'planned' : completions[value];
        if (converted == null) {
          throw const FormatException('Unknown completion');
        }
      } else if (entry.key == 'scope') {
        converted = scopes[value];
        if (converted == null) throw const FormatException('Unknown scope');
      } else if (entry.key == 'requiredCourse') {
        if (!['필수', '선택'].contains(value)) {
          throw const FormatException('Unknown required flag');
        }
        converted = value == '필수';
      } else if (['admissionYear', 'curriculumYear'].contains(entry.key)) {
        converted = int.parse(value);
      } else if (entry.key == 'relatedRecord' && value.isNotEmpty) {
        converted = reference(value);
      }
      wire[entry.value] = converted;
    }
    return resource.decode(wire);
  }

  PersonalRecord decode(StudentRecord<StudentPayload> record) {
    final wire = record.data.toJson();
    final values = <String, String>{};
    for (final entry in fields.entries) {
      final value = wire[entry.value];
      String converted = value?.toString() ?? '';
      if (const {
            'credits',
            'reported_hours',
            'approved_hours',
            'required_value',
            'current_value',
          }.contains(entry.value) &&
          converted.contains('.')) {
        converted = converted
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
      }
      if (entry.key == 'completion') {
        converted =
            completions.entries
                .where((e) => e.value == value)
                .firstOrNull
                ?.key ??
            '';
        if (converted.isEmpty) {
          throw const FormatException('Unknown completion');
        }
      } else if (entry.key == 'scope') {
        converted =
            scopes.entries.where((e) => e.value == value).firstOrNull?.key ??
            '';
        if (converted.isEmpty) throw const FormatException('Unknown scope');
      } else if (entry.key == 'requiredCourse') {
        if (value is! bool) {
          throw const FormatException('Invalid required flag');
        }
        converted = value ? '필수' : '선택';
      } else if (entry.key == 'relatedRecord' && value != null) {
        converted = referenceValue(value as Map);
      }
      values[entry.key] = converted;
    }
    return PersonalRecord(
      id: record.id,
      values: values,
      version: record.version,
    );
  }
}
