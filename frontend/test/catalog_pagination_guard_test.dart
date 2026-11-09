import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/graduation/school_context_form.dart';
import 'package:university_path_frontend/features/records/course/course_pick_options.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';

import 'support/auth_fixture.dart';

class _RepeatingCursorGateway implements ApiGateway {
  var catalogCalls = 0;

  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    if (path == 'me/academic-contexts') {
      return {
        'owner_id': userId,
        'version': 0,
        'institution_id': otherId,
        'contexts': [],
        'issues': [],
      };
    }
    if (path.startsWith('catalog/')) {
      catalogCalls += 1;
      if (catalogCalls > 40) {
        fail('catalog pagination did not stop after repeated next_cursor');
      }
      return {
        'items': [
          {
            'id': otherId,
            'version': 1,
            'name': '반복 커서 학교',
            'created_at': '2026-10-21T00:00:00Z',
            'updated_at': '2026-10-21T00:00:00Z',
            'institution_id': otherId,
            'department_id': otherId,
            'code': 'LOOP',
            'credits': 3,
            'year': 2026,
            'course_id': otherId,
            'category': '전공',
          },
        ],
        'next_cursor': 'same-cursor',
      };
    }
    throw StateError('Unexpected route $method $path');
  }
}

class _ScopedCoursesGateway implements ApiGateway {
  final queries = <Uri>[];
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    if (path == 'me/academic-contexts') {
      return {
        'owner_id': userId,
        'version': 0,
        'institution_id': otherId,
        'contexts': [],
        'issues': [],
      };
    }
    final uri = Uri.parse(path);
    queries.add(uri);
    final curriculum = uri.queryParameters['curriculum_id'];
    return {
      'items': [
        {
          'id': otherId,
          'version': 1,
          'name': '범위 과목',
          'institution_id': otherId,
          'created_at': '2026-10-21T00:00:00Z',
          'updated_at': '2026-10-21T00:00:00Z',
          'department_id': otherId,
          'curriculum_id': curriculum,
          'course_id': otherId,
          'code': 'SCOPED',
          'credits': '3',
          'category': curriculum == userId ? 'major' : 'general',
          'required': true,
        },
      ],
      'next_cursor': null,
    };
  }
}

void main() {
  test('course picker pins both catalog requests to the profile department and curriculum', () async {
    final gateway = _ScopedCoursesGateway();
    final courses = PersonalRecordRepository(PersonalRecordKind.course);
    for (final curriculum in [userId, otherId]) {
      final options = await loadCoursePickOptions(
        courseRepository: courses,
        studentApi: StudentApi(gateway, ownerId: userId),
        institutionId: otherId,
        departmentId: otherId,
        curriculumId: curriculum,
      );
      final catalog = options.singleWhere(
        (item) => item.id.startsWith('catalog:'),
      );
      expect(catalog.category, curriculum == userId ? 'major' : 'general');
      for (final uri in gateway.queries.skip(gateway.queries.length - 2)) {
        expect(uri.queryParameters['institution_id'], otherId);
        expect(uri.queryParameters['department_id'], otherId);
        expect(uri.queryParameters['curriculum_id'], curriculum);
      }
    }
    expect(gateway.queries, hasLength(4));
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'loadCoursePickOptions stops when catalog next_cursor repeats',
    () async {
      final gateway = _RepeatingCursorGateway();
      final courses = PersonalRecordRepository(PersonalRecordKind.course);
      await courses.load();
      await courses.save(
        PersonalRecord(
          id: PersonalRecord.newId(),
          values: const {
            'title': '개인 대체 과목',
            'courseCode': 'P-1',
            'credits': '2',
            'category': '교양',
          },
        ),
      );

      final options = await loadCoursePickOptions(
        courseRepository: courses,
        studentApi: StudentApi(gateway, ownerId: userId),
        institutionId: otherId,
      ).timeout(const Duration(seconds: 2));

      expect(gateway.catalogCalls, lessThan(10));
      expect(options.map((o) => o.title), contains('개인 대체 과목'));
    },
  );

  testWidgets(
    'SchoolContextForm surfaces error instead of hanging on repeated cursor',
    (tester) async {
      final gateway = _RepeatingCursorGateway();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SchoolContextForm(
              api: gateway,
              showStudy: false,
              showDate: false,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 20 && gateway.catalogCalls < 3; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(gateway.catalogCalls, lessThan(10));
      expect(find.textContaining('학교 기준을 읽지 못했습니다'), findsOneWidget);
    },
  );
}
