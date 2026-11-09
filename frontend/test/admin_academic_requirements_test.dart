import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/admin/academic_requirements_page.dart';
import 'package:university_path_frontend/features/admin/academic_requirement_content.dart';
import 'package:university_path_frontend/features/admin/academic_credit_preview.dart';
import 'package:university_path_frontend/features/admin/academic_workspace_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/app.dart';

class RequirementTransport implements ApiGateway {
  RequirementTransport(this.kind);
  final String kind;
  bool fail = false;
  final writes = <Map<String, dynamic>>[];
  late Map<String, dynamic> document = {
    'id': 'requirement-1',
    'institution_id': 'school-a',
    'revision': 1,
    'version': 1,
    'name': '합성 기준',
    'kind': kind,
    'status': 'draft',
    'scope': {'clauses': []},
    'content': switch (kind) {
      'checklist' => {
        'kind': kind,
        'lines': [
          {'id': 'line-1', 'text': '졸업시험 합격', 'scope': null},
        ],
      },
      'certification' => {'kind': kind, 'groups': [], 'tables': []},
      _ => {'kind': kind, 'headers': [], 'rows': [], 'cells': []},
    },
  };
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final route = Uri.parse(path).path;
    if (method == 'GET') {
      if (route.endsWith('requirement-revisions')) {
        return {
          'items': [document],
          'next_cursor': null,
        };
      }
      if (route.endsWith('requirement-1')) return document;
      return {'items': <Object>[], 'next_cursor': null};
    }
    if (method == 'PUT') {
      writes.add(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(body)) as Map),
      );
      if (fail) throw const AuthFailure('응답 확인 실패', status: 503);
      document = {
        ...document,
        ...body!,
        'version': (document['version'] as int) + 1,
      };
      return document;
    }
    throw StateError('Unexpected $method $path');
  }
}

const capture = bool.fromEnvironment('ACADEMIC_CAPTURE');
Future<void> screenshot(WidgetTester tester, GlobalKey key, String name) async {
  if (!capture) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final frame = await boundary.toImage(pixelRatio: 1);
    final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
    final output = Directory('../output/admin-academic-redesign')
      ..createSync(recursive: true);
    await File('${output.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    frame.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (!capture) return;
    await (FontLoader('Pretendard')..addFont(
          rootBundle.load('assets/fonts/pretendard/Pretendard-Regular.otf'),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final kind in ['checklist', 'certification', 'credit_table']) {
    testWidgets(
      '$kind saves through its server document without resetting unsaved input',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final transport = RequirementTransport(kind);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: universityPathTheme(),
            home: RepaintBoundary(
              key: boundary,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: AcademicRequirementsPage(
                    api: AcademicWorkspaceApi(transport),
                    ownerId: 'owner',
                    schoolId: 'school-a',
                    schoolName: '합성 대학',
                    kind: kind,
                    records: const [],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await screenshot(tester, boundary, kind);
        if (kind == 'checklist') {
          final field = find.byKey(const ValueKey('checklist-text-line-1'));
          await tester.ensureVisible(field);
          await tester.enterText(field, '졸업시험 또는 졸업작품 합격');
          await tester.pumpAndSettle();
        }
        final label = AcademicRequirementsPageState.labels[kind]!;
        final save = find.widgetWithText(FilledButton, '$label 저장');
        await tester.ensureVisible(save);
        transport.fail = true;
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(transport.writes, hasLength(1));
        transport.fail = false;
        final retry = find.text('같은 요청으로 다시 저장');
        await tester.ensureVisible(retry);
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(transport.writes, hasLength(2));
        expect(transport.writes[0], transport.writes[1]);
        if (kind == 'checklist') {
          expect(
            (transport.document['content'] as Map)['lines'][0]['text'],
            '졸업시험 또는 졸업작품 합격',
          );
          expect(find.text('졸업시험 또는 졸업작품 합격'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'nested credit headers preserve IDs, mapping and zero versus empty cells',
    (tester) async {
      final input = <String, dynamic>{
        'kind': 'credit_table',
        'headers': [
          {
            'id': 'g1',
            'label': '교양 과목',
            'parent_id': null,
            'position': 0,
            'role': 'group',
          },
          {
            'id': 'g2',
            'label': '필수',
            'parent_id': 'g1',
            'position': 0,
            'role': 'group',
          },
          {
            'id': 'c1',
            'label': '기초교양',
            'parent_id': 'g2',
            'position': 0,
            'role': 'value',
            'classification_node_id': 'node',
            'requirement': 'required',
            'match_mode': 'exact',
          },
          {
            'id': 'c2',
            'label': '선택',
            'parent_id': 'g1',
            'position': 1,
            'role': 'value',
          },
          {
            'id': 'c3',
            'label': '소계',
            'parent_id': 'g1',
            'position': 2,
            'role': 'subtotal',
            'aggregate_members': ['c1', 'c2'],
          },
        ],
        'rows': [
          {'id': 'r1', 'label': '단일전공', 'note': '입학연도별 기준', 'scope': null},
        ],
        'cells': [
          {
            'row_id': 'r1',
            'header_id': 'c1',
            'state': 'number',
            'value': '0.000',
          },
          {'row_id': 'r1', 'header_id': 'c2', 'state': 'empty', 'value': null},
          {
            'row_id': 'r1',
            'header_id': 'c3',
            'state': 'not_applicable',
            'value': null,
          },
        ],
      };
      final grid = creditGridFromAcademic(input);
      final wire = creditGridToAcademic(grid);
      expect((wire['cells'] as List)[0]['value'], '0.000');
      expect((wire['cells'] as List)[1]['state'], 'empty');
      expect((wire['cells'] as List)[2]['state'], 'not_applicable');
      final header = (wire['headers'] as List).firstWhere(
        (h) => h['id'] == 'c1',
      );
      expect(header['parent_id'], 'g2');
      expect(header['classification_node_id'], 'node');
      expect(header['match_mode'], 'exact');
      await tester.binding.setSurfaceSize(const Size(1440, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: universityPathTheme(),
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(body: AcademicCreditPreview(grid: grid)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('교양 과목'), findsOneWidget);
      expect(find.text('기초교양'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await screenshot(tester, boundary, 'nested-credit-preview');
    },
  );
}
