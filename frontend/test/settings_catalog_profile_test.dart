import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/features/planning/remote_planning_repository.dart';
import 'package:university_path_frontend/features/settings/settings_page.dart';

import 'support/auth_fixture.dart';

class SettingsCatalogServer implements ApiGateway {
  final profile = <String, dynamic>{
    'owner_id': userId,
    'version': 0,
    'official': false,
  };

  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    if (path.startsWith('catalog/')) {
      return {
        'items': [_catalogItem(path)],
        'next_cursor': null,
      };
    }
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
    if (path.startsWith('me/events')) {
      return {'items': <Map<String, dynamic>>[], 'next_cursor': null};
    }
    throw StateError('Unexpected route $method $path');
  }

  Map<String, Object?> _catalogItem(String path) {
    final institutions = path.startsWith('catalog/institutions');
    final departments = path.startsWith('catalog/departments');
    return {
      'id': otherId,
      'version': 1,
      'name': institutions
          ? '검증 대학'
          : departments
          ? '검증 학과'
          : '검증 과정',
      'created_at': '2026-10-21T00:00:00Z',
      'updated_at': '2026-10-21T00:00:00Z',
      'institution_id': otherId,
      'department_id': otherId,
      'code': 'synthetic',
      'year': 2026,
    };
  }
}

Future<void> choose(WidgetTester tester, String from, String to) async {
  await tester.ensureVisible(find.text(from));
  await tester.tap(find.text(from));
  await tester.pumpAndSettle();
  await tester.tap(find.text(to).last);
  await tester.pumpAndSettle();
}

Future<void> saveSettings(WidgetTester tester) async {
  final save = find.text('서버에 저장');
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<RemotePlanningRepository> pumpSettings(
    WidgetTester tester,
    SettingsCatalogServer server, {
    StudentApi? api,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final studentApi = api ?? StudentApi(server, ownerId: userId);
    final repository = RemotePlanningRepository(studentApi);
    await repository.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(repository: repository, studentApi: studentApi),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('empty server settings start from registered school catalog', (
    tester,
  ) async {
    final repository = await pumpSettings(tester, SettingsCatalogServer());
    expect(find.textContaining('목록에 없으면 학교를 만들지 않습니다'), findsOneWidget);
    expect(find.text('학교 선택'), findsOneWidget);
    expect(find.text('목록에 없는 학교 직접 입력'), findsNothing);
    repository.dispose();
  });

  testWidgets('catalog school selection stores ids and clearing removes them', (
    tester,
  ) async {
    final server = SettingsCatalogServer();
    final repository = await pumpSettings(tester, server);
    await choose(tester, '학교 선택', '검증 대학');
    await choose(tester, '학과 선택', '검증 학과');
    await choose(tester, '교육과정 선택', '검증 과정 (2026)');
    await saveSettings(tester);
    expect(repository.profile.institutionId, otherId);
    expect(repository.profile.departmentId, otherId);
    expect(repository.profile.curriculumId, otherId);
    expect(repository.profile.school, '검증 대학');
    expect(repository.profile.department, '검증 학과');
    await choose(tester, '검증 대학', '학교 선택');
    await saveSettings(tester);
    expect(repository.profile.school, isEmpty);
    expect(repository.profile.institutionId, isNull);
    expect(repository.profile.departmentId, isNull);
    expect(repository.profile.curriculumId, isNull);
    expect(server.profile['institution_id'], isNull);
    repository.dispose();
  });

  testWidgets('personal school names stay without becoming a catalog school', (
    tester,
  ) async {
    final server = SettingsCatalogServer();
    final studentApi = StudentApi(server, ownerId: userId);
    final repository = RemotePlanningRepository(studentApi);
    await repository.load();
    await repository.saveProfile(
      PlanningProfile(
        school: '미등록 대학',
        department: '미등록 학과',
        version: repository.profile.version,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(repository: repository, studentApi: studentApi),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('개인 기준에서 가져온 학교: 미등록 대학 · 미등록 학과'), findsOneWidget);
    expect(find.text('학교 선택'), findsOneWidget);
    await saveSettings(tester);
    expect(repository.profile.school, '미등록 대학');
    expect(repository.profile.institutionId, isNull);
    repository.dispose();
  });
}
