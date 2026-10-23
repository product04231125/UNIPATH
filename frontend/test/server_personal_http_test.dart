import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/personal_workspace_importer.dart';
import 'package:university_path_frontend/features/records/remote_personal_record_repository.dart';
import 'package:university_path_frontend/features/records/portfolio/portfolio_workspace_repository.dart';
import 'package:university_path_frontend/features/records/portfolio/remote_portfolio_workspace_repository.dart';
import 'package:university_path_frontend/features/planning/remote_planning_repository.dart';

import 'support/personal_workspace_fixture.dart';

// Disposable synthetic loopback API only. Normal CI skips these two tests.
// flutter test test/server_personal_http_test.dart \
//   --dart-define=PERSONAL_TEST_BASE_URL=http://127.0.0.1:8037
class LoseImportResponse implements ApiGateway {
  LoseImportResponse(this.inner);
  final ApiGateway inner;
  bool lose = true;
  final imports = <Map<String, Object?>>[];
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    if (method == 'POST' && path == 'me/personal-imports') imports.add(body!);
    final result = await inner.request(method, path, body);
    if (method == 'POST' && path == 'me/personal-imports' && lose) {
      lose = false;
      throw const AuthFailure('Synthetic lost response');
    }
    return result;
  }
}

void main() {
  const base = String.fromEnvironment('PERSONAL_TEST_BASE_URL');
  Future<(AuthApi, StudentApi)> connect() async {
    final uri = Uri.parse(base);
    expect(uri.scheme, 'http');
    expect(['127.0.0.1', 'localhost'], contains(uri.host));
    SharedPreferences.setMockInitialValues({});
    final auth = AuthApi(baseUrl: uri, cookieMode: false);
    addTearDown(auth.close);
    final identity = await auth.authenticate(
      email: 'personal-${planningClientId()}@example.test',
      password: 'synthetic personal password 2026',
      displayName: '합성 개인 HTTP 검증',
    );
    return (auth, StudentApi(auth.forOwner(identity.id), ownerId: identity.id));
  }

  test('real HTTP all eight record types and portfolio retain relationships, versions and source order', () async {
    final (auth, api) = await connect();
    final repositories = <PersonalRecordKind, RemotePersonalRecordRepository>{};
    final ids = <PersonalRecordKind, String>{};
    for (final kind in [
      PersonalRecordKind.course,
      PersonalRecordKind.activity,
      PersonalRecordKind.experience,
      PersonalRecordKind.credential,
      PersonalRecordKind.portfolio,
      PersonalRecordKind.personalCurriculum,
      PersonalRecordKind.personalCurriculumCourse,
      PersonalRecordKind.personalGraduationRule,
    ]) {
      final repository = RemotePersonalRecordRepository(
        api,
        kind,
        ensureOpen: () {},
      );
      await repository.load();
      expect(repository.records, isEmpty);
      final values = fixtureValues(kind);
      if (kind == PersonalRecordKind.personalCurriculumCourse ||
          kind == PersonalRecordKind.personalGraduationRule) {
        values['curriculumId'] = ids[PersonalRecordKind.personalCurriculum]!;
      }
      if (kind == PersonalRecordKind.personalCurriculumCourse) {
        values['courseRecordId'] = ids[PersonalRecordKind.course]!;
      }
      if (kind == PersonalRecordKind.personalGraduationRule) {
        values['curriculumCourseId'] =
            ids[PersonalRecordKind.personalCurriculumCourse]!;
        values['relatedRecord'] =
            'portfolio/${ids[PersonalRecordKind.portfolio]}';
      }
      await repository.save(
        PersonalRecord(id: fixtureId(kind), values: values),
      );
      final saved = repository.records.single;
      ids[kind] = saved.id;
      repositories[kind] = repository;
      expect(saved.version, 1);
      expect(saved.values, values);
      final fresh = RemotePersonalRecordRepository(
        api,
        kind,
        ensureOpen: () {},
      );
      await fresh.load();
      expect(fresh.records.single.values, values);
      await repository.save(
        PersonalRecord(
          id: saved.id,
          version: saved.version,
          values: {...values, 'detail': '수정된 합성 메모'},
        ),
      );
      expect(repository.records.single.version, 2);
      await expectLater(
        fresh.delete(saved.id, expectedVersion: 1),
        throwsA(isA<AuthFailure>().having((e) => e.status, 'status', 409)),
      );
    }
    final course = repositories[PersonalRecordKind.course]!;
    await course.load();
    await expectLater(
      course.delete(
        course.records.single.id,
        expectedVersion: course.records.single.version,
      ),
      throwsA(isA<AuthFailure>().having((e) => e.status, 'status', 409)),
    );
    final portfolio = RemotePortfolioWorkspaceRepository(
      api,
      ensureOpen: () {},
    );
    await portfolio.load();
    final achievement = 'portfolio/${ids[PersonalRecordKind.portfolio]}';
    final experience = 'experience/${ids[PersonalRecordKind.experience]}';
    await portfolio.saveComposition(
      PortfolioComposition(
        id: compositionId,
        title: 'HTTP 구성',
        sources: [achievement],
      ),
    );
    await portfolio.saveDocument(
      ApplicationDocument(
        id: documentId,
        title: 'HTTP 지원 문서',
        target: '합성 지원처',
        role: '개발',
        type: '이력서',
        body: '합성 본문',
        sources: [experience, achievement],
      ),
    );
    final fresh = RemotePortfolioWorkspaceRepository(api, ensureOpen: () {});
    await fresh.load();
    expect(fresh.compositions.single.sources, [achievement]);
    expect(fresh.documents.single.sources, [experience, achievement]);
    expect(fresh.sources.keys, containsAll([experience, achievement]));
    final document = fresh.documents.single;
    await portfolio.saveDocument(
      ApplicationDocument(
        id: document.id,
        version: document.version,
        title: document.title,
        target: document.target,
        role: document.role,
        type: document.type,
        body: '수정된 합성 본문',
        sources: [achievement, experience],
      ),
    );
    await expectLater(
      fresh.deleteDocument(document.id, expectedVersion: document.version),
      throwsA(isA<AuthFailure>().having((e) => e.status, 'status', 409)),
    );
    await portfolio.load();
    expect(portfolio.documents.single.sources, [achievement, experience]);
    await portfolio.deleteDocument(
      portfolio.documents.single.id,
      expectedVersion: portfolio.documents.single.version,
    );
    await portfolio.deleteComposition(
      portfolio.compositions.single.id,
      expectedVersion: portfolio.compositions.single.version,
    );
    for (final kind in [
      PersonalRecordKind.personalGraduationRule,
      PersonalRecordKind.personalCurriculumCourse,
      PersonalRecordKind.personalCurriculum,
      PersonalRecordKind.course,
      PersonalRecordKind.activity,
      PersonalRecordKind.experience,
      PersonalRecordKind.credential,
      PersonalRecordKind.portfolio,
    ]) {
      final repository = repositories[kind]!;
      await repository.load();
      await repository.delete(
        repository.records.single.id,
        expectedVersion: repository.records.single.version,
      );
      await repository.load();
      expect(repository.records, isEmpty);
    }
    await auth.logout();
  }, skip: base.isEmpty);
  test('real atomic migration of ten linked collections resumes after lost receipt and keeps originals', () async {
    final (auth, api) = await connect();
    await seedLocalWorkspace(api.ownerId);
    final preferences = await SharedPreferences.getInstance();
    final originals = {
      for (final key in preferences.getKeys()) key: preferences.getString(key),
    };
    final flaky = LoseImportResponse(api.api);
    final migrationApi = StudentApi(flaky, ownerId: api.ownerId);
    final first = PersonalWorkspaceImporter(migrationApi, ensureOpen: () {});
    await first.load();
    expect(first.failed, isFalse);
    expect(first.issue, isNull);
    expect(first.count, 10);
    expect(flaky.imports, isEmpty);
    await expectLater(
      first.importRecords(confirmed: false, snapshotId: first.snapshotId!),
      throwsStateError,
    );
    await expectLater(
      first.importRecords(confirmed: true, snapshotId: first.snapshotId!),
      throwsA(isA<AuthFailure>()),
    );
    first.dispose();
    final resumed = PersonalWorkspaceImporter(migrationApi, ensureOpen: () {});
    addTearDown(resumed.dispose);
    await resumed.load();
    await resumed.importRecords(
      confirmed: true,
      snapshotId: resumed.snapshotId!,
    );
    expect(flaky.imports, hasLength(2));
    expect(flaky.imports[0], flaky.imports[1]);
    expect(resumed.completed, isTrue);
    expect(resumed.canImport, isFalse);
    expect(flaky.imports[0]['profile'], isNull);
    expect(flaky.imports[0]['events'], isEmpty);
    final ids = <PersonalRecordKind, String>{};
    final repositories = <PersonalRecordKind, RemotePersonalRecordRepository>{};
    for (final kind in PersonalRecordKind.values.where(
      (kind) => kind.hasServerContract,
    )) {
      final repository = RemotePersonalRecordRepository(
        api,
        kind,
        ensureOpen: () {},
      );
      await repository.load();
      expect(repository.records, hasLength(1));
      ids[kind] = repository.records.single.id;
      repositories[kind] = repository;
    }
    expect(
      repositories[PersonalRecordKind.personalCurriculumCourse]!.records.single
          .value('curriculumId'),
      ids[PersonalRecordKind.personalCurriculum],
    );
    expect(
      repositories[PersonalRecordKind.personalCurriculumCourse]!.records.single
          .value('courseRecordId'),
      ids[PersonalRecordKind.course],
    );
    expect(
      repositories[PersonalRecordKind.personalGraduationRule]!.records.single
          .value('curriculumCourseId'),
      ids[PersonalRecordKind.personalCurriculumCourse],
    );
    expect(
      repositories[PersonalRecordKind.personalGraduationRule]!.records.single
          .value('relatedRecord'),
      'portfolio/${ids[PersonalRecordKind.portfolio]}',
    );
    final portfolio = RemotePortfolioWorkspaceRepository(
      api,
      ensureOpen: () {},
    );
    await portfolio.load();
    expect(portfolio.compositions, hasLength(1));
    expect(portfolio.documents, hasLength(1));
    expect(portfolio.documents.single.sources, [
      'experience/${ids[PersonalRecordKind.experience]}',
      'portfolio/${ids[PersonalRecordKind.portfolio]}',
    ]);
    for (final entry in originals.entries) {
      expect(preferences.getString(entry.key), entry.value);
    }
    await auth.logout();
  }, skip: base.isEmpty);
}
