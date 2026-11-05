import '../api/personal_evaluation_api.dart';
import '../api/student_api.dart';
import '../api/student_api_models.dart';

const personalConditionLabels = {
  'none': '조건 미지정 · 확인 필요',
  'minimum_credits': '최소 학점',
  'required_courses': '필수 과목',
  'minimum_volunteer_hours': '최소 봉사 시간',
  'any_certificate': '자격 보유',
  'thesis': '논문·졸업작품',
};

/// Decimal validation never converts the user's comparison values to double.
String? validateCalculationAmount(String? raw, {bool optional = false}) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty && optional) return null;
  if (!RegExp(r'^\d{1,24}(\.\d{1,6})?$').hasMatch(value)) {
    return '0~1,000,000의 숫자를 소수 여섯 자리 이내로 입력하세요.';
  }
  final parts = value.split('.');
  final scaled =
      BigInt.parse(parts.first) * BigInt.from(1000000) +
      BigInt.parse((parts.length == 1 ? '' : parts.last).padRight(6, '0'));
  return scaled > BigInt.from(1000000000000) ? '1,000,000 이하로 입력하세요.' : null;
}

String? validateCalculationDay(String? raw) {
  final value = raw ?? '';
  final date = DateTime.tryParse(value);
  return !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
          value.startsWith('0000-') ||
          date == null ||
          date.toIso8601String().substring(0, 10) != value
      ? '실제 날짜를 YYYY-MM-DD 형식으로 입력하세요.'
      : null;
}

class PersonalCalculationSources {
  const PersonalCalculationSources({
    required this.curriculum,
    required this.rules,
    required this.links,
    required this.courses,
    required this.activities,
    required this.credentials,
    required this.achievements,
  });
  final StudentRecord<StudentPersonalCurriculumCreate> curriculum;
  final List<StudentRecord<StudentPersonalGraduationRuleCreate>> rules;
  final List<StudentRecord<StudentPersonalCurriculumCourseCreate>> links;
  final List<StudentRecord<StudentCourseRecordCreate>> courses;
  final List<StudentRecord<StudentActivityRecordCreate>> activities;
  final List<StudentRecord<StudentCredentialRecordCreate>> credentials;
  final List<StudentRecord<StudentAchievementRecordCreate>> achievements;
  List<StudentRecord<StudentCourseRecordCreate>> get linkedCourses => courses
      .where((row) => links.any((link) => link.data.courseRecordId == row.id))
      .toList();
  bool active(
    StudentRecord<StudentPersonalGraduationRuleCreate> rule,
    String on,
  ) =>
      (rule.data.effectiveFrom == null ||
          rule.data.effectiveFrom!.compareTo(on) <= 0) &&
      (rule.data.effectiveTo == null ||
          rule.data.effectiveTo!.compareTo(on) >= 0);
}

/// Explicit form values only. Saved rule text/current value/grade/status labels
/// are never parsed into executable conditions or approval observations.
class PersonalCalculationDraft {
  PersonalCalculationDraft();
  factory PersonalCalculationDraft.fromCondition(
    PersonalCondition condition, {
    PersonalCalculationSources? sources,
  }) {
    final draft = PersonalCalculationDraft();
    draft.kind = condition.toJson()['kind'] as String;
    switch (condition) {
      case PersonalCreditCondition():
        draft.values.addAll({
          'minimum': condition.minimum,
          'category': condition.category ?? '',
        });
        draft.allCourses = condition.courseRecordIds == null;
        draft.selected.addAll(condition.courseRecordIds ?? []);
      case PersonalVolunteerCondition():
        draft.values['minimum'] = condition.minimum;
        draft.selected.addAll(condition.activityIds);
      case PersonalCourseCondition():
        for (final course in condition.courses) {
          final link = sources?.links
              .where((r) => r.id == course.curriculumCourseId)
              .firstOrNull;
          final grade = condition.grades
              .where((g) => g.courseRecordId == link?.data.courseRecordId)
              .firstOrNull;
          if (grade != null) {
            draft.observation(course.curriculumCourseId).addAll({
              'points': grade.points,
              'scale': grade.scale,
            });
          }
          draft.selected.add(course.curriculumCourseId);
          draft.observation(course.curriculumCourseId).addAll({
            'minimumCredits': course.minimumCredits ?? '',
            'minimumGradePoints': course.minimumGradePoints ?? '',
            'comparisonGradeScale': course.comparisonGradeScale ?? '',
          });
        }
      case PersonalCertificateCondition():
        for (final item in condition.certificates) {
          draft.selected.add(item.credentialId);
          draft.observation(item.credentialId).addAll({
            'possession': item.possession,
            'validityKnown': '${item.validityKnown}',
          });
        }
      case PersonalThesisCondition():
        draft.values.addAll({
          'thesisType': condition.thesisType,
          'acceptedGrades': condition.acceptedGrades.join(', '),
        });
        draft.requiresApproval = condition.requiresApproval;
        for (final item in condition.records) {
          draft.selected.add(item.achievementId);
          draft.observation(item.achievementId).addAll({
            'completion': item.completion,
            'approval': item.approval,
          });
        }
    }
    return draft;
  }
  String kind = 'none';
  final values = <String, String>{};
  final selected = <String>{};
  final observations = <String, Map<String, String>>{};
  bool allCourses = false;
  bool requiresApproval = true;
  Map<String, String> observation(String id) =>
      observations.putIfAbsent(id, () => {});
  bool get hasInput =>
      kind != 'none' || values.isNotEmpty || selected.isNotEmpty;
  String _text(Map<String, String> map, String key, {bool optional = false}) {
    final value = (map[key] ?? '').trim();
    if ((!optional && value.isEmpty) || value.length > 128) {
      throw const FormatException('선택한 조건의 필수 항목과 128자 제한을 확인하세요.');
    }
    return value;
  }

  String? _number(
    Map<String, String> map,
    String key, {
    bool optional = false,
  }) {
    final value = (map[key] ?? '').trim();
    final error = validateCalculationAmount(value, optional: optional);
    if (error != null) throw FormatException(error);
    return value.isEmpty ? null : value;
  }

  void _selection(Iterable<String> available, {int min = 0, int max = 500}) {
    if (selected.length < min ||
        selected.length > max ||
        !available.toSet().containsAll(selected)) {
      throw FormatException('자료를 $min~$max개 선택하세요. 연결 대상이 바뀌었다면 다시 불러오세요.');
    }
  }

  PersonalCondition? condition(PersonalCalculationSources sources) {
    switch (kind) {
      case 'none':
        return null;
      case 'minimum_credits':
        if (!allCourses) _selection(sources.linkedCourses.map((r) => r.id));
        if (allCourses && sources.linkedCourses.length > 500) {
          throw const FormatException('계산할 수강 기록을 500개 이내로 선택하세요.');
        }
        final category = _text(values, 'category', optional: true);
        return PersonalCreditCondition(
          minimum: _number(values, 'minimum')!,
          category: category.isEmpty ? null : category,
          courseRecordIds: allCourses
              ? sources.linkedCourses.map((r) => r.id).toList()
              : selected.toList(),
        );
      case 'minimum_volunteer_hours':
        _selection(sources.activities.map((r) => r.id));
        return PersonalVolunteerCondition(
          minimum: _number(values, 'minimum')!,
          activityIds: selected.toList(),
        );
      case 'required_courses':
        _selection(sources.links.map((r) => r.id), min: 1, max: 100);
        final courses = <PersonalRequiredCourse>[];
        final grades = <String, PersonalGradeObservation>{};
        for (final id in selected) {
          final row = sources.links.singleWhere((r) => r.id == id);
          final fields = observation(id);
          final threshold = _number(
            fields,
            'minimumGradePoints',
            optional: true,
          );
          final scale = _text(fields, 'comparisonGradeScale', optional: true);
          if ((threshold == null) != scale.isEmpty) {
            throw const FormatException('성적 기준 점수와 비교 척도를 함께 입력하세요.');
          }
          courses.add(
            PersonalRequiredCourse(
              curriculumCourseId: id,
              minimumCredits: _number(fields, 'minimumCredits', optional: true),
              minimumGradePoints: threshold,
              comparisonGradeScale: scale.isEmpty ? null : scale,
            ),
          );
          final points = _number(fields, 'points', optional: true);
          final gradeScale = _text(fields, 'scale', optional: true);
          if ((points == null) != gradeScale.isEmpty) {
            throw const FormatException('내 성적 점수와 척도를 함께 입력하세요.');
          }
          if (points != null) {
            if (row.data.courseRecordId == null) {
              throw const FormatException('성적 관찰에는 연결된 수강 기록이 필요합니다.');
            }
            final recordId = row.data.courseRecordId!;
            if (grades.containsKey(recordId) &&
                (grades[recordId]!.points != points ||
                    grades[recordId]!.scale != gradeScale)) {
              throw const FormatException('같은 수강 기록의 성적 관찰 값을 같게 입력하세요.');
            }
            grades[recordId] = PersonalGradeObservation(
              courseRecordId: recordId,
              points: points,
              scale: gradeScale,
            );
          }
        }
        return PersonalCourseCondition(
          courses: courses,
          grades: grades.values.toList(),
        );
      case 'any_certificate':
        _selection(sources.credentials.map((r) => r.id), min: 1, max: 100);
        return PersonalCertificateCondition(
          certificates: [
            for (final id in selected)
              PersonalCertificateObservation(
                credentialId: id,
                possession: observation(id)['possession'] ?? 'unknown',
                validityKnown: observation(id)['validityKnown'] == 'true',
              ),
          ],
        );
      case 'thesis':
        _selection(
          sources.achievements
              .where((r) => r.data.thesisType.isNotEmpty)
              .map((r) => r.id),
          max: 100,
        );
        final grades = (values['acceptedGrades'] ?? '')
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (grades.length > 20 ||
            grades.toSet().length != grades.length ||
            grades.any((s) => s.length > 128)) {
          throw const FormatException('허용 성적은 중복 없이 20개 이내, 각 128자 이내로 입력하세요.');
        }
        return PersonalThesisCondition(
          thesisType: _text(values, 'thesisType'),
          requiresApproval: requiresApproval,
          acceptedGrades: grades,
          records: [
            for (final id in selected)
              PersonalThesisObservation(
                achievementId: id,
                completion: observation(id)['completion'] ?? 'unknown',
                approval: observation(id)['approval'] ?? 'needs_review',
              ),
          ],
        );
      default:
        throw const FormatException('지원하는 계산 조건을 선택하세요.');
    }
  }
}
