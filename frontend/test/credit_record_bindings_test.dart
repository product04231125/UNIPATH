import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/admin/academic_credit_record_bindings.dart';
import 'package:university_path_frontend/features/admin/academic_workspace_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';

import 'student_academic_integration_test.dart' as fixture;

class BindingGateway implements ApiGateway {
  final writes = <Map<String, Object?>>[];
  bool lose = true;
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    if (method == 'GET') {
      return {
        'requirement_revision_id': 'revision',
        'institution_id': 'school',
        'version': 0,
        'bindings': {},
      };
    }
    writes.add(Map<String, Object?>.from(jsonDecode(jsonEncode(body)) as Map));
    if (lose) {
      lose = false;
      throw const AuthFailure('응답 유실', status: 503);
    }
    return {
      'requirement_revision_id': 'revision',
      'institution_id': 'school',
      'version': 1,
      'bindings': body!['bindings'],
    };
  }
}

class TranscriptTransport extends fixture.AcademicTransport {
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final value = await super.request(method, path, body);
    if (Uri.parse(path).path.endsWith('academic-credit-progress')) {
      final cells = value!['tables'][0]['cells'] as List;
      cells[0] = {
        'row_id': 'row',
        'header_id': 'column',
        'target': '130',
        'earned': '115',
        'planned': '20',
        'projected': '135',
        'remaining': '15',
        'status': 'not_satisfied',
        'evidence': [],
        'issues': [],
      };
    }
    return value;
  }
}

void main() {
  testWidgets(
    'administrator saves category wiring and retries the exact uncertain request',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gateway = BindingGateway();
      final revision = <String, dynamic>{
        'id': 'revision',
        'content': {
          'headers': [
            {'id': 'group', 'label': '전공 과목', 'role': 'group', 'position': 0},
            {
              'id': 'required',
              'label': '필수',
              'role': 'value',
              'position': 0,
              'parent_id': 'group',
            },
          ],
        },
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => editCreditRecordBindings(
                  context,
                  AcademicWorkspaceApi(gateway),
                  'school',
                  revision,
                ),
                child: const Text('연결 편집'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('연결 편집'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '전공필수');
      await tester.tap(find.text('이수구분 연결 저장'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      await tester.tap(find.text('같은 요청으로 다시 저장'));
      await tester.pumpAndSettle();
      expect(gateway.writes, hasLength(2));
      expect(gateway.writes[0], gateway.writes[1]);
      expect(gateway.writes[0]['bindings'], {
        'required': ['전공필수'],
      });
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '전공필수',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('credit table shows earned, planned and projected separately', (
    tester,
  ) async {
    await fixture.mount(tester, TranscriptTransport());
    await tester.tap(find.text('학점표').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('취득 115\n예정 20\n총 135'), findsOneWidget);
    expect(find.textContaining('부족 15'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
