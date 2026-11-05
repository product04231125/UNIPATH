import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:university_path_frontend/features/admin/school_admin_applications_dialog.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/shared/widgets/input_dialog.dart';

import 'school_admin_applications_ui_test.dart' as fixture;
import 'support/auth_fixture.dart';

Future<void> tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> type(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

void main() {
  for (final variant in [
    (const Size(1440, 900), 1.0),
    (const Size(480, 720), 1.0),
    (const Size(480, 520), 2.0),
  ]) {
    testWidgets(
      'empty catalogue supports an owned school request draft and protected discard at $variant',
      (tester) async {
        tester.view.physicalSize = variant.$1;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var writes = 0;
        final auth = AuthApi(
          cookieMode: false,
          client: MockClient((request) async {
            if (request.url.path.endsWith('/login')) {
              return fixture.reply({...identityJson(), 'access_token': token});
            }
            if (request.method != 'GET') writes++;
            return fixture.reply({'items': [], 'next_cursor': null});
          }),
        );
        addTearDown(auth.close);
        final identity = await auth.authenticate(
          email: 'synthetic@example.test',
          password: 'synthetic long password',
        );
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(variant.$2)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showInputDialog<void>(
                    context: context,
                    builder: (_) => SchoolAdminApplicationsDialog(
                      auth: auth,
                      identity: identity,
                    ),
                  ),
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('열기'));
        await tester.pumpAndSettle();
        expect(find.text('등록된 학교'), findsOneWidget);
        await tapVisible(tester, find.text('미등록 학교'));
        expect(find.textContaining('가입·미등록 학교 신청 이력입니다.'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: find.widgetWithText(TextFormField, '신청자 이름'),
                  matching: find.byType(TextField),
                ),
              )
              .readOnly,
          isTrue,
        );
        expect(find.text('합성 학생'), findsOneWidget);
        await type(tester, '학교명', '미등록 검증 대학');
        await type(tester, '공식 홈페이지', 'https://school.example.test');
        await type(tester, '직책', '학사 담당자');
        await type(tester, '연락 이메일', 'draft@example.test');
        await type(tester, '신청 사유', '학교 서비스 등록 요청');
        final submit = find.widgetWithText(FilledButton, '미등록 학교 신청');
        await tester.ensureVisible(submit);
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
        expect(writes, 0);
        expect(find.textContaining('신청이 접수됐습니다.'), findsNothing);
        expect(find.text('신청 내역이 없습니다.'), findsOneWidget);
        await tapVisible(tester, find.text('닫기'));
        expect(find.text('작성한 내용을 폐기할까요?'), findsOneWidget);
        await tester.tap(find.text('계속 작성'));
        await tester.pumpAndSettle();
        expect(find.text('학교 서비스 등록 요청'), findsOneWidget);
        await tapVisible(tester, find.text('닫기'));
        await tester.tap(find.text('내용 폐기'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('열기'));
        await tester.pumpAndSettle();
        await tapVisible(tester, find.text('미등록 학교'));
        expect(find.text('미등록 검증 대학'), findsNothing);
        expect(writes, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'registered and unregistered drafts stay separate across refresh and successful registered submission',
    (tester) async {
      var schoolsAvailable = false;
      Map<String, dynamic>? sent;
      final auth = AuthApi(
        cookieMode: false,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login')) {
            return fixture.reply({...identityJson(), 'access_token': token});
          }
          if (request.url.path.endsWith('/institutions')) {
            return fixture.reply({
              'items': [
                if (schoolsAvailable)
                  {
                    'id': fixture.school,
                    'name': '검증 대학',
                    'created_at': '2026-10-24T00:00:00Z',
                    'updated_at': '2026-10-24T00:00:00Z',
                  },
              ],
              'next_cursor': null,
            });
          }
          if (request.method == 'POST') {
            expect(request.url.path, '/api/v1/me/school-admin-applications');
            sent = jsonDecode(request.body) as Map<String, dynamic>;
            return fixture.reply(
              fixture.record(clientId: sent!['client_id'] as String),
            );
          }
          return fixture.reply({
            'items': [
              if (sent != null)
                fixture.record(clientId: sent!['client_id'] as String),
            ],
            'next_cursor': null,
          });
        }),
      );
      addTearDown(auth.close);
      final identity = await auth.authenticate(
        email: 'synthetic@example.test',
        password: 'synthetic long password',
      );
      await fixture.open(tester, auth, identity);
      await tapVisible(tester, find.text('미등록 학교'));
      await type(tester, '학교명', '별도 초안 학교');
      await type(tester, '연락 이메일', 'new@example.test');
      await type(tester, '직책', '미등록 담당자');
      await tapVisible(tester, find.text('등록된 학교'));
      schoolsAvailable = true;
      await tapVisible(tester, find.text('학교 목록 다시 읽기'));
      await tapVisible(tester, find.text('학교 선택'));
      await tester.tap(find.text('검증 대학').last);
      await tester.pumpAndSettle();
      await type(tester, '직책', '등록 학교 담당자');
      await type(tester, '연락 이메일', 'registered@example.test');
      await type(tester, '신청 사유', '등록 학교 관리 요청');
      await tapVisible(tester, find.text('미등록 학교'));
      expect(find.text('별도 초안 학교'), findsOneWidget);
      expect(find.text('new@example.test'), findsOneWidget);
      expect(find.text('미등록 담당자'), findsOneWidget);
      await tapVisible(tester, find.text('등록된 학교'));
      expect(find.text('registered@example.test'), findsOneWidget);
      expect(find.text('등록 학교 담당자'), findsOneWidget);
      await tapVisible(tester, find.text('신청 제출'));
      expect(sent!['institution_id'], fixture.school);
      expect(sent!['contact_email'], 'registered@example.test');
      expect(sent!.keys.toSet(), {
        'institution_id',
        'client_id',
        'position',
        'contact_email',
        'reason',
      });
      await tapVisible(tester, find.text('미등록 학교'));
      expect(find.text('별도 초안 학교'), findsOneWidget);
      expect(find.text('new@example.test'), findsOneWidget);
      expect(find.textContaining('신청이 접수됐습니다.'), findsNothing);
      expect(find.text('검증 대학 · 승인 대기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'local draft validates fields and input limits without submitting',
    (tester) async {
      var writes = 0;
      final auth = AuthApi(
        cookieMode: false,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login')) {
            return fixture.reply({...identityJson(), 'access_token': token});
          }
          if (request.method != 'GET') writes++;
          return fixture.reply({'items': [], 'next_cursor': null});
        }),
      );
      addTearDown(auth.close);
      final identity = await auth.authenticate(
        email: 'synthetic@example.test',
        password: 'synthetic long password',
      );
      await fixture.open(tester, auth, identity);
      await tapVisible(tester, find.text('미등록 학교'));
      await type(tester, '학교명', ' ');
      expect(find.text('학교명 입력이 필요합니다.'), findsOneWidget);
      expect(find.text('직책 입력이 필요합니다.'), findsOneWidget);
      expect(find.text('신청 사유 입력이 필요합니다.'), findsOneWidget);
      await type(tester, '연락 이메일', 'bad address');
      expect(find.text('연락 이메일 주소 형식을 확인하세요.'), findsOneWidget);
      for (final value in [
        'ftp://example.test',
        'https://user:password@example.test',
        'https://school example.test',
      ]) {
        await type(tester, '공식 홈페이지', value);
        expect(find.text('유효한 http/https 홈페이지 주소를 입력하세요.'), findsOneWidget);
      }
      await type(tester, '공식 홈페이지', '');
      expect(find.text('유효한 http/https 홈페이지 주소를 입력하세요.'), findsNothing);
      await type(tester, '연락 이메일', 'valid@example.test');
      expect(find.text('연락 이메일 주소 형식을 확인하세요.'), findsNothing);
      for (final entry in {
        '학교명': 128,
        '공식 홈페이지': 2048,
        '직책': 128,
        '연락 이메일': 254,
        '신청 사유': 1000,
      }.entries) {
        await type(tester, entry.key, 'a' * (entry.value + 1));
        expect(
          tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, entry.key),
              )
              .controller!
              .text
              .length,
          entry.value,
        );
      }
      expect(writes, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
