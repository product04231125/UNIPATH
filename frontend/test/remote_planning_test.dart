import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/auth/local_data_owner.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/features/planning/remote_planning_repository.dart';
import 'package:university_path_frontend/features/settings/settings_page.dart';
import 'package:university_path_frontend/features/schedule/schedule_page.dart';

import 'support/auth_fixture.dart';

const serverId = '10000000-0000-4000-8000-000000000001';

class PlanningServer implements ApiGateway {
  final profile = <String, dynamic>{
    'owner_id': userId,
    'version': 0,
    'official': false,
  };
  final events = <String, Map<String, dynamic>>{};
  final calls = <(String, String, Map<String, Object?>?)>[];
  bool failReads = false,
      loseCreateResponse = false,
      loseImportResponse = false;
  Map<String, dynamic>? importReceipt;
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    calls.add((method, path, body));
    if (method == 'GET' && failReads) throw const AuthFailure('연결 실패');
    if (path == 'me/planning-profile') {
      if (method == 'PATCH') {
        if (body!['expected_version'] != profile['version']) {
          throw const AuthFailure('다른 변경이 있습니다.', status: 409);
        }
        profile.addAll(body);
        profile['version'] = (profile['version'] as int) + 1;
      }
      return {...profile};
    }
    if (path.startsWith('me/events?')) {
      return {'items': events.values.toList(), 'next_cursor': null};
    }
    if (path == 'me/events' && method == 'POST') {
      final existing = events.values.where(
        (v) => v['client_id'] == body!['client_id'],
      );
      final saved = existing.isNotEmpty
          ? existing.first
          : {
              ...body!,
              'id': serverId,
              'owner_id': userId,
              'version': 1,
              'created_at': '2026-10-19T00:00:00Z',
              'updated_at': '2026-10-19T00:00:00Z',
              'origin': 'personal',
              'official': false,
            };
      events[serverId] = saved;
      if (loseCreateResponse) {
        loseCreateResponse = false;
        throw const AuthFailure('연결 실패');
      }
      return {...saved};
    }
    if (path.startsWith('me/events/$serverId')) {
      final saved = events[serverId]!;
      final expected = method == 'DELETE'
          ? int.parse(Uri.parse(path).queryParameters['expected_version']!)
          : body!['expected_version'];
      if (expected != saved['version']) {
        throw const AuthFailure('다른 변경이 있습니다.', status: 409);
      }
      if (method == 'DELETE') {
        events.remove(serverId);
        return null;
      }
      saved.addAll(body!);
      saved['version'] = (saved['version'] as int) + 1;
      return {...saved};
    }
    if (path == 'me/personal-imports') {
      importReceipt ??= {
        'import_id': body!['import_id'],
        'owner_id': userId,
        'record_count': (body['events'] as List).length,
        'profile_version_at_import': body['profile'] == null ? null : 1,
        'replayed': false,
        'committed_at': '2026-10-19T00:00:00Z',
        'origin': 'personal',
        'official': false,
        'mappings': [
          for (final event in body['events'] as List)
            {
              'resource': 'events',
              'client_id': event['client_id'],
              'record_id': serverId,
              'version_at_import': 1,
              'outcome': 'created',
            },
        ],
      };
      if (loseImportResponse) {
        loseImportResponse = false;
        throw const AuthFailure('연결 실패');
      }
      return importReceipt;
    }
    throw StateError('Unexpected route $method $path');
  }
}

RemotePlanningRepository repo(PlanningServer server) =>
    RemotePlanningRepository(StudentApi(server, ownerId: userId));
PlanningEvent event({
  String title = '합성 일정',
  String id = 'local-op',
  int? version,
}) => PlanningEvent(
  id: id,
  title: title,
  start: DateTime.parse('2026-10-19T09:00:00+09:00'),
  end: DateTime.parse('2026-10-19T10:00:00+09:00'),
  category: PlanningEventCategory.academic,
  version: version,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalDataOwner.currentUserId = null;
  });
  test('server profile and events survive a fresh repository, with versions and UTC instants', () async {
    final server = PlanningServer();
    final first = repo(server);
    await first.load();
    await first.saveProfile(
      PlanningProfile(school: '서버 합성 학교', version: first.profile.version),
    );
    await first.saveEvent(event());
    final second = repo(server);
    await second.load();
    expect(second.profile.school, '서버 합성 학교');
    expect(second.profile.version, 1);
    expect(second.events.single.start.toUtc(), DateTime.utc(2026, 10, 19));
    final saved = second.events.single;
    await second.saveEvent(
      event(id: saved.id, version: saved.version, title: '수정'),
    );
    expect(second.events.single.version, 2);
    await expectLater(
      first.deleteEvent(saved.id, expectedVersion: 1),
      throwsA(isA<AuthFailure>()),
    );
    expect(server.events, hasLength(1));
    await second.deleteEvent(saved.id, expectedVersion: 2);
    expect(server.events, isEmpty);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    first.dispose();
    second.dispose();
  });
  test('uncertain event create retries same client UUID, and rejects changed payload', () async {
    final server = PlanningServer()..loseCreateResponse = true;
    final repository = repo(server);
    await repository.load();
    await expectLater(
      repository.saveEvent(event()),
      throwsA(isA<AuthFailure>()),
    );
    expect(repository.events, isEmpty);
    await expectLater(
      repository.saveEvent(event(title: '변경')),
      throwsA(isA<AuthFailure>()),
    );
    await repository.saveEvent(event());
    final creates = server.calls.where((c) => c.$1 == 'POST').toList();
    expect(creates, hasLength(2));
    expect(creates[0].$3, creates[1].$3);
    expect(server.events, hasLength(1));
    repository.dispose();
  });
  test(
    'read failure prevents writes and preserves previous visible state',
    () async {
      final server = PlanningServer();
      final repository = repo(server);
      await repository.load();
      await repository.saveEvent(event());
      server.failReads = true;
      await repository.load();
      expect(repository.loadFailed, isTrue);
      expect(repository.events, hasLength(1));
      await expectLater(repository.saveEvent(event()), throwsStateError);
      server.failReads = false;
      await repository.load();
      expect(repository.loadFailed, isFalse);
      repository.dispose();
    },
  );
  test('import requires consent, keeps originals, and resumes identical journal after restart', () async {
    final local = PlanningRepository(owner: const LocalDataOwner(userId));
    await local.load();
    await local.saveProfile(const PlanningProfile(school: '기기 합성 학교'));
    await local.saveEvent(event());
    final preferences = await SharedPreferences.getInstance();
    final key = const LocalDataOwner(userId)
        .key('university_path.personal_planning.v1');
    final original = preferences.getString(key);
    final server = PlanningServer()..loseImportResponse = true;
    final first = repo(server);
    await first.load();
    expect(first.canImportLocalPlanning, isTrue);
    expect(server.calls.any((c) => c.$1 != 'GET'), isFalse);
    await expectLater(
      first.importLocalPlanning(confirmed: false),
      throwsStateError,
    );
    await expectLater(
      first.importLocalPlanning(confirmed: true),
      throwsA(isA<AuthFailure>()),
    );
    first.dispose();
    await local.saveEvent(event(title: '로컬 후속 수정'));
    final latestOriginal = preferences.getString(key);
    expect(latestOriginal, isNot(original));
    final retry = repo(server);
    await retry.load();
    expect(retry.localPlanningPreview.join(), contains('합성 일정'));
    expect(retry.localPlanningPreview.join(), isNot(contains('로컬 후속 수정')));
    await retry.importLocalPlanning(confirmed: true);
    final imports = server.calls
        .where((c) => c.$2 == 'me/personal-imports')
        .toList();
    expect(imports, hasLength(2));
    expect(imports[0].$3, imports[1].$3);
    expect(imports[0].$3!['profile'], containsPair('school', '기기 합성 학교'));
    expect(retry.canImportLocalPlanning, isFalse);
    expect(preferences.getString(key), latestOriginal);
    local.dispose();
    retry.dispose();
  });
  test('existing server profile is omitted from import; anonymous data is never attributed', () async {
    final anonymous = PlanningRepository();
    await anonymous.load();
    await anonymous.saveEvent(event());
    final server = PlanningServer()
      ..profile.addAll({'school': '서버', 'version': 2});
    final repository = repo(server);
    await repository.load();
    expect(repository.canImportLocalPlanning, isFalse);
    final local = PlanningRepository(owner: const LocalDataOwner(userId));
    await local.load();
    await local.saveProfile(const PlanningProfile(school: '기기'));
    await local.saveEvent(event());
    await repository.load();
    await repository.importLocalPlanning(confirmed: true);
    expect(
      server.calls.lastWhere((c) => c.$1 == 'POST').$3!['profile'],
      isNull,
    );
    expect(repository.profile.school, '서버');
    local.dispose();
    anonymous.dispose();
    repository.dispose();
  });
  test('invalid import journal disables import without blocking server planning or overwriting local data', () async {
    final preferences = await SharedPreferences.getInstance();
    final key = const LocalDataOwner(userId)
        .key('university_path.planning_import.v1');
    const corrupted = '{"completed":false,"request":{}}';
    await preferences.setString(key, corrupted);
    final server = PlanningServer();
    final repository = repo(server);
    await repository.load();
    expect(repository.loadFailed, isFalse);
    expect(repository.canImportLocalPlanning, isFalse);
    expect(repository.localPlanningNotice, contains('기기 자료를 확인하지 못했습니다'));
    expect(preferences.getString(key), corrupted);
    await repository.saveEvent(event());
    expect(server.events, hasLength(1));
    repository.dispose();
  });
  test('old bound native and browser gateways stop before sending after account switch', () async {
    for (final cookie in [false, true]) {
      var current = userId;
      var writes = 0;
      final auth = AuthApi(
        cookieMode: cookie,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login') ||
              request.url.path.endsWith('/me')) {
            return http.Response(
              jsonEncode({...identityJson(id: current), 'access_token': token}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          writes++;
          expect(request.headers['X-Unipath-Owner'], userId);
          return http.Response('{}', 200);
        }),
      );
      await auth.authenticate(
        email: 'synthetic@example.test',
        password: 'synthetic password',
      );
      final bound = auth.forOwner(userId);
      await bound.request('PATCH', 'me/planning-profile', {});
      current = otherId;
      await auth.me();
      await expectLater(
        bound.request('PATCH', 'me/planning-profile', {}),
        throwsA(isA<AuthFailure>()),
      );
      expect(writes, 1);
      auth.close();
    }
  });
  test('a late response from old workspace is not delivered after reauthentication', () async {
    final response = Completer<http.Response>();
    final sent = Completer<void>();
    final auth = AuthApi(
      cookieMode: false,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return http.Response(
            jsonEncode({...identityJson(), 'access_token': token}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        sent.complete();
        return response.future;
      }),
    );
    await auth.authenticate(
      email: 'synthetic@example.test',
      password: 'synthetic password',
    );
    final bound = auth.forOwner(userId);
    final pending = bound.request('GET', 'me/planning-profile');
    await sent.future;
    await auth.authenticate(
      email: 'synthetic@example.test',
      password: 'synthetic password',
    );
    final assertion = expectLater(pending, throwsA(isA<AuthFailure>()));
    response.complete(http.Response('{}', 200));
    await assertion;
    auth.close();
  });
  testWidgets(
    'server settings and schedule work at narrow width, with explicit import consent',
    (tester) async {
      final local = PlanningRepository(owner: const LocalDataOwner(userId));
      await local.load();
      await local.saveEvent(event());
      final server = PlanningServer();
      final repository = repo(server);
      await repository.load();
      await tester.binding.setSurfaceSize(const Size(480, 520));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SettingsPage(repository: repository)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('기기 학업 정보·일정 이전'));
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(FilledButton, '동의하고 이전');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await Scrollable.ensureVisible(
        tester.element(find.byType(Checkbox)),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(server.importReceipt, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SchedulePage(repository: repository)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('계정 서버 저장'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      local.dispose();
      repository.dispose();
    },
  );
}
