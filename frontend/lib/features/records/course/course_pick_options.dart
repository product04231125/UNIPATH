import '../../api/student_api.dart';
import '../../api/student_api_models.dart';
import '../../api/student_catalog_api.dart';
import '../../api/student_academic_api.dart';
import '../../../shared/credits_format.dart';
import '../personal_record_repository.dart';

class CoursePickOption {
  const CoursePickOption({
    required this.id,
    required this.title,
    required this.courseCode,
    required this.credits,
    required this.category,
    required this.sourceLabel,
    this.curriculumCourseId,
    this.curriculumId,
    this.academicContextId,
    this.requiredCourse,
    this.gradingBasis = 'unspecified',
  });

  final String id;
  final String title;
  final String courseCode;
  final String credits;
  final String category;
  final String sourceLabel;
  final String gradingBasis;
  final String? curriculumCourseId, curriculumId;
  final String? academicContextId;
  final bool? requiredCourse;
  String get categoryLabel => switch (category) {
    'major' => '전공',
    'general' => '교양',
    'other' => '기타',
    _ => category,
  };
  String get requirementLabel => switch (requiredCourse) {
    true => '필수',
    false => '선택',
    null => '필수 여부 미제공',
  };

  String get label {
    final parts = <String>[
      if (gradingBasis == 'pass_fail') 'P/F',
      [title, if (courseCode.isNotEmpty) '($courseCode)'].join(' '),
      if (credits.isNotEmpty) formatCreditsLabel(credits),
      if (category.isNotEmpty) categoryLabel,
      if (requiredCourse != null) requirementLabel,
    ];
    return parts.join(' · ');
  }

  bool matches(PersonalRecord record) {
    return id == 'record:${record.id}' || id == 'current:${record.id}';
  }
}

/// Source IDs define identity. Equal names/codes never merge distinct records.
Future<List<CoursePickOption>> loadCoursePickOptions({
  required PersonalRecordRepository courseRepository,
  PersonalRecordRepository? curriculumCourseRepository,
  StudentApi? studentApi,
  String? institutionId,
  String? departmentId,
  String? curriculumId,
  void Function(String message)? onIssue,
}) async {
  final options = <CoursePickOption>[];
  final seen = <String>{};

  void add(CoursePickOption option) {
    if (option.title.trim().isEmpty || !seen.add(option.id)) return;
    options.add(option);
  }

  final school = institutionId?.trim() ?? '';
  if (studentApi == null) {
    onIssue?.call('학교 과목 조회에 연결되지 않았습니다.');
  } else if (school.isEmpty) {
    onIssue?.call('설정에서 등록된 학교·학과·교육과정을 선택하고 저장하세요.');
  }
  var useLegacyCatalog = false;
  if (studentApi != null && school.isNotEmpty) {
    try {
      final workspace = await StudentAcademicApi.fromStudent(studentApi)
          .workspace();
      if (workspace.institutionId != school) {
        onIssue?.call('저장된 학교와 학업 기준이 다릅니다. 설정에서 학업 기준을 확인하세요.');
      } else if (workspace.contexts.isEmpty) {
        useLegacyCatalog = true;
      } else if (workspace.issues.isNotEmpty) {
        onIssue?.call('학업 기준을 다시 확인하세요. 현재 교육과정 과목을 불러올 수 없습니다.');
      } else {
        for (final context in workspace.contexts.where(
          (c) => c.institutionId == school,
        )) {
          for (final course in context.courses) {
            add(
              CoursePickOption(
                id: 'academic:${context.id}:${course.id}',
                title: course.name,
                courseCode: course.code,
                credits: course.credits,
                category: course.classificationLabel,
                sourceLabel:
                    '학교 교육과정 · ${context.curriculum} · ${context.track}',
                curriculumId: context.curriculumId,
                academicContextId: context.id,
                curriculumCourseId: course.id,
                gradingBasis: course.gradingBasis,
                requiredCourse: switch (course.requirement) {
                  'required' => true,
                  'elective' => false,
                  _ => null,
                },
              ),
            );
          }
        }
      }
    } catch (_) {
      onIssue?.call('학교 과목을 불러오지 못했습니다. 학업 기준을 확인하고 다시 읽기를 눌러 주세요.');
    }
  }
  if (studentApi != null && school.isNotEmpty && useLegacyCatalog) {
    final catalog = StudentCatalogApi(studentApi.api);
    final courses = <StudentCoursePublicView>[];
    try {
      final seenCursors = <String>{};
      String? cursor;
      do {
        final page = await catalog.list(
          StudentCatalogResources.courses,
          institutionId: school,
          departmentId: departmentId,
          curriculumId: curriculumId,
          cursor: cursor,
        );
        courses.addAll(page.items);
        cursor = page.nextCursor;
        if (cursor != null && !seenCursors.add(cursor)) {
          throw StateError('Catalog pagination cursor repeated.');
        }
      } while (cursor != null);
    } catch (_) {
      onIssue?.call('학교 과목을 불러오지 못했습니다. 다시 읽기를 눌러 주세요.');
    }
    final links = <String, List<StudentCurriculumCoursePublicView>>{};
    try {
      final seenCursors = <String>{};
      String? cursor;
      do {
        final page = await catalog.list(
          StudentCatalogResources.curriculumCourses,
          institutionId: school,
          departmentId: departmentId,
          curriculumId: curriculumId,
          cursor: cursor,
        );
        for (final link in page.items) {
          if (link.institutionId == school &&
              link.courseId.isNotEmpty &&
              (curriculumId == null ||
                  curriculumId.isEmpty ||
                  link.curriculumId == curriculumId)) {
            (links[link.courseId] ??= []).add(link);
          }
        }
        cursor = page.nextCursor;
        if (cursor != null && !seenCursors.add(cursor)) {
          throw StateError('Catalog pagination cursor repeated.');
        }
      } while (cursor != null);
    } catch (_) {
      onIssue?.call('교육과정별 이수구분·필수 여부를 불러오지 못했습니다. 다시 읽기를 눌러 주세요.');
    }
    for (final course in courses) {
      if (course.institutionId != school) continue;
      final candidates = links[course.id] ?? [];
      // A course in multiple curricula has no implicit last-row winner.
      final link = candidates.length == 1 ? candidates.single : null;
      add(
        CoursePickOption(
          id: 'catalog:${course.id}',
          title: course.name,
          courseCode: course.code,
          credits: course.credits,
          gradingBasis: course.gradingBasis,
          category: link?.category ?? '',
          sourceLabel: '학교 과목',
          curriculumCourseId: link?.id,
          curriculumId: link?.curriculumId,
          requiredCourse: link?.required,
        ),
      );
    }
  }

  final curriculum =
      curriculumCourseRepository ??
      PersonalRecordRepository(PersonalRecordKind.personalCurriculumCourse);
  await curriculum.load();
  for (final record in curriculum.records) {
    add(
      CoursePickOption(
        id: 'personal:${record.id}',
        title: record.value('title'),
        courseCode: record.value('courseCode'),
        credits: record.value('credits'),
        category: record.value('category'),
        sourceLabel: '내 교육과정',
        requiredCourse: switch (record.value('requiredCourse')) {
          'true' || '필수' => true,
          'false' || '선택' => false,
          _ => null,
        },
      ),
    );
  }

  await courseRepository.load();
  for (final record in courseRepository.records) {
    add(
      CoursePickOption(
        id: 'record:${record.id}',
        title: record.value('title'),
        courseCode: record.value('courseCode'),
        credits: record.value('credits'),
        category: record.value('category'),
        sourceLabel: '내 수강 기록',
        academicContextId: record.value('academicContextId').isEmpty
            ? null
            : record.value('academicContextId'),
        curriculumCourseId: record.value('academicEntryId').isEmpty
            ? null
            : record.value('academicEntryId'),
        gradingBasis: record.value('gradingBasis').isEmpty
            ? 'unspecified'
            : record.value('gradingBasis'),
      ),
    );
  }
  return options;
}
