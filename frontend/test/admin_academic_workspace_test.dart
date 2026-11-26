import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/admin/academic_workspace_api.dart';
import 'package:university_path_frontend/features/admin/school_classification_server_page.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';

class WorkspaceTransport implements ApiGateway {
  Map<String, dynamic>? revision;
  final List<Map<String, Object?>> saves = [];
  bool failSave = false, failLoad = false;
  String school = 'school-a';

  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    if (method == 'GET' && failLoad) {
      throw const AuthFailure('기준 조회 실패', status: 503);
    }
    if (method == 'GET' && path.contains('study-tracks')) {
      return {'items': <Object>[], 'next_cursor': null};
    }
    if (method == 'GET' &&
        Uri.parse(path).path.endsWith('classification-revisions')) {
      return {
        'items': [if (revision != null) revision],
        'next_cursor': null,
      };
    }
    if (method == 'GET') return revision!;
    if (method == 'POST' && path.endsWith('classification-revisions')) {
      revision = {
        'id': 'revision-1',
        'institution_id': school,
        'revision': 1,
        'version': 1,
        'status': 'draft',
        'nodes': <Object>[],
      };
      return revision;
    }
    if (method == 'PUT') {
      saves.add(jsonDecode(jsonEncode(body)) as Map<String, dynamic>);
      if (failSave) throw const AuthFailure('응답 확인 실패', status: 503);
      revision = {
        ...revision!,
        'version': 2,
        'nodes': [
          for (final value in body!['nodes'] as List)
            {
              ...value as Map<String, dynamic>,
              'id': 'node-1',
              'logical_id': 'logical-1',
              'parent_id': value['parent_ref'],
            },
        ],
      };
      return revision;
    }
    throw StateError('Unexpected test request $method $path');
  }
}

Widget page(
  WorkspaceTransport transport, {
  String school = 'school-a',
  GlobalKey<SchoolClassificationServerPageState>? pageKey,
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: SchoolClassificationServerPage(
        key: pageKey,
        api: AcademicWorkspaceApi(transport),
        ownerId: 'owner',
        schoolId: school,
        schoolName: school,
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'classification editing preserves uncertain save and replays the same body',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final transport = WorkspaceTransport();
      final key = GlobalKey<SchoolClassificationServerPageState>();
      await tester.pumpWidget(page(transport, pageKey: key));
      await tester.pumpAndSettle();
      expect(find.textContaining('등록된 분류가 없습니다.'), findsOneWidget);
      await tester.tap(find.text('분류 작성 시작'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('server-classification-label')),
        '전공',
      );
      await tester.tap(find.widgetWithText(OutlinedButton, '분류 추가'));
      await tester.pumpAndSettle();
      expect(key.currentState!.dirty, isTrue);
      transport.failSave = true;
      await tester.tap(find.widgetWithText(FilledButton, '분류 저장'));
      await tester.pumpAndSettle();
      expect(find.text('전공'), findsOneWidget);
      expect(find.text('같은 요청으로 다시 저장'), findsOneWidget);
      expect(await key.currentState!.allowLeave(), isFalse);
      transport.failSave = false;
      await tester.tap(find.text('같은 요청으로 다시 저장'));
      await tester.pumpAndSettle();
      expect(transport.saves, hasLength(2));
      expect(transport.saves[0], equals(transport.saves[1]));
      expect(key.currentState!.dirty, isFalse);
      expect(find.text('전공'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed school read blocks writes while retry remains available',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final transport = WorkspaceTransport()..failLoad = true;
      await tester.pumpWidget(page(transport));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '분류 작성 시작'))
            .onPressed,
        isNull,
      );
      final reload = find.widgetWithText(OutlinedButton, '다시 불러오기');
      expect(tester.widget<OutlinedButton>(reload).onPressed, isNotNull);
      transport.failLoad = false;
      await tester.tap(reload);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '분류 작성 시작'))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'school switch clears previous school data even when the next read fails',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final transport = WorkspaceTransport()
        ..revision = {
          'id': 'revision-1',
          'institution_id': 'school-a',
          'revision': 1,
          'version': 1,
          'status': 'published',
          'nodes': [
            {
              'id': 'a',
              'logical_id': 'la',
              'parent_id': null,
              'label': '이전 학교 분류',
              'position': 0,
              'selectable': true,
            },
          ],
        };
      final key = GlobalKey<SchoolClassificationServerPageState>();
      await tester.pumpWidget(page(transport, pageKey: key));
      await tester.pumpAndSettle();
      expect(find.text('이전 학교 분류'), findsOneWidget);
      transport.failLoad = true;
      await tester.pumpWidget(
        page(transport, school: 'school-b', pageKey: key),
      );
      await tester.pumpAndSettle();
      expect(find.text('이전 학교 분류'), findsNothing);
      expect(find.text('기준 조회 실패'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('classification transport rejects another school response', () async {
    final transport = WorkspaceTransport()
      ..revision = {'id': 'revision-1', 'institution_id': 'school-b'};
    expect(
      AcademicWorkspaceApi(transport).classifications('school-a'),
      throwsFormatException,
    );
  });
}
