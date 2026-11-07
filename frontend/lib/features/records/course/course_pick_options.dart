import '../../api/student_api.dart';
import '../../api/student_api_models.dart';
import '../../api/student_catalog_api.dart';
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
  });

  final String id;
  final String title;
  final String courseCode;
  final String credits;
  final String category;
  final String sourceLabel;

  String get label {
    final parts = <String>[
      sourceLabel,
      [title, if (courseCode.isNotEmpty) '($courseCode)'].join(' '),
      if (credits.isNotEmpty) formatCreditsLabel(credits),
      if (category.isNotEmpty) category,
    ];
    return parts.join(' · ');
  }

  bool matches(PersonalRecord record) {
    final titleKey = _key(title, courseCode);
    return titleKey.isNotEmpty &&
        titleKey == _key(record.value('title'), record.value('courseCode'));
  }
}

String _key(String title, String code) =>
    '${title.trim().toLowerCase()}|${code.trim().toLowerCase()}';

/// Catalog, personal curriculum, then distinct existing course records.
Future<List<CoursePickOption>> loadCoursePickOptions({
  required PersonalRecordRepository courseRepository,
  PersonalRecordRepository? curriculumCourseRepository,
  StudentApi? studentApi,
  String? institutionId,
}) async {
  final options = <CoursePickOption>[];
  final seen = <String>{};

  void add(CoursePickOption option) {
    final key = _key(option.title, option.courseCode);
    if (option.title.trim().isEmpty || !seen.add(key)) return;
    options.add(option);
  }

  final school = institutionId?.trim() ?? '';
  if (studentApi != null && school.isNotEmpty) {
    final catalog = StudentCatalogApi(studentApi.api);
    final courses = <StudentCoursePublicView>[];
    try {
      final seenCursors = <String>{};
      String? cursor;
      do {
        final page = await catalog.list(
          StudentCatalogResources.courses,
          institutionId: school,
          cursor: cursor,
        );
        courses.addAll(page.items);
        cursor = page.nextCursor;
        if (cursor != null && !seenCursors.add(cursor)) {
          throw StateError('Catalog pagination cursor repeated.');
        }
      } while (cursor != null);
    } catch (_) {
      // School catalog is optional; personal sources still fill the list.
    }
    final categories = <String, String>{};
    try {
      final seenCursors = <String>{};
      String? cursor;
      do {
        final page = await catalog.list(
          StudentCatalogResources.curriculumCourses,
          institutionId: school,
          cursor: cursor,
        );
        for (final link in page.items) {
          if (link.courseId.isNotEmpty) {
            categories[link.courseId] = link.category;
          }
        }
        cursor = page.nextCursor;
        if (cursor != null && !seenCursors.add(cursor)) {
          throw StateError('Catalog pagination cursor repeated.');
        }
      } while (cursor != null);
    } catch (_) {
      // Curriculum links only add category; courses already collected stay.
    }
    for (final course in courses) {
      add(
        CoursePickOption(
          id: 'catalog:${course.id}',
          title: course.name,
          courseCode: course.code,
          credits: course.credits,
          category: categories[course.id] ?? '',
          sourceLabel: '학교 과목',
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
      ),
    );
  }
  return options;
}
