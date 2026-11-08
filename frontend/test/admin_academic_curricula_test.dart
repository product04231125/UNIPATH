import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/admin/academic_curricula_page.dart';
import 'package:university_path_frontend/features/admin/academic_workspace_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';

class CurriculumTransport implements ApiGateway {
  bool fail = false;
  final writes = <Map<String, dynamic>>[];
  Map<String, dynamic> curriculum = {
    'id': 'curriculum-1',
    'institution_id': 'school-a',
    'revision': 1,
    'version': 1,
    'name': '합성 교육과정',
    'curriculum_year': 2026,
    'status': 'draft',
    'classification_revision_id': 'classification-1',
    'scope': {'clauses': []},
    'courses': <Object>[],
    'legacy_courses': <Object>[],
  };
  final classification = {
    'id': 'classification-1',
    'institution_id': 'school-a',
    'revision': 1,
    'status': 'published',
    'nodes': [
      {
        'id': 'node-1',
        'logical_id': 'logical-1',
        'label': '학교 전공',
        'parent_id': null,
        'position': 0,
        'selectable': true,
      },
    ],
  };
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final route = Uri.parse(path).path;
    if (method == 'GET') {
      if (route.endsWith('study-tracks')) {
        return {'items': <Object>[], 'next_cursor': null};
      }
      if (route.endsWith('classification-revisions')) {
        return {
          'items': [classification],
          'next_cursor': null,
        };
      }
      if (route.endsWith('classification-1')) return classification;
      if (route.endsWith('curriculum-revisions')) {
        return {
          'items': [curriculum],
          'next_cursor': null,
        };
      }
      return curriculum;
    }
    if (method == 'POST' && route.endsWith('course-entries')) {
      writes.add(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(body)) as Map),
      );
      if (fail) throw const AuthFailure('결과 확인 실패', status: 503);
      curriculum = {
        ...curriculum,
        'version': 2,
        'courses': [
          {
            'id': 'entry-1',
            'logical_id': 'entry-logical',
            'course_id': 'course-1',
            'course_version': 1,
            'course_name': (body!['new_course'] as Map)['name'],
            'course_code': (body['new_course'] as Map)['code'],
            'classification_node_id': body['classification_node_id'],
            'requirement': body['requirement'],
            'recognized_credits': body['recognized_credits'],
            'position': 0,
          },
        ],
      };
      return curriculum;
    }
    throw StateError('Unexpected curriculum test request $method $path');
  }
}

void main() {
  testWidgets(
    'new course registration uses one shared classification and preserves uncertain retry',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final transport = CurriculumTransport();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AcademicCurriculaPage(
                api: AcademicWorkspaceApi(transport),
                ownerId: 'owner',
                schoolId: 'school-a',
                records: const [],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> enter(String key, String value) async {
        final field = find.byKey(ValueKey(key));
        await tester.ensureVisible(field);
        await tester.enterText(field, value);
        await tester.pumpAndSettle();
      }

      await enter('curriculum-new-course-name', '새 공통 과목');
      await enter('curriculum-new-course-code', 'SHARED-1');
      await enter('curriculum-source-credits', '3.25');
      await enter('curriculum-recognized-credits', '3.25');
      final selector = find.byWidgetPredicate(
        (w) => w is AnchoredSelectField<String> && w.label == '이수구분·세부분류',
      );
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, '학교 전공'));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, '과목 등록·연결');
      await tester.ensureVisible(save);
      transport.fail = true;
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(transport.writes, hasLength(1));
      expect(
        find.byKey(const ValueKey('curriculum-new-course-name')),
        findsOneWidget,
      );
      expect(transport.writes.single['classification_node_id'], 'node-1');
      expect(transport.writes.single.containsKey('category'), isFalse);
      transport.fail = false;
      final retry = find.text('같은 요청으로 다시 저장');
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(transport.writes, hasLength(2));
      expect(transport.writes[0], equals(transport.writes[1]));
      expect(find.text('새 공통 과목 · SHARED-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
