import 'dart:async';
import 'dart:convert';

import 'support/auth_fixture.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/workspace.dart';
import 'package:university_path_frontend/features/auth/account_access_page.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/auth/local_data_owner.dart';
import 'package:university_path_frontend/features/auth/login_page.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/portfolio/portfolio_workspace_repository.dart';

http.Response jsonResponse(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalDataOwner.currentUserId = null;
  });
  tearDown(() => LocalDataOwner.currentUserId = null);

  test('native auth sends only credentials and keeps token in memory until server logout', () async {
    final requests = <http.Request>[];
    final api = AuthApi(
      cookieMode: false,
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/login')) {
          return jsonResponse({...identityJson(), 'access_token': token});
        }
        expect(request.headers['Authorization'], 'Bearer $token');
        if (request.url.path.endsWith('/logout')) return http.Response('', 204);
        return jsonResponse(identityJson());
      }),
    );
    expect(await api.me(), isNull);
    await api.authenticate(
      email: ' synthetic@example.test ',
      password: 'synthetic long password',
    );
    expect(jsonDecode(requests.first.body), {
      'email': 'synthetic@example.test',
      'password': 'synthetic long password',
      'session_mode': 'bearer',
    });
    expect((await api.me())!.id, userId);
    await api.logout();
    expect(await api.me(), isNull);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    api.close();
  });

  test(
    'browser auth requests cookie mode and never adds a bearer credential',
    () async {
      final api = AuthApi(
        cookieMode: true,
        client: MockClient((request) async {
          expect(request.headers.containsKey('Authorization'), isFalse);
          if (request.method == 'POST') {
            expect(jsonDecode(request.body)['session_mode'], 'cookie');
          }
          return jsonResponse(identityJson());
        }),
      );
      expect(
        (await api.authenticate(
          email: 'synthetic@example.test',
          password: 'synthetic password',
        )).id,
        userId,
      );
      expect((await api.me())!.id, userId);
      api.close();
    },
  );

  test(
    'server errors do not echo a password or an arbitrary server body',
    () async {
      for (final status in [401, 403, 409, 422, 429, 500]) {
        final api = AuthApi(
          client: MockClient(
            (_) async => jsonResponse({
              'error': {
                'message': 'private-password',
                'field_errors': [
                  {'field': 'body.email', 'reason': 'invalid'},
                ],
              },
            }, status),
          ),
        );
        await expectLater(
          api.authenticate(
            email: 'synthetic@example.test',
            password: 'private-password',
          ),
          throwsA(
            isA<AuthFailure>().having(
              (e) => e.message,
              'safe message',
              isNot(contains('private-password')),
            ),
          ),
        );
        api.close();
      }
    },
  );

  testWidgets('failed login preserves input and blocks duplicate submission', (
    tester,
  ) async {
    final pending = Completer<void>();
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          onSignedIn: () {},
          authenticate:
              ({required email, required password, displayName}) async {
                attempts++;
                await pending.future;
                throw const AuthFailure('이메일·비밀번호를 확인해 주세요.', status: 401);
              },
        ),
      ),
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'synthetic@example.test');
    await tester.enterText(fields.at(1), 'synthetic long password');
    await tester.ensureVisible(find.byKey(const Key('login-submit')));
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();
    expect(attempts, 1);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('login-submit')))
          .onPressed,
      isNull,
    );
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('이메일·비밀번호를 확인해 주세요.'), findsOneWidget);
    expect(find.text('synthetic@example.test'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(fields.at(1)).controller!.text,
      'synthetic long password',
    );
  });

  testWidgets(
    'real server role opens the live access page without synthetic editor',
    (tester) async {
      final api = FakeAuth(role: 'school_admin');
      await tester.pumpWidget(UniversityPathApp(authGateway: api));
      addTearDown(() async => tester.pumpWidget(const SizedBox()));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'synthetic@example.test');
      await tester.enterText(fields.at(1), 'synthetic long password');
      await tester.ensureVisible(find.byKey(const Key('login-submit')));
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();
      expect(find.byType(AccountAccessPage), findsOneWidget);
      expect(find.text('서버 합성 학교'), findsOneWidget);
      expect(find.text('합성 대학 A'), findsNothing);
      final emailStyle = DefaultTextStyle.of(
        tester.element(find.text('synthetic@example.test')),
      ).style;
      expect(emailStyle.decoration, isNot(TextDecoration.underline));
      expect(emailStyle.fontSize, lessThanOrEqualTo(20));
      expect(LocalDataOwner.currentUserId, userId);
      await tester.tap(find.widgetWithText(FilledButton, '로그아웃'));
      await tester.pumpAndSettle();
      expect(api.logouts, 1);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(LocalDataOwner.currentUserId, isNull);
    },
  );

  testWidgets(
    'a session switched in another tab recreates the local workspace',
    (tester) async {
      final api = FakeAuth()..signedIn = true;
      await tester.pumpWidget(UniversityPathApp(authGateway: api));
      await tester.pumpAndSettle();
      final originalWorkspace = tester.state(find.byType(Workspace));
      final first = PlanningRepository();
      await first.load();
      await first.saveSchoolContext(school: '계정 A 학교');
      api.id = otherId;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(LocalDataOwner.currentUserId, otherId);
      expect(
        tester.state(find.byType(Workspace)),
        isNot(same(originalWorkspace)),
      );
      final second = PlanningRepository();
      await second.load();
      expect(second.profile.school, isEmpty);
      expect(first.profile.school, '계정 A 학교');
      first.dispose();
      second.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('each account sees only its local records and old owners keep their original key', () async {
    LocalDataOwner.currentUserId = userId;
    final first = PersonalRecordRepository(PersonalRecordKind.course);
    await first.load();
    LocalDataOwner.currentUserId = otherId;
    final second = PersonalRecordRepository(PersonalRecordKind.course);
    await second.load();
    await first.save(PersonalRecord(id: 'first', values: {'title': 'A 계정 기록'}));
    await second.save(
      PersonalRecord(id: 'second', values: {'title': 'B 계정 기록'}),
    );
    await first.load();
    await second.load();
    expect(first.records.single.id, 'first');
    expect(second.records.single.id, 'second');
    expect(first.storageKey, isNot(second.storageKey));
  });

  test(
    'planning and portfolio partition accounts and do not adopt anonymous data',
    () async {
      final anonymous = PlanningRepository();
      await anonymous.load();
      await anonymous.saveSchoolContext(school: '기존 익명 학교');
      LocalDataOwner.currentUserId = userId;
      final first = PlanningRepository();
      final portfolio = PortfolioWorkspaceRepository();
      final firstRecords = PersonalRecordRepository(
        PersonalRecordKind.experience,
      );
      await firstRecords.load();
      await firstRecords.save(
        PersonalRecord(id: 'first-experience', values: {'title': 'A 경험'}),
      );
      await first.load();
      expect(first.profile.school, isEmpty);
      await first.saveSchoolContext(school: 'A 학교');
      LocalDataOwner.currentUserId = otherId;
      final second = PlanningRepository();
      final secondRecords = PersonalRecordRepository(
        PersonalRecordKind.experience,
      );
      await secondRecords.load();
      await secondRecords.save(
        PersonalRecord(id: 'second-experience', values: {'title': 'B 경험'}),
      );
      await second.load();
      expect(second.profile.school, isEmpty);
      await first.saveSchoolContext(school: 'A 변경');
      await second.load();
      expect(second.profile.school, isEmpty);
      await portfolio.load();
      expect(portfolio.sources.keys, contains('experience/first-experience'));
      expect(
        portfolio.sources.keys,
        isNot(contains('experience/second-experience')),
      );
      anonymous.dispose();
      first.dispose();
      second.dispose();
    },
  );
}
