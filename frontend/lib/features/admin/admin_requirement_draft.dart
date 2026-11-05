import '../api/rule_program_models.dart';
import '../graduation/personal_calculation_draft.dart';
import 'admin_models.dart';

const executionKinds = {
  'credits': 'minimum_credits',
  'required_course': 'required_courses',
  'volunteer': 'minimum_volunteer_hours',
  'certificate': 'any_certificate',
  'thesis': 'thesis',
  'custom': 'manual_review',
};

class AdminRequirementDraft {
  final values = <String, String>{};
  final selected = <String>{};
  final referenceVersions = <String, int>{};
  final observations = <String, Map<String, String>>{};
  bool approval = true;
  String? number(
    String key, {
    bool optional = false,
    Map<String, String>? source,
  }) {
    final text = (source ?? values)[key]?.trim() ?? '';
    final error = validateCalculationAmount(text, optional: optional);
    if (error != null) throw FormatException(error);
    return text.isEmpty ? null : text;
  }

  String text(String key, {bool optional = false}) {
    final value = values[key]?.trim() ?? '';
    if ((!optional && value.isEmpty) || value.length > 128) {
      throw const FormatException('필수 입력과 128자 제한을 확인하세요.');
    }
    return value;
  }

  OfficialCondition condition(
    String type,
    Iterable<AdminRecord> courses,
    Iterable<CertificateRegistryCertificateView> certificates,
    String description,
  ) {
    switch (type) {
      case 'credits':
        final category = text('category', optional: true);
        return OfficialCreditCriterion(
          kind: 'minimum_credits',
          minimum: number('minimum')!,
          category: category.isEmpty ? null : category,
        );
      case 'volunteer':
        return OfficialVolunteerCriterion(
          kind: 'minimum_volunteer_hours',
          minimum: number('minimum')!,
        );
      case 'required_course':
        if (selected.isEmpty ||
            selected.length > 100 ||
            !courses.map((r) => r.id).toSet().containsAll(selected)) {
          throw const FormatException('같은 학교의 필수 과목을 1~100개 선택하세요.');
        }
        return OfficialCourseCriterion(
          kind: 'required_courses',
          courses: [
            for (final id in selected)
              () {
                final row = courses.singleWhere((r) => r.id == id);
                if (referenceVersions[id] != null &&
                    referenceVersions[id] != row.version) {
                  throw const FormatException(
                    '과목 버전이 변경되었습니다. 선택을 해제하고 다시 검토해 선택하세요.',
                  );
                }
                final observation = observations[id] ?? {};
                final grade = number(
                  'minimumGradePoints',
                  source: observation,
                  optional: true,
                );
                final scale = observation['comparisonGradeScale']?.trim() ?? '';
                if ((grade == null) != scale.isEmpty || scale.length > 128) {
                  throw const FormatException('최소 평점과 비교 척도를 함께 입력하세요.');
                }
                return OfficialProgramRequiredCourse(
                  courseId: id,
                  expectedVersion: row.version,
                  minimumCredits: number(
                    'minimumCredits',
                    source: observation,
                    optional: true,
                  ),
                  minimumGradePoints: grade,
                  comparisonGradeScale: scale.isEmpty ? null : scale,
                );
              }(),
          ],
        );
      case 'certificate':
        if (selected.isEmpty ||
            selected.length > 100 ||
            !certificates.map((r) => r.id).toSet().containsAll(selected)) {
          throw const FormatException('활성 자격증을 1~100개 선택하세요.');
        }
        for (final id in selected) {
          if (referenceVersions[id] != null &&
              referenceVersions[id] !=
                  certificates.singleWhere((r) => r.id == id).version) {
            throw const FormatException(
              '자격증 버전이 변경되었습니다. 선택을 해제하고 다시 검토해 선택하세요.',
            );
          }
        }
        return OfficialCertificateCriterion(
          kind: 'any_certificate',
          certificates: [
            for (final id in selected)
              OfficialCertificateChoice(
                certificateId: id,
                expectedVersion: certificates
                    .singleWhere((r) => r.id == id)
                    .version,
              ),
          ],
        );
      case 'thesis':
        final grades = (values['acceptedGrades'] ?? '')
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (grades.length > 20 ||
            grades.toSet().length != grades.length ||
            grades.any((s) => s.length > 128)) {
          throw const FormatException('허용 성적은 중복 없이 20개 이내로 입력하세요.');
        }
        return OfficialThesisCriterion(
          kind: 'thesis',
          thesisType: text('thesisType'),
          requiresApproval: approval,
          acceptedGrades: grades,
        );
      case 'custom':
        if (description.trim().isEmpty) {
          throw const FormatException('확인할 요건 설명을 입력하세요.');
        }
        return OfficialManualCriterion(
          kind: 'manual_review',
          instruction: description.trim(),
        );
      default:
        throw const FormatException('규칙 종류를 선택하세요.');
    }
  }

  factory AdminRequirementDraft.fromCondition(OfficialCondition condition) {
    final draft = AdminRequirementDraft();
    switch (condition) {
      case OfficialCreditCriterion():
        draft.values.addAll({
          'minimum': condition.minimum,
          'category': condition.category ?? '',
        });
      case OfficialVolunteerCriterion():
        draft.values['minimum'] = condition.minimum;
      case OfficialCourseCriterion():
        for (final r in condition.courses) {
          draft.selected.add(r.courseId);
          draft.referenceVersions[r.courseId] = r.expectedVersion;
          draft.observations[r.courseId] = {
            'minimumCredits': r.minimumCredits ?? '',
            'minimumGradePoints': r.minimumGradePoints ?? '',
            'comparisonGradeScale': r.comparisonGradeScale ?? '',
          };
        }
      case OfficialCertificateCriterion():
        draft.referenceVersions.addEntries(
          condition.certificates.map(
            (r) => MapEntry(r.certificateId, r.expectedVersion),
          ),
        );
        draft.selected.addAll(
          condition.certificates.map((r) => r.certificateId),
        );
      case OfficialThesisCriterion():
        draft.values.addAll({
          'thesisType': condition.thesisType,
          'acceptedGrades': condition.acceptedGrades.join(', '),
        });
        draft.approval = condition.requiresApproval;
      case OfficialManualCriterion():
        break;
    }
    return draft;
  }
  AdminRequirementDraft();
}
