import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/auth/local_data_owner.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/features/planning/remote_planning_repository.dart';

// Run only against a disposable, synthetic, loopback review API:
// flutter test test/server_planning_http_test.dart \
//   --dart-define=PLANNING_TEST_BASE_URL=http://127.0.0.1:8031
void main() {
  const base = String.fromEnvironment('PLANNING_TEST_BASE_URL');
  test('real Flutter HTTP planning writes, reloads, conflicts, imports, and deletes', () async {
    final uri = Uri.parse(base);
    expect(uri.scheme, 'http');
    expect(['127.0.0.1', 'localhost'], contains(uri.host));
    SharedPreferences.setMockInitialValues({});
    final auth = AuthApi(baseUrl: uri, cookieMode: false);
    addTearDown(auth.close);
    final user = await auth.authenticate(
      email: 'planning-${planningClientId()}@example.test',
      password: 'synthetic planning password 2026',
      displayName: '합성 HTTP 검증',
    );
    final api = StudentApi(auth.forOwner(user.id), ownerId: user.id);
    final first = RemotePlanningRepository(api);
    addTearDown(first.dispose);
    await first.load();
    expect(first.loadFailed, isFalse);
    await first.saveProfile(
      PlanningProfile(school: '합성 HTTP 학교', version: first.profile.version),
    );
    final event = PlanningEvent(
      id: planningClientId(),
      title: '합성 HTTP 일정',
      start: DateTime.parse('2026-10-19T09:00:00+09:00'),
      end: DateTime.parse('2026-10-19T10:00:00+09:00'),
      category: PlanningEventCategory.personal,
    );
    await first.saveEvent(event);
    final saved = first.events.single;
    final second = RemotePlanningRepository(api);
    addTearDown(second.dispose);
    await second.load();
    expect(second.loadFailed, isFalse);
    expect(second.profile.school, '합성 HTTP 학교');
    expect(second.events.single.id, saved.id);
    expect(second.events.single.start.toUtc(), DateTime.utc(2026, 10, 19));
    await second.saveEvent(
      PlanningEvent(
        id: saved.id,
        version: saved.version,
        title: '수정된 합성 일정',
        start: saved.start,
        end: saved.end,
        category: saved.category,
      ),
    );
    await expectLater(
      first.deleteEvent(saved.id, expectedVersion: saved.version),
      throwsA(isA<AuthFailure>().having((e) => e.status, 'status', 409)),
    );
    final local = PlanningRepository(owner: LocalDataOwner(user.id));
    addTearDown(local.dispose);
    await local.load();
    await local.saveEvent(event);
    await second.load();
    expect(second.canImportLocalPlanning, isTrue);
    await second.importLocalPlanning(confirmed: true);
    expect(second.loadFailed, isFalse);
    expect(second.events, hasLength(2));
    expect(second.canImportLocalPlanning, isFalse);
    final original = PlanningRepository(owner: LocalDataOwner(user.id));
    addTearDown(original.dispose);
    await original.load();
    expect(original.events.single.title, event.title);
    for (final current in second.events) {
      await second.deleteEvent(current.id, expectedVersion: current.version);
    }
    await first.load();
    expect(first.events, isEmpty);
    await auth.logout();
    await expectLater(api.profile(), throwsA(isA<AuthFailure>()));
  }, skip: base.isEmpty);
}
