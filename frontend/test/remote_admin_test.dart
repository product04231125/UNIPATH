import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/features/admin/admin_models.dart';
import 'package:university_path_frontend/features/admin/admin_editor.dart';
import 'package:university_path_frontend/features/admin/admin_workspace.dart';
import 'package:university_path_frontend/features/admin/remote_admin_repository.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/auth/login_page.dart';

import 'support/auth_fixture.dart';

const schoolId = '00000000-0000-4000-8000-000000000010';
const newId = '00000000-0000-4000-8000-000000000011';
const courseId = '00000000-0000-4000-8000-000000000012';

class AdminServer {
  final requests = <http.Request>[];
  final data = <String, List<Map<String, dynamic>>>{};
  bool rejectCourses = false;
  bool failRefreshAfterSave = false;
  bool paginate = false;
  bool loggedOut = false;
  bool saved = false;
  Map<String, dynamic> row(String id, String name) => {
    'id': id,
    'name': name,
    'version': 1,
    'institution_id': schoolId,
    'created_by': userId,
    'updated_by': userId,
    'created_at': '2026-10-18T00:00:00Z',
    'updated_at': '2026-10-18T00:00:00Z',
  };
  AdminServer() {
    data['institutions'] = [row(schoolId, '합성 학교')];
    data['courses'] = [
      {...row(courseId, '설계'), 'code': 'CS1', 'credits': '3.0'},
    ];
    data['users'] = [
      Map<String, dynamic>.from(
        identityJson(role: 'super_admin')['user']! as Map,
      ),
    ];
  }
  http.Response respond(http.Request request) {
    requests.add(request);
    final path = request.url.path;
    http.Response json(Object value, [int status = 200]) => http.Response(
      jsonEncode(value),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    if (path.endsWith('/auth/login')) {
      return json({
        ...identityJson(role: 'super_admin'),
        'access_token': token,
      });
    }
    expect(request.headers['Authorization'], 'Bearer $token');
    if (path.endsWith('/auth/logout')) {
      loggedOut = true;
      return http.Response('', 204);
    }
    if (path.endsWith('/auth/me')) {
      return json(identityJson(role: 'super_admin'));
    }
    final parts = path.split('/').skip(4).toList();
    final resource = parts.first;
    if (rejectCourses && resource == 'courses') return json({}, 403);
    if (request.method == 'GET') {
      if (failRefreshAfterSave && saved) return json({}, 503);
      if (parts.length > 1 && parts.last == 'references') {
        return json({'items': [], 'total': 0});
      }
      if (paginate && resource == 'institutions') {
        return json({
          'items': request.url.queryParameters['cursor'] == null
              ? [row(schoolId, '첫 학교')]
              : [row(newId, '두 번째 학교')],
          'next_cursor': request.url.queryParameters['cursor'] == null
              ? schoolId
              : null,
        });
      }
      return json({'items': data[resource] ?? [], 'next_cursor': null});
    }
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    if (request.method == 'POST') {
      final result = {...row(newId, body['name'] as String? ?? '생성'), ...body};
      (data[resource] ??= []).add(result);
      saved = true;
      return json(result, 201);
    }
    if (request.method == 'PATCH' && resource == 'users') {
      expect(parts.last, 'access');
      final result = {...data['users']!.first, ...body, 'version': 2};
      data['users'] = [result];
      return json(result);
    }
    return json({}, 409);
  }
}

Future<(AuthApi, RemoteAdminRepository)> connected(AdminServer server) async {
  final api = AuthApi(
    client: MockClient((request) async => server.respond(request)),
    cookieMode: false,
  );
  final identity = await api.authenticate(
    email: 'operator@example.test',
    password: 'synthetic long password',
  );
  final repo = RemoteAdminRepository(identity, auth: api, api: api);
  await repo.load();
  return (api, repo);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('remote catalog shares native session and sends typed payloads without owner fields', () async {
    final server = AdminServer();
    final (api, repo) = await connected(server);
    expect(
      repo.records
          .where((r) => r.kind == AdminKind.course)
          .single
          .value('credits'),
      '3.0',
    );
    await repo.save(
      userId,
      AdminRecord(
        id: 'temporary',
        kind: AdminKind.course,
        values: {
          'name': '새 과목',
          'institutionId': schoolId,
          'code': 'CS2',
          'credits': '2.5',
        },
      ),
    );
    final request = server.requests.singleWhere(
      (r) => r.method == 'POST' && r.url.path.endsWith('/courses'),
    );
    expect(jsonDecode(request.body), {
      'name': '새 과목',
      'institution_id': schoolId,
      'code': 'CS2',
      'credits': '2.5',
    });
    expect(repo.records.any((r) => r.id == newId), isTrue);
    repo.dispose();
    api.close();
  });
  test(
    'all pages are loaded and school membership is retained in view records',
    () async {
      final server = AdminServer()..paginate = true;
      server.data['curricula'] = [
        {
          ...server.row(newId, '2026 과정'),
          'department_id': courseId,
          'year': 2026,
        },
      ];
      final (api, repo) = await connected(server);
      expect(
        repo.records.where((r) => r.kind == AdminKind.institution).length,
        2,
      );
      expect(
        repo.school(
          repo.records.firstWhere((r) => r.kind == AdminKind.curriculum),
        ),
        schoolId,
      );
      expect(
        server.requests
            .where((r) => r.url.queryParameters['cursor'] == schoolId)
            .length,
        1,
      );
      repo.dispose();
      api.close();
    },
  );
  test('access changes use one versioned request and scope editor offers school-level fields only', () async {
    final server = AdminServer();
    final (api, repo) = await connected(server);
    await repo.save(
      userId,
      repo.records
          .firstWhere((r) => r.kind == AdminKind.account)
          .copy(values: {'role': 'school_admin', 'accountStatus': 'suspended'}),
    );
    final change = server.requests.singleWhere((r) => r.method == 'PATCH');
    expect(change.url.path.endsWith('/users/$userId/access'), isTrue);
    expect(jsonDecode(change.body), {
      'role': 'school_admin',
      'account_status': 'suspended',
      'expected_version': 1,
    });
    expect(repo.fields(AdminKind.scope).map((f) => f.key), [
      'institutionId',
      'userId',
      'reason',
    ]);
    repo.dispose();
    api.close();
  });
  test(
    'curriculum and course links send the selected school with typed fields',
    () async {
      final server = AdminServer();
      final (api, repo) = await connected(server);
      await repo.save(
        userId,
        AdminRecord(
          id: 'temporary',
          kind: AdminKind.curriculum,
          values: {
            'name': '2026 과정',
            'institutionId': schoolId,
            'departmentId': courseId,
            'year': '2026',
          },
        ),
      );
      final request = server.requests.singleWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/curricula'),
      );
      expect(jsonDecode(request.body), {
        'name': '2026 과정',
        'institution_id': schoolId,
        'department_id': courseId,
        'year': 2026,
      });
      await repo.save(
        userId,
        AdminRecord(
          id: 'temporary-link',
          kind: AdminKind.curriculumCourse,
          values: {
            'name': '필수 과목',
            'institutionId': schoolId,
            'curriculumId': newId,
            'courseId': courseId,
            'category': 'major',
            'required': 'true',
          },
        ),
      );
      final link = server.requests.singleWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/curriculum-courses'),
      );
      final body = jsonDecode(link.body) as Map;
      expect(body['institution_id'], schoolId);
      expect(body['required'], isTrue);
      repo.dispose();
      api.close();
    },
  );

  test('permission failure clears cached privileged records', () async {
    final server = AdminServer();
    final (api, repo) = await connected(server);
    server.rejectCourses = true;
    await expectLater(repo.load(), throwsStateError);
    expect(repo.records, isEmpty);
    expect(repo.history, isEmpty);
    repo.dispose();
    api.close();
  });
  test(
    'successful save is not repeated when the following refresh fails',
    () async {
      final server = AdminServer();
      final (api, repo) = await connected(server);
      server.failRefreshAfterSave = true;
      await repo.save(
        userId,
        AdminRecord(
          id: 'temporary',
          kind: AdminKind.institution,
          values: {'name': '저장된 학교'},
        ),
      );
      expect(
        server.requests
            .where(
              (r) => r.method == 'POST' && r.url.path.endsWith('/institutions'),
            )
            .length,
        1,
      );
      expect(repo.records.any((r) => r.id == newId), isTrue);
      expect(repo.warning, isNotNull);
      repo.dispose();
      api.close();
    },
  );
  for (final size in [const Size(1440, 900), const Size(480, 520)]) {
    testWidgets(
      'live admin creates a school and performs server logout at $size',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final server = AdminServer();
        final api = AuthApi(
          client: MockClient((request) async => server.respond(request)),
          cookieMode: false,
        );
        await api.authenticate(
          email: 'operator@example.test',
          password: 'synthetic long password',
        );
        await tester.pumpWidget(UniversityPathApp(authGateway: api));
        await tester.pumpAndSettle();
        expect(find.byType(AdminWorkspace), findsOneWidget);
        expect(find.text('합성 대학 A'), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('admin-menu-/admin/schools')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.widgetWithText(FilledButton, '학교 등록'));
        await tester.tap(find.widgetWithText(FilledButton, '학교 등록'));
        await tester.pumpAndSettle();
        final schoolForm = find.byWidgetPredicate(
          (widget) =>
              widget is AdminEditor && widget.kind == AdminKind.institution,
        );
        final nameField = find.descendant(
          of: schoolForm,
          matching: find.byKey(const ValueKey('admin-field-name')),
        );
        await tester.ensureVisible(nameField);
        await tester.enterText(nameField, '등록할 학교');
        final register = find.descendant(
          of: schoolForm,
          matching: find.widgetWithText(FilledButton, '등록'),
        );
        await tester.ensureVisible(register);
        await tester.tap(register);
        await tester.pumpAndSettle();
        expect(
          server.data['institutions']!.any((row) => row['name'] == '등록할 학교'),
          isTrue,
        );
        expect(server.saved, isTrue);
        await tester.ensureVisible(nameField);
        await tester.enterText(nameField, '아직 저장하지 않은 학교');
        final guardedLogout = find.byTooltip('로그아웃');
        final logoutAction = guardedLogout.evaluate().isNotEmpty
            ? guardedLogout
            : find.text('로그아웃');
        await tester.ensureVisible(logoutAction);
        await tester.tap(logoutAction);
        await tester.pumpAndSettle();
        expect(find.text('작성한 내용을 폐기할까요?'), findsOneWidget);
        expect(server.loggedOut, isFalse);
        await tester.tap(find.text('계속 작성'));
        await tester.pumpAndSettle();
        expect(find.text('아직 저장하지 않은 학교'), findsOneWidget);
        await tester.ensureVisible(nameField);
        await tester.enterText(nameField, '');
        await tester.pumpAndSettle();
        final logout = find.byTooltip('로그아웃');
        if (logout.evaluate().isNotEmpty) {
          await tester.ensureVisible(logout);
          await tester.tap(logout);
        } else {
          await tester.ensureVisible(find.text('로그아웃'));
          await tester.tap(find.text('로그아웃'));
        }
        await tester.pumpAndSettle();
        expect(server.loggedOut, isTrue);
        expect(find.byType(LoginPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        api.close();
      },
    );
  }
}
