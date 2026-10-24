import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/graduation/official_graduation_page.dart';

import 'graduation_api_test.dart' as fixture;
import 'support/auth_fixture.dart';

Map<String, Object?> catalogRow(String path) => {
  'id': otherId,
  'version': 1,
  'name': path.endsWith('institutions')
      ? '검증 대학'
      : path.endsWith('departments')
      ? '검증 학과'
      : '검증 과정',
  'created_at': '2026-10-21T00:00:00Z',
  'updated_at': '2026-10-21T00:00:00Z',
  'institution_id': otherId,
  'department_id': otherId,
  'code': 'synthetic',
  'year': 2026,
};

Future<void> choose(WidgetTester tester, String from, String to) async {
  await tester.ensureVisible(find.text(from));
  await tester.tap(find.text(from));
  await tester.pumpAndSettle();
  await tester.tap(find.text(to).last);
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [const Size(1440, 900), const Size(480, 720)]) {
    testWidgets(
      'audit preserves retry input and separates historical/current results $size',
      (tester) async {
        tester.view.resetPhysicalSize();
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final creates = <Map<String, dynamic>>[];
        final auth = AuthApi(
          cookieMode: false,
          client: MockClient((request) async {
            final path = request.url.path;
            if (path.endsWith('/login')) {
              return fixture.json({...identityJson(), 'access_token': token});
            }
            expect(request.headers['X-Unipath-Owner'], userId);
            if (path.contains('/catalog/')) {
              return fixture.json({
                'items': [catalogRow(path)],
                'next_cursor': null,
              });
            }
            if (request.method == 'POST') {
              creates.add(jsonDecode(request.body) as Map<String, dynamic>);
              if (creates.length == 1) {
                throw http.ClientException('synthetic offline');
              }
              return fixture.json({
                ...fixture.auditJson(),
                'client_id': creates.last['client_id'],
                'context': creates.last['context'],
                'evaluated_on': creates.last['as_of'],
              });
            }
            if (path.endsWith('/${fixture.auditId}')) {
              return fixture.json({
                ...fixture.auditJson(),
                'current_usable': false,
                'current_issues': [
                  {'kind': 'records', 'reason': 'approved_records_changed'},
                ],
              });
            }
            return fixture.json({
              'items': [fixture.auditJson()],
              'next_cursor': null,
            });
          }),
        );
        addTearDown(auth.close);
        await fixture.login(auth);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OfficialGraduationPage(
                auth: auth,
                ownerId: userId,
                onPersonal: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await choose(tester, '학교 선택', '검증 대학');
        await choose(tester, '학과 선택', '검증 학과');
        await choose(tester, '교육과정 선택', '검증 과정 (2026)');
        for (final entry in {
          '입학연도': '2026',
          '이수 경로': 'single_major',
          '기준일 (YYYY-MM-DD)': '2026-10-21',
        }.entries) {
          final field = find.widgetWithText(TextField, entry.key);
          await tester.ensureVisible(field);
          await tester.enterText(field, entry.value);
        }
        final run = find.text('졸업요건 감사 실행');
        await tester.ensureVisible(run);
        await tester.tap(run);
        await tester.pumpAndSettle();
        expect(creates, hasLength(1));
        expect(find.widgetWithText(TextField, 'single_major'), findsOneWidget);
        await tester.ensureVisible(run);
        await tester.tap(run);
        await tester.pumpAndSettle();
        expect(creates, hasLength(2));
        expect(creates[0], creates[1]);
        expect(find.text('감사 결과 · 충족'), findsOneWidget);
        expect(find.textContaining('3.500001'), findsOneWidget);
        final history = find.text('2026-10-21 · 충족');
        await tester.ensureVisible(history);
        await tester.tap(history);
        await tester.pumpAndSettle();
        expect(find.text('당시 기준일에 요건 충족이 확인됐습니다.'), findsOneWidget);
        expect(
          find.text('현재 사용할 수 없는 근거입니다. 재검토 후 새 감사를 실행하세요.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
