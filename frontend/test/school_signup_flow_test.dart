import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:university_path_frontend/features/admin/school_signup_panel.dart';
import 'package:university_path_frontend/features/api/school_signup_models.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/auth/login_page.dart';

import 'support/auth_fixture.dart';

const receiptId = '00000000-0000-4000-8000-000000000003';
Map<String, dynamic> receipt({
  String owner = userId,
  String status = 'pending',
}) => {
  'id': receiptId,
  'applicant_id': owner,
  'institution_id': status == 'approved' ? otherId : null,
  'institution_name': status == 'approved' ? '검토 합성대' : null,
  'client_id': receiptId,
  'position': '담당자',
  'contact_email': 'staff@example.test',
  'reason': '합성 신청',
  'status': status,
  'version': status == 'pending' ? 1 : 2,
  'created_at': '2026-10-25T00:00:00Z',
  'updated_at': '2026-10-25T00:00:00Z',
  'reviewed_by': status == 'pending' ? null : userId,
  'reviewed_at': status == 'pending' ? null : '2026-10-25T00:00:01Z',
  'review_note': '',
  'identity_verified': status == 'approved',
  'affiliation_verified': status == 'approved',
  'granted_scope_id': status == 'approved' ? receiptId : null,
  'school_name': '합성대',
  'official_url': 'https://school.example.test',
};
Map<String, dynamic> reviewed({String status = 'pending'}) => {
  ...receipt(owner: otherId, status: status),
  'applicant': {
    'id': otherId,
    'email': 'private-staff@example.test',
    'display_name': '합성 신청 담당자',
    'role': status == 'approved' ? 'school_admin' : 'user',
    'account_status': 'active',
    'version': status == 'approved' ? 2 : 1,
  },
};
http.Response json(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Future<void> login(AuthApi auth) => auth.authenticate(
  email: 'synthetic@example.test',
  password: 'synthetic long password',
);
Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder field(String name) => find.ancestor(
  of: find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == name,
  ),
  matching: find.byType(TextFormField),
);
Future<void> type(WidgetTester tester, String name, String value) async {
  final finder = field(name);
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  await tester.pumpAndSettle();
}

void main() {
  test('native initial signup sends one account-and-school request and validates its owner', () async {
    final requests = <http.Request>[];
    final auth = AuthApi(
      cookieMode: false,
      client: MockClient((request) async {
        requests.add(request);
        final body = jsonDecode(request.body) as Map;
        return json({
          ...identityJson(),
          'access_token': token,
          'signup': {...receipt(), 'client_id': body['client_id']},
        }, 201);
      }),
    );
    addTearDown(auth.close);
    final result = await auth.registerSchoolAdmin(
      email: 'staff@example.test',
      password: 'synthetic long password',
      displayName: '합성 담당자',
      details: const SchoolAdminSignupDetails(
        clientId: receiptId,
        schoolName: '합성대',
        officialUrl: 'https://school.example.test',
        position: '담당자',
        contactEmail: 'staff@example.test',
        reason: '합성 신청',
      ),
    );
    expect(requests.single.url.path, '/api/v1/auth/school-admin-signups');
    final body = jsonDecode(requests.single.body) as Map;
    expect(body['session_mode'], 'bearer');
    expect(body.containsKey('role'), false);
    expect(result.signup.status, 'pending');
    expect(result.signup.institutionId, isNull);
    expect(auth.forOwner(userId), isNotNull);
  });

  test('delayed initial signup cannot replace a newer login', () async {
    final started = Completer<void>(), pending = Completer<http.Response>();
    final auth = AuthApi(
      cookieMode: false,
      client: MockClient((request) async {
        if (request.url.path.endsWith('school-admin-signups')) {
          started.complete();
          return pending.future;
        }
        return json({...identityJson(id: otherId), 'access_token': token});
      }),
    );
    addTearDown(auth.close);
    final old = expectLater(
      auth.registerSchoolAdmin(
        email: 'staff@example.test',
        password: 'synthetic long password',
        displayName: '합성 담당자',
        details: const SchoolAdminSignupDetails(
          clientId: receiptId,
          schoolName: '합성대',
          position: '담당자',
          contactEmail: 'staff@example.test',
          reason: '합성 신청',
        ),
      ),
      throwsA(isA<AuthFailure>()),
    );
    await started.future;
    await login(auth);
    pending.complete(
      json({
        ...identityJson(),
        'access_token': token,
        'signup': receipt(),
      }, 201),
    );
    await old;
    expect(auth.forOwner(otherId), isNotNull);
  });

  for (final size in [const Size(1440, 900), const Size(480, 520)]) {
    testWidgets(
      'signup loss keeps the same key, freezes fields, and confirms receipt at $size',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final keys = <String>[];
        var signed = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: LoginPage(
              onSignedIn: () => signed++,
              registerSchoolAdmin:
                  ({
                    required email,
                    required password,
                    required displayName,
                    required details,
                  }) async {
                    keys.add(details.clientId);
                    if (keys.length == 1) throw const AuthFailure('합성 응답 유실');
                    return SchoolAdminSignupView.fromJson({
                      ...receipt(),
                      'client_id': details.clientId,
                    });
                  },
            ),
          ),
        );
        await tap(tester, find.byKey(const Key('signup-tab')));
        await tap(tester, find.byKey(const Key('signup-school-admin')));
        for (final value in {
          '이름': '합성 담당자',
          '이메일 주소': 'staff@example.test',
          '비밀번호': 'synthetic long password',
          '비밀번호 확인': 'synthetic long password',
          '학교명': '합성대',
          '직책': '담당자',
          '연락 이메일': 'staff@example.test',
          '신청 사유': '합성 신청',
        }.entries) {
          await type(tester, value.key, value.value);
        }
        await tap(tester, find.byKey(const Key('signup-submit')));
        expect(signed, 0);
        expect(tester.widget<TextFormField>(field('학교명')).enabled, false);
        await tap(tester, find.byKey(const Key('signup-submit')));
        expect(keys, hasLength(2));
        expect(keys[0], keys[1]);
        expect(find.textContaining('접수 번호:'), findsOneWidget);
        expect(find.textContaining('승인 대기'), findsOneWidget);
        await tap(tester, find.text('계속하기'));
        expect(signed, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final denied in [false, true]) {
    testWidgets(
      'superadmin school creation review and permission loss denied=$denied',
      (tester) async {
        await tester.binding.setSurfaceSize(
          denied ? const Size(480, 520) : const Size(1440, 900),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        Map<String, dynamic>? sent;
        final auth = AuthApi(
          cookieMode: false,
          client: MockClient((request) async {
            if (request.url.path.endsWith('/login')) {
              return json({
                ...identityJson(role: 'super_admin'),
                'access_token': token,
              });
            }
            if (request.url.path.endsWith('/institutions')) {
              return json({'items': [], 'next_cursor': null});
            }
            if (request.method == 'POST') {
              sent = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
              return denied
                  ? json({}, 403)
                  : json(reviewed(status: 'approved'));
            }
            if (request.url.path.endsWith('/$receiptId')) {
              return json(reviewed());
            }
            return json({
              'items': [
                reviewed(status: sent == null ? 'pending' : 'approved'),
              ],
              'next_cursor': null,
            });
          }),
        );
        addTearDown(auth.close);
        await login(auth);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(denied ? 2 : 1)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: SchoolSignupPanel(
                  auth: auth,
                  ownerId: userId,
                  admin: true,
                  inline: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tap(tester, find.text('신청 상세·심사'));
        await tap(tester, find.text('새 학교 등록'));
        await tap(tester, find.text('신청자 신원을 별도로 확인했습니다'));
        await tap(tester, find.text('해당 학교 담당자 자격을 확인했습니다'));
        final note = find.widgetWithText(TextField, '검토 사유 (신청자에게 표시)');
        await tester.ensureVisible(note);
        await tester.enterText(note, '합성 신원·담당 확인');
        await tap(tester, find.text('승인·학교 연결 및 권한 부여'));
        expect(sent!['new_institution']['name'], '합성대');
        expect(sent!['institution_id'], isNull);
        expect(sent!['identity_verified'], true);
        if (denied) {
          expect(
            find.textContaining('private-staff@example.test'),
            findsNothing,
          );
          expect(find.text('승인·학교 연결 및 권한 부여'), findsNothing);
        } else {
          expect(find.text('학교 연결·관리자 권한 부여를 완료했습니다.'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
