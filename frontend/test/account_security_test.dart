import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/features/auth/account_security_dialog.dart';
import 'package:university_path_frontend/features/auth/account_security_gateway.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/auth/login_page.dart';
import 'package:university_path_frontend/features/auth/local_data_owner.dart';
import 'package:university_path_frontend/shared/widgets/input_dialog.dart';

import 'support/auth_fixture.dart';

http.Response json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
const oldPassword = 'synthetic old password 2026';
const newPassword = '  synthetic 새 비밀번호 2026  ';

class SecurityGateway implements AccountSecurityGateway {
  final calls = <(String, String?, String?)>[];
  int? failStatus;
  bool fail = false;
  AccountSessionStatus status = AccountSessionStatus.active;
  Completer<void>? deferred;
  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    calls.add(('password', oldPassword, newPassword));
    if (deferred != null) await deferred!.future;
    if (fail) throw AuthFailure('Synthetic safe error', status: failStatus);
  }

  @override
  Future<void> logoutAll() async {
    calls.add(('logoutAll', null, null));
    if (fail) throw AuthFailure('Synthetic safe error', status: failStatus);
  }

  @override
  Future<AccountSessionStatus> checkSession() async {
    calls.add(('check', null, null));
    return status;
  }
}

Widget host(
  SecurityGateway gateway, {
  ValueChanged<AccountSecurityOutcome>? onEnd,
  double scale = 1,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => showInputDialog<AccountSecurityOutcome>(
            context: context,
            builder: (_) => AccountSecurityDialog(
              identity: AuthIdentity.fromJson(
                Map<String, dynamic>.from(identityJson()),
              ),
              gateway: gateway,
              onKnownEnd: onEnd ?? (_) {},
            ),
          ),
          child: const Text('계정 보안 열기'),
        ),
      ),
    ),
  ),
);
Future<void> open(WidgetTester tester) async {
  await tester.tap(find.text('계정 보안 열기'));
  await tester.pumpAndSettle();
}

Future<void> fill(
  WidgetTester tester, {
  String old = oldPassword,
  String next = newPassword,
  String? confirmation,
}) async {
  for (final entry in {
    'security-old-password': old,
    'security-new-password': next,
    'security-confirm-password': confirmation ?? next,
  }.entries) {
    final f = find.byKey(ValueKey(entry.key));
    await tester.ensureVisible(f);
    await tester.enterText(f, entry.value);
  }
}

Future<void> submit(WidgetTester tester, String label) async {
  final b = find.widgetWithText(FilledButton, label);
  await tester.ensureVisible(b);
  await tester.tap(b);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('owner-bound password operation preserves raw input, clears only completed session and persists no secrets', () async {
    final calls = <http.Request>[];
    final auth = AuthApi(
      cookieMode: false,
      client: MockClient((r) async {
        calls.add(r);
        if (r.url.path.endsWith('/login')) {
          return json({...identityJson(), 'access_token': token});
        }
        expect(r.headers['X-Unipath-Owner'], userId);
        expect(r.headers['Authorization'], 'Bearer $token');
        if (r.url.path.endsWith('/change-password')) {
          expect(jsonDecode(r.body), {
            'old_password': oldPassword,
            'new_password': newPassword,
          });
          return http.Response('', 204);
        }
        return json(identityJson());
      }),
    );
    addTearDown(auth.close);
    await auth.authenticate(
      email: 'synthetic@example.test',
      password: oldPassword,
    );
    final captured = auth.securityForOwner(userId);
    await captured.changePassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
    expect(await auth.me(), isNull);
    expect(calls.length, 2);
    await expectLater(
      captured.logoutAll(),
      throwsA(isA<AuthFailure>().having((e) => e.status, 'stale status', 403)),
    );
    expect(calls.length, 2);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });
  test(
    'logout-all sends no password body and uses owner precondition',
    () async {
      final auth = AuthApi(
        cookieMode: false,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/login')) {
            return json({...identityJson(), 'access_token': token});
          }
          expect(r.url.path, '/api/v1/auth/logout-all');
          expect(r.headers['X-Unipath-Owner'], userId);
          expect(r.body, isEmpty);
          return http.Response('', 204);
        }),
      );
      addTearDown(auth.close);
      await auth.authenticate(
        email: 'synthetic@example.test',
        password: oldPassword,
      );
      await auth.securityForOwner(userId).logoutAll();
      expect(await auth.me(), isNull);
    },
  );
  for (final sameOwner in [false, true]) {
    test(
      'late old security completion cannot clear newer login sameOwner=$sameOwner',
      () async {
        final pending = Completer<http.Response>();
        var logins = 0;
        const secondToken = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
        final secondId = sameOwner ? userId : otherId;
        final auth = AuthApi(
          cookieMode: false,
          client: MockClient((r) async {
            if (r.url.path.endsWith('/login')) {
              logins++;
              return json({
                ...identityJson(id: logins == 1 ? userId : secondId),
                'access_token': logins == 1 ? token : secondToken,
              });
            }
            if (r.url.path.endsWith('/change-password')) return pending.future;
            expect(r.headers['Authorization'], 'Bearer $secondToken');
            return json(identityJson(id: secondId));
          }),
        );
        addTearDown(auth.close);
        await auth.authenticate(
          email: 'synthetic@example.test',
          password: oldPassword,
        );
        final previous = auth.securityForOwner(userId);
        final changing = previous.changePassword(
          oldPassword: oldPassword,
          newPassword: newPassword,
        );
        final assertion = expectLater(
          changing,
          throwsA(isA<AuthFailure>().having((e) => e.status, 'stale', 403)),
        );
        await Future<void>.delayed(Duration.zero);
        await auth.authenticate(
          email: 'other@example.test',
          password: 'other synthetic password 2026',
        );
        pending.complete(http.Response('', 204));
        await assertion;
        expect((await auth.me())!.id, secondId);
      },
    );
  }
  test('a concurrent me confirming revocation does not misclassify a known204 success', () async {
    final pending = Completer<http.Response>();
    bool revoked = false;
    final auth = AuthApi(
      cookieMode: false,
      client: MockClient((r) async {
        if (r.url.path.endsWith('/login')) {
          return json({...identityJson(), 'access_token': token});
        }
        if (r.url.path.endsWith('/change-password')) return pending.future;
        return revoked ? json({'error': {}}, 401) : json(identityJson());
      }),
    );
    addTearDown(auth.close);
    await auth.authenticate(
      email: 'synthetic@example.test',
      password: oldPassword,
    );
    final capability = auth.securityForOwner(userId);
    final changing = capability.changePassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
    await Future<void>.delayed(Duration.zero);
    revoked = true;
    expect(await auth.me(), isNull);
    pending.complete(http.Response('', 204));
    await changing;
    expect(await capability.checkSession(), AccountSessionStatus.expired);
  });
  test('session checks use captured owner, and unexpected mutation response never claims success', () async {
    int status = 200;
    final auth = AuthApi(
      cookieMode: true,
      client: MockClient((r) async {
        if (r.url.path.endsWith('/login')) return json(identityJson());
        expect(r.headers['X-Unipath-Owner'], userId);
        expect(r.headers.containsKey('Authorization'), isFalse);
        if (r.url.path.endsWith('/change-password')) return json({});
        return status == 200
            ? json(identityJson())
            : json({'error': {}}, status);
      }),
    );
    addTearDown(auth.close);
    await auth.authenticate(
      email: 'synthetic@example.test',
      password: oldPassword,
    );
    final capability = auth.securityForOwner(userId);
    await expectLater(
      capability.changePassword(
        oldPassword: oldPassword,
        newPassword: newPassword,
      ),
      throwsA(isA<AuthFailure>()),
    );
    expect(await capability.checkSession(), AccountSessionStatus.active);
    status = 403;
    expect(await capability.checkSession(), AccountSessionStatus.changed);
    status = 401;
    expect(await capability.checkSession(), AccountSessionStatus.expired);
  });

  testWidgets(
    'raw passwords and validation stay private until valid explicit submit',
    (tester) async {
      final gateway = SecurityGateway();
      AccountSecurityOutcome? ended;
      await tester.pumpWidget(host(gateway, onEnd: (v) => ended = v));
      await open(tester);
      await fill(tester, next: 'short');
      await submit(tester, '비밀번호 변경');
      expect(gateway.calls, isEmpty);
      await fill(tester, confirmation: 'different synthetic password');
      await submit(tester, '비밀번호 변경');
      expect(gateway.calls, isEmpty);
      await fill(tester, next: oldPassword);
      await submit(tester, '비밀번호 변경');
      expect(gateway.calls, isEmpty);
      await fill(tester);
      await submit(tester, '비밀번호 변경');
      expect(gateway.calls.single, ('password', oldPassword, newPassword));
      expect(ended, AccountSecurityOutcome.passwordChanged);
      expect(find.byType(AccountSecurityDialog), findsNothing);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );
  testWidgets(
    'cancelled all-device logout does not revoke or change password; confirmed logout sends no credentials',
    (tester) async {
      final gateway = SecurityGateway();
      AccountSecurityOutcome? ended;
      await tester.pumpWidget(host(gateway, onEnd: (v) => ended = v));
      await open(tester);
      await fill(tester);
      final logout = find.widgetWithText(OutlinedButton, '모든 기기 로그아웃');
      await tester.ensureVisible(logout);
      await tester.tap(logout);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '취소'));
      await tester.pumpAndSettle();
      expect(gateway.calls, isEmpty);
      await tester.ensureVisible(logout);
      await tester.tap(logout);
      await tester.pumpAndSettle();
      await submit(tester, '모든 기기 로그아웃');
      expect(gateway.calls.single, ('logoutAll', null, null));
      expect(ended, AccountSecurityOutcome.allSessionsEnded);
    },
  );
  testWidgets(
    'uncertain response probes without automatic re-post and retries only the same raw body',
    (tester) async {
      final g = SecurityGateway()..fail = true;
      await tester.pumpWidget(host(g));
      await open(tester);
      await fill(tester);
      await submit(tester, '비밀번호 변경');
      expect(g.calls.length, 1);
      expect(find.textContaining('자동으로 다시 보내지 않습니다'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '비밀번호 변경'))
            .onPressed,
        isNull,
      );
      final probe = find.widgetWithText(OutlinedButton, '로그인 상태 확인');
      await tester.ensureVisible(probe);
      await tester.tap(probe);
      await tester.pumpAndSettle();
      expect(g.calls.map((c) => c.$1), ['password', 'check']);
      expect(find.textContaining('확정된 것은 아닙니다'), findsOneWidget);
      g.fail = false;
      await submit(tester, '같은 요청으로 다시 시도');
      expect(g.calls.last, g.calls.first);
    },
  );
  testWidgets(
    'expired uncertain outcome never claims password change or all-device revocation',
    (tester) async {
      final g = SecurityGateway()
        ..fail = true
        ..status = AccountSessionStatus.expired;
      AccountSecurityOutcome? ended;
      await tester.pumpWidget(host(g, onEnd: (v) => ended = v));
      await open(tester);
      await fill(tester);
      await submit(tester, '비밀번호 변경');
      final probe = find.widgetWithText(OutlinedButton, '로그인 상태 확인');
      await tester.ensureVisible(probe);
      await tester.tap(probe);
      await tester.pumpAndSettle();
      expect(ended, AccountSecurityOutcome.expired);
      expect(g.calls.where((v) => v.$1 == 'password').length, 1);
    },
  );
  testWidgets(
    'dirty cancel confirms discard and in-flight request prevents double submission',
    (tester) async {
      final g = SecurityGateway()..deferred = Completer<void>();
      await tester.pumpWidget(host(g));
      await open(tester);
      await fill(tester);
      await tester.tap(find.widgetWithText(TextButton, '닫기'));
      await tester.pumpAndSettle();
      expect(find.text('작성한 내용을 폐기할까요?'), findsOneWidget);
      await tester.tap(find.text('계속 작성'));
      await tester.pumpAndSettle();
      final send = find.widgetWithText(FilledButton, '비밀번호 변경');
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '닫기'))
            .onPressed,
        isNull,
      );
      expect(g.calls.length, 1);
      g.deferred!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AccountSecurityDialog), findsNothing);
    },
  );
  testWidgets(
    'uncertain all-device logout never becomes a password operation',
    (tester) async {
      final gateway = SecurityGateway()..fail = true;
      await tester.pumpWidget(host(gateway));
      await open(tester);
      final logout = find.widgetWithText(OutlinedButton, '모든 기기 로그아웃');
      await tester.ensureVisible(logout);
      await tester.tap(logout);
      await tester.pumpAndSettle();
      await submit(tester, '모든 기기 로그아웃');
      expect(find.text('전송한 요청: 모든 기기 로그아웃'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '로그아웃 확인 필요'),
            )
            .onPressed,
        isNull,
      );
      final probe = find.widgetWithText(OutlinedButton, '로그인 상태 확인');
      await tester.ensureVisible(probe);
      await tester.tap(probe);
      await tester.pumpAndSettle();
      gateway.fail = false;
      await submit(tester, '같은 요청으로 다시 시도');
      expect(gateway.calls.map((v) => v.$1), [
        'logoutAll',
        'check',
        'logoutAll',
      ]);
    },
  );

  testWidgets(
    'known204 notice survives periodic expiry removing the old security route',
    (tester) async {
      final response = Completer<http.Response>();
      bool revoked = false;
      final auth = AuthApi(
        cookieMode: true,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/change-password')) return response.future;
          if (r.url.path.endsWith('/me')) {
            return revoked ? json({'error': {}}, 401) : json(identityJson());
          }
          return json({'items': [], 'next_cursor': null});
        }),
      );
      addTearDown(auth.close);
      await tester.pumpWidget(UniversityPathApp(authGateway: auth));
      await tester.pumpAndSettle();
      // Put the 60s periodic check near this request, before its 20s timeout.
      await tester.pump(const Duration(seconds: 50));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('계정 보안'));
      await tester.pumpAndSettle();
      await fill(tester);
      final submit = find.widgetWithText(FilledButton, '비밀번호 변경');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      revoked = true;
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(AccountSecurityDialog), findsNothing);
      response.complete(http.Response('', 204));
      await tester.pumpAndSettle();
      expect(find.text('비밀번호가 변경되었습니다. 새 비밀번호로 다시 로그인하세요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'changed-cookie403 closes old form and restores new identity without logging it out',
    (tester) async {
      String owner = userId;
      final requests = <http.Request>[];
      final auth = AuthApi(
        cookieMode: true,
        client: MockClient((r) async {
          requests.add(r);
          if (r.url.path.endsWith('/change-password')) {
            expect(r.headers['X-Unipath-Owner'], userId);
            return json({'error': {}}, 403);
          }
          if (r.url.path.endsWith('/me')) return json(identityJson(id: owner));
          return json({'items': [], 'next_cursor': null});
        }),
      );
      addTearDown(auth.close);
      await tester.pumpWidget(UniversityPathApp(authGateway: auth));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('계정 보안'));
      await tester.pumpAndSettle();
      await fill(tester);
      owner = otherId;
      await submit(tester, '비밀번호 변경');
      expect(find.byType(AccountSecurityDialog), findsNothing);
      expect(find.byType(LoginPage), findsNothing);
      expect(LocalDataOwner.currentUserId, otherId);
      expect((await auth.me())!.id, otherId);
      expect(
        requests.where(
          (r) =>
              r.url.path.endsWith('/logout') ||
              r.url.path.endsWith('/logout-all'),
        ),
        isEmpty,
      );
      expect(find.textContaining('비밀번호가 변경되었습니다'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a response after the transport timeout is not promoted to a known success',
    (tester) async {
      final response = Completer<http.Response>();
      bool revoked = false;
      final auth = AuthApi(
        cookieMode: true,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/change-password')) return response.future;
          if (r.url.path.endsWith('/me')) {
            return revoked ? json({'error': {}}, 401) : json(identityJson());
          }
          return json({'items': [], 'next_cursor': null});
        }),
      );
      addTearDown(auth.close);
      await tester.pumpWidget(UniversityPathApp(authGateway: auth));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('계정 보안'));
      await tester.pumpAndSettle();
      await fill(tester);
      final submit = find.widgetWithText(FilledButton, '비밀번호 변경');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      revoked = true;
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      response.complete(http.Response('', 204));
      await tester.pumpAndSettle();
      expect(find.textContaining('비밀번호가 변경되었습니다'), findsNothing);
      expect(find.textContaining('모든 기기의 세션이 종료되었습니다'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'development samples do not expose an unbacked account-security action',
    (tester) async {
      await tester.pumpWidget(
        const UniversityPathApp(startAuthenticated: true),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('계정 보안'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in [const Size(1440, 900), const Size(480, 520)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'validation failure preserves obscured input at $size scale=$scale',
        (tester) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final g = SecurityGateway()
            ..fail = true
            ..failStatus = 422;
          await tester.pumpWidget(host(g, scale: scale));
          await open(tester);
          await fill(tester);
          await submit(tester, '비밀번호 변경');
          expect(find.textContaining('입력은 유지됩니다'), findsOneWidget);
          for (final key in [
            'security-old-password',
            'security-new-password',
            'security-confirm-password',
          ]) {
            final f = tester.widget<TextFormField>(find.byKey(ValueKey(key)));
            expect(f.controller!.text, isNotEmpty);
            expect(
              tester
                  .widget<EditableText>(
                    find.descendant(
                      of: find.byKey(ValueKey(key)),
                      matching: find.byType(EditableText),
                    ),
                  )
                  .obscureText,
              isTrue,
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  for (final role in ['user', 'school_admin', 'super_admin']) {
    testWidgets(
      'real $role navigation exposes security and successful204 shows login notice',
      (tester) async {
        bool ended = false;
        final requests = <http.Request>[];
        final auth = AuthApi(
          cookieMode: true,
          client: MockClient((r) async {
            requests.add(r);
            if (r.url.path.endsWith('/change-password')) {
              expect(r.headers['X-Unipath-Owner'], userId);
              ended = true;
              return http.Response('', 204);
            }
            if (r.url.path.endsWith('/me')) {
              return ended
                  ? json({'error': {}}, 401)
                  : json(identityJson(role: role));
            }
            if (r.url.path.contains('/admin/')) {
              return json({'items': [], 'next_cursor': null});
            }
            if (r.url.path.endsWith('/planning-profile')) {
              return json({
                'owner_id': userId,
                'version': 0,
                'origin': 'personal',
                'official': false,
                'school': '',
                'department': '',
                'admission_year': null,
                'track': 'single_major',
                'planning_grade': null,
                'week_start': 'sunday',
                'time_zone': 'Asia/Seoul',
              });
            }
            return json({'items': [], 'next_cursor': null});
          }),
        );
        addTearDown(auth.close);
        // Restore a real AuthApi session rather than the unrelated sample/fallback page.
        await tester.pumpWidget(UniversityPathApp(authGateway: auth));
        await tester.pumpAndSettle();
        expect(find.byType(LoginPage), findsNothing);
        expect(find.byTooltip('계정 보안'), findsOneWidget);
        await tester.tap(find.byTooltip('계정 보안'));
        await tester.pumpAndSettle();
        await fill(tester);
        await submit(tester, '비밀번호 변경');
        expect(find.byType(LoginPage), findsOneWidget);
        expect(find.text('비밀번호가 변경되었습니다. 새 비밀번호로 다시 로그인하세요.'), findsOneWidget);
        expect(requests.where((r) => r.url.path.endsWith('/logout')), isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
