import '../records/personal_record_fields.dart';
import '../records/personal_record_repository.dart';
import '../records/personal_repository_scope.dart';

/// Links between personal UUIDs in the selected store; no school master mapping.
Future<List<PersonalRecordField>> personalGraduationFields(
  PersonalRecordKind kind, {
  PersonalRepositoryFactory? repositoryFactory,
}) async {
  final fields = personalRecordFields(kind);
  final create = repositoryFactory ?? PersonalRecordRepository.new;
  if (repositoryFactory != null &&
      kind == PersonalRecordKind.personalCurriculum) {
    return fields;
  }
  if (kind == PersonalRecordKind.personalSchool) return fields;
  if (kind == PersonalRecordKind.personalDepartment ||
      kind == PersonalRecordKind.personalCurriculum) {
    final schools = create(PersonalRecordKind.personalSchool);
    await schools.load();
    fields.add(
      _reference(
        'schoolId',
        '연결할 개인 학교',
        schools.records,
        required: kind == PersonalRecordKind.personalDepartment,
        mirrorKey: kind == PersonalRecordKind.personalCurriculum
            ? 'school'
            : null,
      ),
    );
    if (kind == PersonalRecordKind.personalCurriculum) {
      final departments = create(PersonalRecordKind.personalDepartment);
      await departments.load();
      fields.add(
        _reference(
          'departmentId',
          '연결할 개인 학과',
          departments.records,
          mirrorKey: 'department',
        ),
      );
    }
    return fields;
  }
  final curricula = create(PersonalRecordKind.personalCurriculum);
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
    final courses = create(PersonalRecordKind.course);
    await courses.load();
    fields.add(_reference('courseRecordId', '연결할 개인 수강 기록', courses.records));
  } else {
    final courses = create(PersonalRecordKind.personalCurriculumCourse);
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
      final repo = create(type);
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
  String? mirrorKey,
}) => PersonalRecordField(
  key,
  label,
  required: required,
  mirrorKey: mirrorKey,
  options: ['', ...records.map((r) => r.id)],
  optionLabels: {
    for (final r in records)
      r.id: [
        r.value('title'),
        r.value('curriculumYear').isEmpty
            ? r.value('category')
            : r.value('curriculumYear'),
      ].where((v) => v.isNotEmpty).join(' · '),
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
  Map<String, String> values, {
  PersonalRepositoryFactory? repositoryFactory,
}) async {
  final create = repositoryFactory ?? PersonalRecordRepository.new;
  final fields = await personalGraduationFields(
    kind,
    repositoryFactory: create,
  );
  for (final field in fields.where((f) => f.options.isNotEmpty)) {
    if (field.validate(values[field.key]) != null) {
      return '${field.label}을 다시 선택하세요. 연결 대상이 변경되었을 수 있습니다.';
    }
  }
  if (kind == PersonalRecordKind.personalCurriculum &&
      (values['departmentId'] ?? '').isNotEmpty) {
    final departments = create(PersonalRecordKind.personalDepartment);
    await departments.load();
    final department = departments.records
        .where((r) => r.id == values['departmentId'])
        .firstOrNull;
    if (department == null ||
        department.value('schoolId') != values['schoolId']) {
      return '학교와 학과의 연결을 확인하세요.';
    }
  }
  final courseId = values['curriculumCourseId'] ?? '';
  if (courseId.isNotEmpty) {
    final repo = create(PersonalRecordKind.personalCurriculumCourse);
    await repo.load();
    final course = repo.records.where((r) => r.id == courseId).first;
    if (course.value('curriculumId') != values['curriculumId']) {
      return '관련 과목과 규칙의 개인 교육과정을 같게 선택하세요.';
    }
  }
  return null;
}
