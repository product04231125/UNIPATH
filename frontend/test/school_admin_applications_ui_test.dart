import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:university_path_frontend/features/admin/school_admin_applications_dialog.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/shared/widgets/input_dialog.dart';

import 'support/auth_fixture.dart';

const school = '00000000-0000-4000-8000-000000000002';
const application = '00000000-0000-4000-8000-000000000003';
Map<String, Object?> record({String? clientId, String status = 'pending'}) => {
  'id': application,
  'applicant_id': userId,
  'institution_id': school,
  'institution_name': '검증 대학',
  'client_id': clientId ?? application,
  'position': '학사 담당자',
  'contact_email': 'staff@example.test',
  'reason': '담당 업무 신청',
  'status': status,
  'version': 1,
  'created_at': '2026-10-24T00:00:00Z',
  'updated_at': '2026-10-24T00:00:00Z',
  'reviewed_by': null,
  'reviewed_at': null,
  'review_note': '',
  'identity_verified': false,
  'affiliation_verified': false,
  'granted_scope_id': null,
};
http.Response reply(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<void> open(
  WidgetTester tester,
  AuthApi auth,
  AuthIdentity identity,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showInputDialog<void>(
              context: context,
              builder: (_) =>
                  SchoolAdminApplicationsDialog(auth: auth, identity: identity),
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('application review hides applicant after permission failure', (
    tester,
  ) async {
    final applicant = {
      ...record(),
      'applicant_id': otherId,
      'applicant': {
        'id': otherId,
        'email': 'staff@example.test',
        'display_name': '신청 담당자',
        'role': 'user',
        'account_status': 'active',
        'version': 3,
      },
    };
    final auth = AuthApi(
      cookieMode: false,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return reply({
            ...identityJson(role: 'super_admin'),
            'access_token': token,
          });
        }
        if (request.method == 'POST') return reply({}, 403);
        if (request.url.path.endsWith('/$application')) {
          return reply(applicant);
        }
        return reply({
          'items': [applicant],
          'next_cursor': null,
        });
      }),
    );
    addTearDown(auth.close);
    final identity = await auth.authenticate(
      email: 'admin@example.test',
      password: 'synthetic password',
    );
    await open(tester, auth, identity);
    await tester.tap(find.text('검증 대학 · 승인 대기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('신청자 신원을 별도로 확인했습니다'));
    await tester.tap(find.text('해당 학교 담당자 자격을 확인했습니다'));
    await tester.enterText(
      find.widgetWithText(TextField, '검토 사유 (신청자에게 표시)'),
      '검토 완료',
    );
    await tester.tap(find.text('승인·학교 범위 부여'));
    await tester.pumpAndSettle();
    expect(find.textContaining('staff@example.test'), findsNothing);
    expect(find.textContaining('신청 담당자'), findsNothing);
    expect(find.text('승인·학교 범위 부여'), findsNothing);
    expect(find.textContaining('현재 권한으로 이 신청을 검토할 수 없습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'applicant can confirm cancellation and cannot see review controls',
    (tester) async {
      var status = 'pending';
      final writes = <String>[];
      final auth = AuthApi(
        cookieMode: false,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login')) {
            return reply({...identityJson(), 'access_token': token});
          }
          if (request.url.path.endsWith('/institutions')) {
            return reply({'items': [], 'next_cursor': null});
          }
          if (request.method == 'POST') {
            writes.add(request.url.path);
            status = 'cancelled';
            return reply(record(status: status));
          }
          return reply({
            'items': [record(status: status)],
            'next_cursor': null,
          });
        }),
      );
      addTearDown(auth.close);
      final identity = await auth.authenticate(
        email: 'staff@example.test',
        password: 'synthetic long password',
      );
      await open(tester, auth, identity);
      expect(find.text('승인·학교 범위 부여'), findsNothing);
      await tester.ensureVisible(find.text('신청 취소'));
      await tester.tap(find.text('신청 취소'));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, '신청 취소'));
      await tester.pumpAndSettle();
      expect(writes.single, endsWith('/cancel'));
      expect(find.text('검증 대학 · 취소'), findsOneWidget);
    },
  );
  for (final size in [const Size(1440, 900), const Size(480, 720)]) {
    testWidgets('applicant preserves input and retry identity at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final requests = <Map<String, dynamic>>[];
      var saved = false;
      final auth = AuthApi(
        cookieMode: false,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login')) {
            return reply({...identityJson(), 'access_token': token});
          }
          if (request.url.path.endsWith('/institutions')) {
            return reply({
              'items': [
                {
                  'id': school,
                  'name': '검증 대학',
                  'created_at': '2026-10-24T00:00:00Z',
                  'updated_at': '2026-10-24T00:00:00Z',
                },
              ],
              'next_cursor': null,
            });
          }
          if (request.method == 'POST') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            requests.add(body);
            if (requests.length == 1) throw http.ClientException('offline');
            saved = true;
            return reply(record(clientId: body['client_id'] as String));
          }
          return reply({
            'items': saved
                ? [record(clientId: requests.last['client_id'] as String)]
                : [],
            'next_cursor': null,
          });
        }),
      );
      addTearDown(auth.close);
      final identity = await auth.authenticate(
        email: 'staff@example.test',
        password: 'synthetic long password',
      );
      await open(tester, auth, identity);
      await tester.tap(find.text('학교 선택'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('검증 대학').last);
      await tester.pumpAndSettle();
      for (final pair in [
        ('직책', '학사 담당자'),
        ('연락 이메일', 'staff@example.test'),
        ('신청 사유', '담당 업무 신청'),
      ]) {
        final field = find.widgetWithText(TextFormField, pair.$1);
        await tester.ensureVisible(field);
        await tester.enterText(field, pair.$2);
      }
      Future<void> submit() async {
        await tester.ensureVisible(find.text('신청 제출'));
        await tester.tap(find.text('신청 제출'));
        await tester.pumpAndSettle();
      }

      await submit();
      expect(find.text('담당 업무 신청'), findsOneWidget);
      expect(find.textContaining('입력을 유지'), findsOneWidget);
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      expect(find.text('작성한 내용을 폐기할까요?'), findsOneWidget);
      await tester.tap(find.text('계속 작성'));
      await tester.pumpAndSettle();
      await submit();
      expect(requests[0]['client_id'], requests[1]['client_id']);
      expect(find.textContaining('신청이 접수됐습니다'), findsOneWidget);
      expect(find.text('검증 대학 · 승인 대기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final approve in [true, false]) {
    testWidgets(
      'review ${approve ? 'approval' : 'rejection'} preserves verified decision and owner transport',
      (tester) async {
        final writes = <http.Request>[];
        var approved = false;
        final applicant = {
          ...record(),
          'applicant_id': otherId,
          'applicant': {
            'id': otherId,
            'email': 'staff@example.test',
            'display_name': '신청 담당자',
            'role': 'user',
            'account_status': 'active',
            'version': 3,
          },
        };
        final auth = AuthApi(
          cookieMode: false,
          client: MockClient((request) async {
            if (request.url.path.endsWith('/login')) {
              return reply({
                ...identityJson(role: 'super_admin'),
                'access_token': token,
              });
            }
            if (request.method == 'POST') {
              writes.add(request);
              approved = true;
              return reply({
                ...applicant,
                'status': approve ? 'approved' : 'rejected',
              });
            }
            if (request.url.path.endsWith('/$application')) {
              return reply(applicant);
            }
            return reply({
              'items': [
                {
                  ...applicant,
                  if (approved) 'status': approve ? 'approved' : 'rejected',
                },
              ],
              'next_cursor': null,
            });
          }),
        );
        addTearDown(auth.close);
        final identity = await auth.authenticate(
          email: 'admin@example.test',
          password: 'synthetic long password',
        );
        await open(tester, auth, identity);
        await tester.tap(find.text('검증 대학 · 승인 대기'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, '승인·학교 범위 부여'),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('신청자 신원을 별도로 확인했습니다'));
        await tester.tap(find.text('해당 학교 담당자 자격을 확인했습니다'));
        final note = find.byType(TextField);
        await tester.ensureVisible(note);
        await tester.enterText(note, '담당자 신원과 학교 소속을 확인했습니다.');
        final action = approve ? '승인·학교 범위 부여' : '반려';
        await tester.ensureVisible(find.text(action));
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        expect(writes.single.headers['X-Unipath-Owner'], userId);
        if (approve) {
          expect(jsonDecode(writes.single.body)['expected_user_version'], 3);
        }
        expect(
          writes.single.url.path,
          endsWith(approve ? '/approve' : '/reject'),
        );
        expect(find.text('검증 대학 · ${approve ? '승인' : '반려'}'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
