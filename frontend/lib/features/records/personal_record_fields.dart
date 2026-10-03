import 'personal_record_repository.dart';
import '../../shared/external_links.dart';

enum PersonalFieldType { text, number, date, url }

class PersonalRecordField {
  const PersonalRecordField(
    this.key,
    this.label, {
    this.required = false,
    this.type = PersonalFieldType.text,
    this.options = const [],
    this.optionLabels = const {},
    this.multiline = false,
  });
  final String key;
  final String label;
  final bool required;
  final PersonalFieldType type;
  final List<String> options;
  final Map<String, String> optionLabels;
  final bool multiline;

  String? validate(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return required ? '$label 입력이 필요합니다.' : null;
    if (type == PersonalFieldType.number) {
      final number = double.tryParse(value);
      if (number == null ||
          !number.isFinite ||
          number < 0 ||
          (key == 'credits' && number == 0)) {
        return key == 'credits' ? '0보다 큰 학점을 입력하세요.' : '0 이상의 숫자를 입력하세요.';
      }
    }
    if (type == PersonalFieldType.date) {
      final date = DateTime.tryParse(value);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
          date == null ||
          date.toIso8601String().substring(0, 10) != value) {
        return '실제 날짜를 YYYY-MM-DD 형식으로 입력하세요.';
      }
    }
    if (type == PersonalFieldType.url) {
      if (browserLink(value) == null) {
        return '로그인 정보 없는 http/https 링크를 입력하세요.';
      }
    }
    if (options.isNotEmpty && !options.contains(value)) return '항목을 선택하세요.';
    if (['curriculumYear', 'admissionYear'].contains(key) &&
        !RegExp(r'^\d{4}$').hasMatch(value)) {
      return '연도는 네 자리 숫자로 입력하세요.';
    }
    return null;
  }
}

List<PersonalRecordField> personalRecordFields(PersonalRecordKind kind) => [
  const PersonalRecordField('title', '이름', required: true),
  const PersonalRecordField('detail', '설명 · 메모', multiline: true),
  ...switch (kind) {
    PersonalRecordKind.personalCurriculum => const [
      PersonalRecordField('school', '개인 학교명', required: true),
      PersonalRecordField('department', '개인 학과명', required: true),
      PersonalRecordField('admissionYear', '입학연도', required: true),
      PersonalRecordField('curriculumYear', '교육과정 연도', required: true),
      PersonalRecordField('evidenceUrl', '출처 링크', type: PersonalFieldType.url),
    ],
    PersonalRecordKind.personalCurriculumCourse => const [
      PersonalRecordField('courseCode', '개인 과목 코드'),
      PersonalRecordField('category', '교육과정 이수구분', required: true),
      PersonalRecordField(
        'credits',
        '과목 학점',
        required: true,
        type: PersonalFieldType.number,
      ),
      PersonalRecordField(
        'requiredCourse',
        '개인 필수 여부',
        required: true,
        options: ['필수', '선택'],
      ),
    ],
    PersonalRecordKind.personalGraduationRule => const [
      PersonalRecordField('ruleCode', '개인 규칙 코드'),
      PersonalRecordField('ruleType', '규칙 종류', required: true),
      PersonalRecordField(
        'scope',
        '개인 적용 범위',
        required: true,
        options: ['학교 공통', '학과', '교육과정'],
      ),
      PersonalRecordField(
        'requiredValue',
        '필요한 값',
        type: PersonalFieldType.number,
      ),
      PersonalRecordField(
        'currentValue',
        '직접 확인한 현재 값',
        type: PersonalFieldType.number,
      ),
      PersonalRecordField('unit', '값의 단위'),
      PersonalRecordField(
        'condition',
        '조건 · 대체 요건 · 성적 기준',
        required: true,
        multiline: true,
      ),
      PersonalRecordField(
        'effectiveFrom',
        '적용 시작일',
        type: PersonalFieldType.date,
      ),
      PersonalRecordField(
        'effectiveTo',
        '적용 종료일',
        type: PersonalFieldType.date,
      ),
      PersonalRecordField(
        'evidenceUrl',
        '규칙 출처 링크',
        type: PersonalFieldType.url,
      ),
    ],
    PersonalRecordKind.course => const [
      PersonalRecordField('term', '학기', required: true),
      PersonalRecordField('category', '이수구분', required: true),
      PersonalRecordField(
        'credits',
        '학점',
        required: true,
        type: PersonalFieldType.number,
      ),
      PersonalRecordField('section', '분반'),
      PersonalRecordField('courseCode', '과목 코드'),
      PersonalRecordField('grade', '원 성적 표기'),
      PersonalRecordField(
        'completion',
        '개인 기록 상태',
        options: ['계획', '수강 중', '이수 기록'],
      ),
    ],
    PersonalRecordKind.activity => const [
      PersonalRecordField('organization', '기관'),
      PersonalRecordField('startedOn', '시작일', type: PersonalFieldType.date),
      PersonalRecordField('endedOn', '종료일', type: PersonalFieldType.date),
      PersonalRecordField('role', '역할'),
      PersonalRecordField(
        'reportedHours',
        '직접 입력 봉사 시간',
        type: PersonalFieldType.number,
      ),
      PersonalRecordField(
        'approvedHours',
        '학교 시스템에서 확인한 승인 시간',
        type: PersonalFieldType.number,
      ),
      PersonalRecordField(
        'approval',
        '사용자가 확인한 승인 상태',
        options: ['pending', 'approved', 'rejected', 'needs_review'],
      ),
      PersonalRecordField(
        'observedOn',
        '학교 상태 확인일',
        type: PersonalFieldType.date,
      ),
    ],
    PersonalRecordKind.experience => const [
      PersonalRecordField('type', '경험 종류', required: true),
      PersonalRecordField('organization', '기관'),
      PersonalRecordField('startedOn', '시작일', type: PersonalFieldType.date),
      PersonalRecordField('endedOn', '종료일', type: PersonalFieldType.date),
      PersonalRecordField('role', '나의 역할'),
      PersonalRecordField('result', '결과 · 개인 기여', multiline: true),
      PersonalRecordField('status', '진행 상태'),
    ],
    PersonalRecordKind.credential => const [
      PersonalRecordField('provider', '발급 기관'),
      PersonalRecordField('level', '점수 · 등급'),
      PersonalRecordField('earnedOn', '취득일', type: PersonalFieldType.date),
      PersonalRecordField('expiresOn', '만료일', type: PersonalFieldType.date),
      PersonalRecordField('status', '보유 상태'),
      PersonalRecordField('evidenceUrl', '증빙 링크', type: PersonalFieldType.url),
    ],
    PersonalRecordKind.portfolio => const [
      PersonalRecordField('type', '성과 종류', required: true),
      PersonalRecordField('thesisType', '논문·캡스톤 유형 (해당 시)'),
      PersonalRecordField('thesisStatus', '논문·캡스톤 개인 기록 상태'),
      PersonalRecordField('thesisGrade', '논문·캡스톤 원 성적 표기'),
      PersonalRecordField(
        'thesisApprovedOn',
        '직접 확인한 논문·캡스톤 승인일',
        type: PersonalFieldType.date,
      ),
      PersonalRecordField('startedOn', '시작일', type: PersonalFieldType.date),
      PersonalRecordField('endedOn', '종료일', type: PersonalFieldType.date),
      PersonalRecordField('role', '나의 역할', required: true),
      PersonalRecordField('result', '결과 · 성과', required: true, multiline: true),
      PersonalRecordField(
        'evidenceUrl',
        '공개 가능한 링크',
        type: PersonalFieldType.url,
      ),
    ],
  },
];

String? personalRecordCrossError(Map<String, String> values) {
  for (final pair in [
    ('startedOn', 'endedOn'),
    ('earnedOn', 'expiresOn'),
    ('effectiveFrom', 'effectiveTo'),
  ]) {
    final start = DateTime.tryParse(values[pair.$1] ?? '');
    final end = DateTime.tryParse(values[pair.$2] ?? '');
    if (start != null && end != null && end.isBefore(start)) {
      return '종료·만료일은 시작·취득일보다 빠를 수 없습니다.';
    }
  }
  final approved = double.tryParse(values['approvedHours'] ?? '') ?? 0;
  if (approved > 0 &&
      (values['approval'] != 'approved' ||
          (values['observedOn'] ?? '').isEmpty)) {
    return '승인 시간을 기록하려면 승인 상태 approved와 학교 상태 확인일을 입력하세요.';
  }
  return null;
}
