import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/assistant/assistant_api.dart';
import 'package:university_path_frontend/features/assistant/assistant_conversation.dart';
import 'package:university_path_frontend/features/assistant/assistant_panel.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/auth/local_data_owner.dart';
import 'package:university_path_frontend/features/auth/login_page.dart';
import 'package:university_path_frontend/features/graduation/official_graduation_page.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/features/planning/remote_planning_repository.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/personal_repository_scope.dart';
import 'package:university_path_frontend/features/records/portfolio/remote_portfolio_workspace_repository.dart';
import 'package:university_path_frontend/features/records/remote_personal_record_repository.dart';
import 'package:university_path_frontend/features/settings/settings_page.dart';

import '../assistant_api_test.dart' as assistant;
import '../graduation_api_test.dart' as audit;
import '../support/auth_fixture.dart';

const syntheticName = '합성 학생';
const syntheticEmail = 'synthetic@example.test';
const syntheticPassword = 'synthetic long password';

Finder labeledField(String label) => find.ancestor(
  of: find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  ),
  matching: find.byType(TextFormField),
);

http.Response jsonBody(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class JourneyGateway implements ApiGateway {
  bool emptyCatalog = false;
  bool failWrites = false;
  final profile = <String, dynamic>{
    'owner_id': userId,
    'version': 0,
    'official': false,
  };
  final records = <String, List<Map<String, dynamic>>>{};
  final auditCreates = <Map<String, dynamic>>[];
  Map<String, dynamic>? lastAudit;

  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    if (path.startsWith('catalog/')) {
      if (emptyCatalog) {
        return {'items': <Map<String, dynamic>>[], 'next_cursor': null};
      }
      return {
        'items': [_catalogItem(path)],
        'next_cursor': null,
      };
    }
    if (path == 'me/planning-profile') {
      if (method == 'PATCH') {
        if (failWrites) {
          throw const AuthFailure('다른 변경이 있습니다.', status: 409);
        }
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
    if (path.startsWith('me/portfolio-compositions') ||
        path.startsWith('me/application-documents')) {
      return {'items': <Map<String, dynamic>>[], 'next_cursor': null};
    }
    final uri = Uri.parse(path);
    final parts = uri.path.split('/');
    if (parts.length >= 2 && parts.first == 'me') {
      final resource = parts[1];
      final id = parts.length > 2 ? parts[2] : null;
      if (method != 'GET' && failWrites) {
        throw const AuthFailure('다른 변경이 있습니다. 다시 읽어주세요.', status: 409);
      }
      if (method == 'GET' && id == null) {
        return {'items': [...?records[resource]], 'next_cursor': null};
      }
      if (method == 'POST') {
        final row = _recordRow(body!, records[resource]?.length ?? 0);
        records.putIfAbsent(resource, () => []).add(row);
        return row;
      }
      if (id != null) {
        final list = records[resource] ?? [];
        final index = list.indexWhere((row) => row['id'] == id);
        if (index < 0) {
          throw const AuthFailure('기록을 찾지 못했습니다.', status: 404);
        }
        if (method == 'PATCH') {
          final next = {...list[index], ...?body};
          next['version'] = (list[index]['version'] as int) + 1;
          next['updated_at'] = '2026-10-22T00:00:00Z';
          list[index] = next;
          return next;
        }
        if (method == 'DELETE') {
          if (_referenced(resource, id)) {
            throw const AuthFailure('연결된 자료가 있습니다.', status: 409);
          }
          list.removeAt(index);
          return null;
        }
      }
    }
    throw StateError('Unexpected synthetic gateway call $method $path');
  }

  bool _referenced(String resource, String id) {
    final kind = switch (resource) {
      'course-records' => 'course',
      'activity-records' => 'activity',
      'experience-records' => 'experience',
      'credential-records' => 'credential',
      _ => null,
    };
    if (kind == null) return false;
    for (final rule in records['personal-graduation-rules'] ?? []) {
      final related = rule['related_record'];
      if (related is Map &&
          related['kind'] == kind &&
          related['record_id'] == id) {
        return true;
      }
    }
    return false;
  }

  Map<String, dynamic> _recordRow(Map<String, Object?> body, int index) {
    final id =
        (body['client_id'] as String?) ??
        '10000000-0000-4000-8000-${(index + 1).toString().padLeft(12, '0')}';
    return {
      ...body,
      'id': id,
      'owner_id': userId,
      'version': 1,
      'origin': 'personal',
      'official': false,
      'created_at': '2026-10-21T00:00:00Z',
      'updated_at': '2026-10-21T00:00:00Z',
    };
  }

  Map<String, Object?> _catalogItem(String path) {
    final institutions = path.contains('catalog/institutions');
    final departments = path.contains('catalog/departments');
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

enum AuthScript { live, fieldErrors, conflict, loginFail }

class StudentWorld {
  AuthScript script = AuthScript.live;
  final accounts = <String, String>{};
  final captured = <({String email, String password, String? displayName})>[];
  bool signedIn = false;
  late AuthApi authApi;
  JourneyGateway? gateway;
  RemotePlanningRepository? planning;
  AssistantConversation? conversation;
  final chatRequests = <Map<String, dynamic>>[];
  Object? lastAuditStatus;
  Map<String, dynamic>? frozenAudit;
  WeekStartDay? keptWeekStart;
  String? keptTrack;
  String lastQuestion = '사회봉사 조건은?';
  String lastCourseTitle = '합성 수강';
  String lastActivityTitle = '합성 봉사';
  String lastOtherActivityTitle = '합성 그 밖의 활동';
  String lastExperienceTitle = '합성 프로젝트';
  String lastCredentialTitle = '합성 자격';

  StudentWorld() {
    authApi = AuthApi(cookieMode: false, client: MockClient(_handleAuth));
  }

  Future<http.Response> _handleAuth(http.Request request) async {
    final path = request.url.path;
    if (path.contains('/catalog/')) {
      return jsonBody({
        'items': [ensureGateway()._catalogItem(path)],
        'next_cursor': null,
      });
    }
    if (request.method == 'POST' && path.contains('/graduation-audits')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      ensureGateway().auditCreates.add(body);
      final result = {
        ...audit.auditJson(),
        'client_id': body['client_id'],
        'context': body['context'],
        'evaluated_on': body['as_of'],
      };
      lastAuditStatus = result['status'];
      frozenAudit ??= Map<String, dynamic>.from(result);
      gateway?.lastAudit = result;
      return jsonBody(result);
    }
    if (path.contains('/graduation-audits/')) {
      return jsonBody(frozenAudit ?? audit.auditJson());
    }
    if (path.contains('/graduation-audits')) {
      return jsonBody({
        'items': [if (frozenAudit != null) frozenAudit],
        'next_cursor': null,
      });
    }
    if (!path.endsWith('/auth/register') && !path.endsWith('/auth/login')) {
      return jsonBody(identityJson());
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final email = body['email'] as String;
    final passwordValue = body['password'] as String;
    final displayName = body['display_name'] as String?;
    captured.add((
      email: email,
      password: passwordValue,
      displayName: displayName,
    ));
    if (displayName != null) {
      if (script == AuthScript.fieldErrors) {
        return jsonBody({
          'error': {
            'message': 'private-password',
            'field_errors': [
              {'field': 'body.display_name', 'reason': 'too_long'},
              {'field': 'body.email', 'reason': 'invalid'},
              {'field': 'body.password', 'reason': 'too_short'},
            ],
          },
        }, 422);
      }
      if (script == AuthScript.conflict) {
        return jsonBody({
          'error': {'message': 'private-password'},
        }, 409);
      }
      if ((displayName).length > 128 || email.length > 254) {
        return jsonBody({
          'error': {
            'field_errors': [
              if (displayName.length > 128)
                {'field': 'body.display_name', 'reason': 'too_long'},
              if (email.length > 254)
                {'field': 'body.email', 'reason': 'too_long'},
            ],
          },
        }, 422);
      }
      accounts[email] = passwordValue;
      signedIn = true;
      return jsonBody({...identityJson(), 'access_token': token});
    }
    if (script == AuthScript.loginFail ||
        (accounts.containsKey(email) && accounts[email] != passwordValue)) {
      return jsonBody({
        'error': {'message': 'private-password'},
      }, 401);
    }
    signedIn = true;
    return jsonBody({...identityJson(), 'access_token': token});
  }

  Future<void> openSignup(WidgetTester tester, {bool fill = true}) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    signedIn = false;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          key: UniqueKey(),
          onSignedIn: () => signedIn = true,
          authenticate: authApi.authenticate,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('signup-tab')));
    await tester.pumpAndSettle();
    if (fill) await fillSignup(tester);
  }

  Future<void> fillSignup(
    WidgetTester tester, {
    String name = syntheticName,
    String email = syntheticEmail,
    String passwordValue = syntheticPassword,
    String? confirm,
  }) async {
    await tester.enterText(labeledField('이름'), name);
    await tester.enterText(labeledField('이메일 주소'), email);
    await tester.enterText(labeledField('비밀번호'), passwordValue);
    await tester.enterText(labeledField('비밀번호 확인'), confirm ?? passwordValue);
    await tester.pump();
  }

  Future<void> submitSignup(WidgetTester tester) async {
    final button = find.byKey(const Key('signup-submit'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> openLogin(WidgetTester tester) async {
    final login = find.byKey(const Key('login-tab'));
    if (login.evaluate().isNotEmpty) {
      await tester.tap(login);
      await tester.pumpAndSettle();
    }
  }

  Future<void> submitLogin(WidgetTester tester) async {
    final button = find.byKey(const Key('login-submit'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  String fieldText(WidgetTester tester, String label) =>
      tester.widget<TextFormField>(labeledField(label)).controller!.text;

  JourneyGateway ensureGateway() => gateway ??= JourneyGateway();

  Future<RemotePlanningRepository> pumpSettings(
    WidgetTester tester, {
    bool emptyCatalog = false,
  }) async {
    final server = ensureGateway()..emptyCatalog = emptyCatalog;
    LocalDataOwner.currentUserId = userId;
    await tester.binding.setSurfaceSize(const Size(1440, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = StudentApi(server, ownerId: userId);
    final repository = RemotePlanningRepository(api);
    planning?.dispose();
    planning = repository;
    await repository.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(repository: repository, studentApi: api),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  Widget scoped(Widget child) {
    final server = ensureGateway();
    final api = StudentApi(server, ownerId: userId);
    return PersonalRepositoryScope(
      records: (kind) => RemotePersonalRecordRepository(
        api,
        kind,
        ensureOpen: () {},
      ),
      portfolio: () =>
          RemotePortfolioWorkspaceRepository(api, ensureOpen: () {}),
      child: Scaffold(body: child),
    );
  }

  Future<void> pumpMenu(WidgetTester tester, Widget page) async {
    LocalDataOwner.currentUserId = userId;
    await tester.binding.setSurfaceSize(const Size(1440, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(key: UniqueKey(), home: scoped(page)));
    await tester.pumpAndSettle();
  }

  Future<void> pumpSidebar(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UniversityPathApp(startAuthenticated: true, authGateway: FakeAuth()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpOfficialAudit(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await audit.login(authApi);
    addTearDown(authApi.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OfficialGraduationPage(
            auth: authApi,
            ownerId: userId,
            onPersonal: () {},
            profile: planning?.profile,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpChat(WidgetTester tester, {required bool grounded}) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    conversation?.dispose();
    conversation = AssistantConversation(
      api: AssistantApi(
        client: MockClient((request) async {
          chatRequests.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (script == AuthScript.loginFail) {
            return assistant.response({
              'error': {'message': 'synthetic-sensitive-input'},
            }, 500);
          }
          if (grounded && chatRequests.length == 1) {
            return assistant.response(
              assistant.result(
                status: 'grounded',
                reason: 'generated_from_evidence',
                answer: '합성 문서에 근거한 설명',
                citations: const [
                  {
                    'chunk_id': 'id',
                    'document_id': 'id',
                    'title': '합성 학사규정',
                    'source_url': 'https://example.edu/rules.pdf',
                    'page': 2,
                    'excerpt': '합성 근거 원문',
                  },
                ],
              ),
            );
          }
          return assistant.response(assistant.result());
        }),
      ),
    );
    addTearDown(() => conversation?.dispose());
    final profile = planning?.profile;
    if (profile != null) {
      conversation!.setContext(
        SchoolQueryContext(
          institution: profile.school,
          department: profile.department,
          admissionYear: profile.admissionYear,
          track: profile.track,
        ),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssistantPanel(
            conversation: conversation!,
            width: 360,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fillRecord(
    WidgetTester tester,
    Map<String, String> values,
  ) async {
    for (final entry in values.entries) {
      final field = find.byKey(ValueKey('record-field-${entry.key}'));
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.value);
    }
  }

  Future<void> saveRecord(WidgetTester tester) async {
    final button = find.text('내 기록에 저장');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<PersonalRecord> saveServerRecord(
    PersonalRecordKind kind,
    Map<String, String> values,
  ) async {
    LocalDataOwner.currentUserId = userId;
    final repo = RemotePersonalRecordRepository(
      StudentApi(ensureGateway(), ownerId: userId),
      kind,
      ensureOpen: () {},
    );
    await repo.load();
    await repo.save(PersonalRecord(id: PersonalRecord.newId(), values: values));
    return repo.records.last;
  }

  Future<void> addNamedRecord(
    WidgetTester tester, {
    required String addLabel,
    String? choice,
    required Map<String, String> values,
  }) async {
    var add = find.widgetWithText(FilledButton, addLabel);
    if (add.evaluate().isEmpty) {
      add = find.text(addLabel);
    }
    await tester.ensureVisible(add.first);
    await tester.tap(add.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    final volunteer = find.byKey(const ValueKey('activity-add-volunteer'));
    if (volunteer.evaluate().isNotEmpty) {
      await tester.tap(find.text(choice ?? '봉사').last);
      await tester.pumpAndSettle();
    } else if (choice != null) {
      final option = find.text(choice);
      if (option.evaluate().isNotEmpty) {
        await tester.tap(option.last);
        await tester.pumpAndSettle();
      }
    }
    await fillRecord(tester, values);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await saveRecord(tester);
  }
}
