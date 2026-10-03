import '../records/personal_record_fields.dart';
import '../records/personal_record_repository.dart';

/// Explicit links between client-local UUIDs only; no school master FK mapping.
Future<List<PersonalRecordField>> personalGraduationFields(
  PersonalRecordKind kind,
) async {
  final fields = personalRecordFields(kind);
  if (kind == PersonalRecordKind.personalCurriculum) return fields;
  final curricula = PersonalRecordRepository(
    PersonalRecordKind.personalCurriculum,
  );
  await curricula.load();
  fields.add(
    _reference(
      'curriculumId',
      '연결할 개인 교육과정',
      curricula.records,
      required: true,
    ),
  );
  if (kind == PersonalRecordKind.personalCurriculumCourse) {
    final courses = PersonalRecordRepository(PersonalRecordKind.course);
    await courses.load();
    fields.add(_reference('courseRecordId', '연결할 개인 수강 기록', courses.records));
  } else {
    final courses = PersonalRecordRepository(
      PersonalRecordKind.personalCurriculumCourse,
    );
    await courses.load();
    fields.add(
      _reference('curriculumCourseId', '관련 개인 교육과정 과목', courses.records),
    );
    final labels = <String, String>{};
    for (final type in [
      PersonalRecordKind.course,
      PersonalRecordKind.activity,
      PersonalRecordKind.experience,
      PersonalRecordKind.credential,
      PersonalRecordKind.portfolio,
    ]) {
      final repo = PersonalRecordRepository(type);
      await repo.load();
      for (final record in repo.records) {
        labels['${type.name}/${record.id}'] =
            '${_menuName(type)} · ${record.value('title')}';
      }
    }
    fields.add(
      PersonalRecordField(
        'relatedRecord',
        '관련 개인 기록',
        options: ['', ...labels.keys],
        optionLabels: labels,
      ),
    );
  }
  return fields;
}

PersonalRecordField _reference(
  String key,
  String label,
  List<PersonalRecord> records, {
  bool required = false,
}) => PersonalRecordField(
  key,
  label,
  required: required,
  options: ['', ...records.map((r) => r.id)],
  optionLabels: {
    for (final r in records)
      r.id:
          '${r.value('title')} · ${r.value('curriculumYear').isEmpty ? r.value('category') : r.value('curriculumYear')}',
  },
);

String _menuName(PersonalRecordKind kind) => switch (kind) {
  PersonalRecordKind.course => '수강',
  PersonalRecordKind.activity => '활동',
  PersonalRecordKind.experience => '경험',
  PersonalRecordKind.credential => '자격',
  _ => '성과',
};

Future<String?> validatePersonalGraduationLinks(
  PersonalRecordKind kind,
  Map<String, String> values,
) async {
  final fields = await personalGraduationFields(kind);
  for (final field in fields.where((f) => f.options.isNotEmpty)) {
    if (field.validate(values[field.key]) != null) {
      return '${field.label}을 다시 선택하세요. 연결 대상이 변경되었을 수 있습니다.';
    }
  }
  final courseId = values['curriculumCourseId'] ?? '';
  if (courseId.isNotEmpty) {
    final repo = PersonalRecordRepository(
      PersonalRecordKind.personalCurriculumCourse,
    );
    await repo.load();
    final course = repo.records.where((r) => r.id == courseId).first;
    if (course.value('curriculumId') != values['curriculumId']) {
      return '관련 과목과 규칙의 개인 교육과정을 같게 선택하세요.';
    }
  }
  return null;
}
