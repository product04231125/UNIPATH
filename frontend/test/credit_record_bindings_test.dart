import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        'planned': '99',
        'projected': '214',
        'in_progress': '20',
        'earned_with_in_progress': '135',
        'remaining': '15',
        'status': 'not_satisfied',
        'evidence': [],
        'issues': [],
      };
    }
    return value;
  }
}

class ComparisonTransport extends TranscriptTransport {
  ComparisonTransport() {
    final content = docs[2]['content'] as Map<String, dynamic>;
    content['headers'] = [
      {'id': 'general', 'label': '교양 과목', 'role': 'group', 'position': 0},
      for (var i = 0; i < labels.length; i++)
        {
          'id': 'col-$i',
          'label': labels[i],
          'role': 'value',
          'position': i,
          'parent_id': i < 3 ? 'general' : null,
        },
    ];
    content['cells'] = [];
    content['rows'][0]['note'] = '';
  }
  static const labels = ['필수', '선택', '소계', '전공 필수', '전공 선택', '일반선택', '총 이수학점'];
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final value = await super.request(method, path, body);
    if (Uri.parse(path).path.endsWith('academic-credit-progress')) {
      value!['tables'][0]['cells'] = [
        for (var i = 0; i < labels.length; i++)
          {
            'row_id': 'row',
            'header_id': 'col-$i',
            'target': ['18', '8', '26', '14', '56', '29', '130'][i],
            'earned': [null, '13', '41', '11', '57', '6', '115'][i],
            'planned': ['1', '0', '2', '3', '3', '12', '20'][i],
            'in_progress': ['1', '0', '2', '3', '3', '12', '20'][i],
            'earned_with_in_progress': [
              null,
              '13',
              '43',
              '14',
              '60',
              '18',
              '135',
            ][i],
            'projected': [null, '13', '43', '14', '60', '18', '135'][i],
            'remaining': [null, '0', '0', '3', '0', '23', '15'][i],
            'status': i == 0 ? 'needs_review' : 'not_satisfied',
            'evidence': [],
            'issues': i == 0 ? ['transcript_subcategory_required'] : [],
          },
      ];
    }
    return value;
  }
}

void main() {
  setUpAll(() async {
    if (!fixture.capture) return;
    await (FontLoader('Pretendard')..addFont(
          rootBundle.load('assets/fonts/pretendard/Pretendard-Regular.otf'),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'comparison matrix keeps zero and unknown distinct with grouped headers',
    (tester) async {
      final key = await fixture.mount(tester, ComparisonTransport());
      await tester.tap(find.text('학점표').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('단일전공\n기준학점'));
      expect(find.text('확인 필요'), findsNWidgets(3));
      expect(find.text('0'), findsWidgets);
      expect(find.text('교양 과목'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await fixture.screenshot(tester, key, 'credit-comparison-matrix');
    },
  );
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
    final key = await fixture.mount(tester, TranscriptTransport());
    await tester.tap(find.text('학점표').first);
    await tester.pumpAndSettle();
    for (final label in ['기준학점', '취득학점', '수강 중 학점', '취득 + 수강 중', '부족학점']) {
      expect(find.text('단일전공\n$label'), findsOneWidget);
    }
    for (final number in ['130', '115', '20', '135', '15']) {
      expect(find.text(number), findsOneWidget);
    }
    expect(find.text('산입·제외·확인 필요 과목'), findsNothing);
    await tester.ensureVisible(find.text('산입 내역'));
    await tester.tap(find.text('산입 내역'));
    await tester.pumpAndSettle();
    expect(find.text('산입·제외·확인 필요 과목'), findsOneWidget);
    await tester.tap(find.text('산입 내역'));
    await tester.pumpAndSettle();
    await fixture.screenshot(tester, key, 'credit-comparison-rows');
    expect(tester.takeException(), isNull);
  });
}
