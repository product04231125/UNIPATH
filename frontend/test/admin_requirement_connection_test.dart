import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/admin/admin_editor.dart';
import 'package:university_path_frontend/features/admin/admin_models.dart';
import 'package:university_path_frontend/features/admin/admin_requirement_draft.dart';
import 'package:university_path_frontend/features/admin/admin_rule_execution_panel.dart';
import 'package:university_path_frontend/features/api/rule_program_models.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';

import 'package:university_path_frontend/shared/widgets/field_label.dart';

import 'support/auth_fixture.dart';

import 'remote_admin_test.dart' as fixture;
import 'school_knowledge_api_test.dart' as knowledge;

const ruleId = '00000000-0000-4000-8000-000000000021';
const groupId = '00000000-0000-4000-8000-000000000022';
const otherRuleId = '00000000-0000-4000-8000-000000000023';
const programId = '00000000-0000-4000-8000-000000000024';

class RequirementServer extends fixture.AdminServer {
  RequirementServer({
    this.grouped = false,
    this.empty = false,
    this.schoolAdmin = false,
  }) {
    data['rules'] = empty
        ? []
        : [
            {
              ...row(ruleId, '총 학점'),
              'status': 'applied',
              'rule_type': 'credits',
              'definition': '졸업에 필요한 학점',
              if (grouped) 'rule_set_id': groupId,
            },
            if (grouped)
              {
                ...row(otherRuleId, '봉사'),
                'status': 'applied',
                'rule_type': 'volunteer',
                'definition': '봉사시간',
                'rule_set_id': groupId,
              },
          ];
    if (grouped) {
      data['rule-sets'] = [
        {...row(groupId, '졸업요건'), 'status': 'applied', 'version': 4},
      ];
    }
  }
  final bool grouped, empty, schoolAdmin;
  int? fail;
  bool changedPage = false;
  Map<String, dynamic>? savedProgram;
  final writes = <http.Request>[];
  Map<String, dynamic> get source => data['rules']!.first;
  Map<String, dynamic> evidence() => {
    'chunk_id': knowledge.chunk,
    'knowledge_document_id': knowledge.document,
    'knowledge_version': 3,
    'document_id': knowledge.document,
    'document_version': 2,
    'title': '학교 규정',
    'source_url': 'https://school.example.invalid/rules',
    'page': 1,
    'content_hash': 'c' * 64,
    'document_hash': 'a' * 64,
    'excerpt': '최소 120학점',
  };
  Map<String, dynamic> program(Map<String, dynamic> body, {int version = 1}) =>
      {
        'id': programId,
        'institution_id': fixture.schoolId,
        'department_id': null,
        'curriculum_id': null,
        'name': '졸업 조건',
        'rule_set_id': grouped ? groupId : null,
        'rule_id': grouped ? null : source['id'],
        'source_version': grouped ? 4 : source['version'],
        'version': version,
        'admission_year_from': body['admission_year_from'],
        'admission_year_to': body['admission_year_to'],
        'tracks': body['tracks'],
        'effective_from': null,
        'effective_to': null,
        'status': 'draft',
        'created_at': '2026-10-25T00:00:00Z',
        'updated_at': '2026-10-25T00:00:00Z',
        'approved_at': null,
        'revoked_at': null,
        'approved_by': null,
        'review_note': '',
        'revoked_by': null,
        'revocation_reason': '',
        'rules': [
          for (final r in body['rules'] as List)
            {
              'rule_id': r['rule_id'],
              'source_version': r['expected_version'],
              'title': '요건',
              'condition': r['condition'],
              'evidence': [evidence()],
              'references': [],
            },
        ],
        'missing_rule_ids': [],
        'usable': false,
      };
  @override
  http.Response respond(http.Request r) {
    http.Response json(Object value, [int status = 200]) => http.Response(
      jsonEncode(value),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    final path = r.url.path;
    if (schoolAdmin &&
        (path.endsWith('/auth/login') || path.endsWith('/auth/me'))) {
      requests.add(r);
      return json({
        ...identityJson(role: 'school_admin'),
        'admin_scopes': [
          {'institution_id': fixture.schoolId, 'status': 'active'},
        ],
        if (path.endsWith('/login')) 'access_token': token,
      });
    }

    if (path.contains('/rule-programs')) {
      requests.add(r);
      if (r.method == 'GET') {
        if (path.endsWith('/$programId')) return json(savedProgram!);
        return json({
          'items': [if (savedProgram != null) savedProgram],
          'next_cursor': null,
        });
      }
      writes.add(r);
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      if (fail == null || fail == 503) {
        savedProgram = program(
          body,
          version: r.method == 'PUT'
              ? (savedProgram!['version'] as int) + 1
              : 1,
        );
      }
      if (fail != null) {
        return json({
          'error': {
            'message': '합성 저장 실패',
            'field_errors': [
              {'field': 'body.rules.0.condition.minimum', 'reason': 'invalid'},
            ],
          },
        }, fail!);
      }
      return json(savedProgram!, r.method == 'POST' ? 201 : 200);
    }
    if (path.contains('/knowledge-revisions')) {
      requests.add(r);
      if (path.endsWith('/pages')) {
        return json({
          'items': [
            {
              'page': 1,
              'part_count': 1,
              'character_count': 10,
              'page_hash': 'b' * 64,
              'is_blank': false,
            },
          ],
          'next_cursor': null,
        });
      }
      if (path.endsWith('/pages/1')) {
        return json({
          'knowledge_document_id': knowledge.document,
          'version': changedPage ? 4 : 3,
          'page': 1,
          'page_hash': 'b' * 64,
          'is_blank': false,
          'parts': [
            {
              'id': knowledge.chunk,
              'content': '최소 120학점',
              'admission_years': [2026],
              'tracks': ['single_major'],
              'warnings': [],
              'part_index': 0,
              'part_count': 1,
              'character_start': 0,
              'character_end': 10,
              'content_hash': 'c' * 64,
            },
          ],
        });
      }
      return json({
        'items': [
          {
            ...knowledge.header(),
            'institution_id': fixture.schoolId,
            'department_id': null,
            'status': 'approved',
            'name': '학교 규정',
          },
        ],
        'next_cursor': null,
      });
    }
    if (r.method == 'POST' && path.endsWith('/apply')) {
      requests.add(r);
      final index = data['rules']!.indexWhere(
        (x) => path.contains(x['id'] as String),
      );
      data['rules']![index] = {
        ...data['rules']![index],
        'status': 'applied',
        'version': 2,
      };
      return json(data['rules']![index]);
    }
    final result = super.respond(r);
    if (empty && r.method == 'POST' && path.endsWith('/rules')) {
      data['rules']!.last['status'] = 'draft';
      return json(data['rules']!.last, 201);
    }
    return result;
  }
}

Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Finder input(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is FieldLabel && w.label == label),
  matching: find.byType(TextFormField),
);
Future<void> text(WidgetTester t, String label, String value) async {
  final f = input(label);
  await t.ensureVisible(f);
  await t.enterText(f, value);
  await t.pumpAndSettle();
}

Future<void> select<T>(WidgetTester t, String label, T value) async {
  final f = find.byWidgetPredicate(
    (w) => w is AnchoredSelectField<T> && w.label == label,
  );
  await t.ensureVisible(f);
  t.widget<AnchoredSelectField<T>>(f).onChanged(value);
  await t.pumpAndSettle();
}

Future<GlobalKey<AdminEditorState>> open(
  WidgetTester t,
  RequirementServer server,
) async {
  await t.binding.setSurfaceSize(const Size(1440, 1100));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final (api, repo) = await fixture.connected(server);
  addTearDown(api.close);
  addTearDown(repo.dispose);
  final key = GlobalKey<AdminEditorState>();
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AdminEditor(
            key: key,
            repository: repo,
            actorId: userId,
            kind: AdminKind.rule,
            schoolId: fixture.schoolId,
            record: server.empty
                ? null
                : repo.records.firstWhere((r) => r.id == ruleId),
            inline: true,
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return key;
}

Future<void> criteria(WidgetTester t) async {
  await text(t, '최소 필요 학점 *', '120');
  await text(t, '적용 입학연도 시작 *', '2026');
  await text(t, '적용 입학연도 종료 *', '2026');
  await text(t, '이수 경로 (쉼표 구분) *', 'single_major');
  await tap(t, find.text('근거·초안 다시 읽기'));
  await select(t, '검토된 근거 문서', knowledge.document);
  await select<int?>(t, '근거 페이지', 1);
  await tap(t, find.widgetWithText(CheckboxListTile, '최소 120학점').first);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'new metadata retains server UUID then sends explicit criterion only after apply and save',
    (t) async {
      final server = RequirementServer(empty: true);
      final key = await open(t, server);
      await t.enterText(find.byKey(const ValueKey('admin-field-name')), '총 학점');
      await select(t, '규칙 종류 *', 'credits');
      await t.enterText(
        find.byKey(const ValueKey('admin-field-definition')),
        '졸업에 필요한 학점',
      );
      await text(t, '최소 필요 학점 *', '120');
      await tap(t, find.text('요건 설명 저장'));
      expect(server.data['rules'], hasLength(1));
      expect(server.writes, isEmpty);
      expect(find.byType(AdminRuleExecutionPanel), findsOneWidget);
      expect(t.widget<TextFormField>(input('최소 필요 학점 *')).initialValue, '120');
      await tap(t, find.text('요건 검토·적용'));
      await tap(t, find.widgetWithText(FilledButton, '검토·적용'));
      await criteria(t);
      await tap(t, find.text('계산 조건 초안 저장'));
      expect(server.writes, hasLength(1));
      final body = jsonDecode(server.writes.single.body) as Map;
      expect(body['rule_id'], fixture.newId);
      expect(body['expected_source_version'], 2);
      expect((body['rules'] as List).single, {
        'rule_id': fixture.newId,
        'expected_version': 2,
        'condition': {
          'kind': 'minimum_credits',
          'minimum': '120',
          'category': null,
        },
        'evidence_chunk_ids': [knowledge.chunk],
      });
      expect(body['admission_year_from'], 2026);
      expect(body['tracks'], ['single_major']);
      expect(key.currentState!.dirty, isFalse);
      await text(t, '최소 필요 학점 *', '130');
      await tap(t, find.text('계산 조건 초안 저장'));
      expect(server.writes.last.method, 'PUT');
      expect(jsonDecode(server.writes.last.body)['expected_version'], 1);
      expect(server.data['rules'], hasLength(1));
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('group draft replacement preserves other rules and versions', (
    t,
  ) async {
    final server = RequirementServer(grouped: true);
    server.savedProgram = server.program({
      'admission_year_from': 2026,
      'admission_year_to': 2026,
      'tracks': ['single_major'],
      'rules': [
        {
          'rule_id': ruleId,
          'expected_version': 1,
          'condition': {'kind': 'minimum_credits', 'minimum': '100'},
        },
        {
          'rule_id': otherRuleId,
          'expected_version': 1,
          'condition': {'kind': 'minimum_volunteer_hours', 'minimum': '30'},
        },
      ],
    }, version: 7);
    await open(t, server);
    await tap(t, find.text('근거·초안 다시 읽기'));
    await select(t, '저장할 실행 초안', programId);
    await text(t, '최소 필요 학점 *', '120');
    await tap(t, find.text('계산 조건 초안 저장'));
    final body = jsonDecode(server.writes.single.body) as Map;
    expect(server.writes.single.method, 'PUT');
    expect(body['expected_version'], 7);
    final rules = body['rules'] as List;
    expect(rules.first['rule_id'], otherRuleId);
    expect(rules.first['condition'], {
      'kind': 'minimum_volunteer_hours',
      'minimum': '30',
    });
    expect(rules.last['condition']['minimum'], '120');
    server.fail = 409;
    await text(t, '최소 필요 학점 *', '125');
    await tap(t, find.text('계산 조건 초안 저장'));
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '계산 조건 초안 저장'),
          )
          .onPressed,
      isNull,
    );
    server.fail = null;
    await tap(t, find.text('근거·초안 다시 읽기'));
    await select(t, '저장할 실행 초안', programId);
    await tap(t, find.text('내용 폐기'));
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '계산 조건 초안 저장'),
          )
          .onPressed,
      isNotNull,
    );
    expect(t.widget<TextFormField>(input('최소 필요 학점 *')).initialValue, '120');
    expect(t.takeException(), isNull);
  });
  for (final status in [422, 409, 503]) {
    testWidgets(
      'server $status retains condition and protects uncertain or stale retry',
      (t) async {
        final server = RequirementServer()..fail = status;
        await open(t, server);
        await criteria(t);
        await tap(t, find.text('계산 조건 초안 저장'));
        expect(server.writes, hasLength(1));
        expect(
          find.text(
            status == 422
                ? '입력값의 형식과 길이를 확인해 주세요.'
                : status == 409
                ? '이미 등록되었거나 다른 변경이 있습니다. 입력을 확인해 주세요.'
                : '서버에서 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.',
          ),
          findsOneWidget,
        );
        expect(
          t.widget<TextFormField>(input('최소 필요 학점 *')).initialValue,
          '120',
        );
        final button = t.widget<FilledButton>(
          find.widgetWithText(FilledButton, '계산 조건 초안 저장'),
        );
        if (status == 422) {
          expect(button.onPressed, isNotNull);
          expect(find.textContaining('서버에서 이 입력'), findsWidgets);
        } else {
          expect(button.onPressed, isNull);
          await t.pumpAndSettle();
          expect(server.writes, hasLength(1));
          if (status == 503) {
            server.fail = null;
            await tap(t, find.text('근거·초안 다시 읽기'));
            await select(t, '저장할 실행 초안', programId);
            await tap(
              t,
              find.text('내용 폐기'),
            ); // Explicitly replace the local draft with the saved response.
            await text(t, '최소 필요 학점 *', '125');
            await tap(t, find.text('계산 조건 초안 저장'));
            expect(server.writes.last.method, 'PUT');
            expect(
              server.writes.where((r) => r.method == 'POST'),
              hasLength(1),
            );
          }
        }
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'condition drafts survive type switches and protect cancel until discarded',
    (t) async {
      final server = RequirementServer(empty: true);
      final key = await open(t, server);
      expect(key.currentState!.dirty, isFalse);
      await select(t, '규칙 종류 *', 'credits');
      await text(t, '최소 필요 학점 *', '120');
      await select(t, '규칙 종류 *', 'volunteer');
      await text(t, '최소 필요 봉사시간 *', '30');
      await select(t, '규칙 종류 *', 'credits');
      expect(t.widget<TextFormField>(input('최소 필요 학점 *')).initialValue, '120');
      await tap(t, find.text('취소'));
      await tap(t, find.text('계속 작성'));
      expect(key.currentState!.dirty, isTrue);
      await tap(t, find.text('취소'));
      await tap(t, find.text('내용 폐기'));
      expect(key.currentState!.dirty, isFalse);
      expect(server.writes, isEmpty);
      expect(server.data['rules'], isEmpty);
    },
  );
  testWidgets(
    'permission rejection clears fetched evidence and never shows save success',
    (t) async {
      final server = RequirementServer()..fail = 403;
      await open(t, server);
      await criteria(t);
      await tap(t, find.text('계산 조건 초안 저장'));
      expect(find.text('이 작업을 수행할 권한이 없습니다.'), findsOneWidget);
      expect(find.text('계산 조건 초안을 서버에 저장했습니다. 아직 승인되지 않았습니다.'), findsNothing);
      expect(find.widgetWithText(CheckboxListTile, '최소 120학점'), findsNothing);
      expect(server.writes, hasLength(1));
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'school administrator saves scoped criterion using existing execution endpoint',
    (t) async {
      final server = RequirementServer(schoolAdmin: true);
      await open(t, server);
      await criteria(t);
      await tap(t, find.text('계산 조건 초안 저장'));
      expect(server.writes, hasLength(1));
      expect(server.writes.single.url.path, '/api/v1/admin/rule-programs');
      expect(server.writes.single.headers['Authorization'], 'Bearer $token');
      expect(jsonDecode(server.writes.single.body)['rule_id'], ruleId);
      expect(find.text('계산 조건 초안을 서버에 저장했습니다. 아직 승인되지 않았습니다.'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('changed evidence page is rejected without write', (t) async {
    final server = RequirementServer()..changedPage = true;
    await open(t, server);
    await tap(t, find.text('근거·초안 다시 읽기'));
    await select(t, '검토된 근거 문서', knowledge.document);
    await select<int?>(t, '근거 페이지', 1);
    expect(find.textContaining('요청과 다른 근거 페이지'), findsOneWidget);
    expect(server.writes, isEmpty);
  });
  test('all typed criteria roundtrip and reject changed master versions', () {
    final course = AdminRecord(
      id: fixture.courseId,
      kind: AdminKind.course,
      version: 3,
      values: {},
    );
    final cert = CertificateRegistryCertificateView.fromJson({
      'id': programId,
      'provider_id': groupId,
      'code': 'C',
      'name': '자격',
      'official_url': 'https://certificate.example.invalid',
      'version': 2,
      'status': 'active',
      'created_at': '2026-10-25T00:00:00Z',
      'updated_at': '2026-10-25T00:00:00Z',
    });
    final conditions = <String, OfficialCondition>{
      'credits': const OfficialCreditCriterion(
        kind: 'minimum_credits',
        minimum: '120',
        category: '전공',
      ),
      'volunteer': const OfficialVolunteerCriterion(
        kind: 'minimum_volunteer_hours',
        minimum: '30',
      ),
      'required_course': const OfficialCourseCriterion(
        kind: 'required_courses',
        courses: [
          OfficialProgramRequiredCourse(
            courseId: fixture.courseId,
            expectedVersion: 3,
            minimumCredits: '3',
            minimumGradePoints: '2',
            comparisonGradeScale: '4.5',
          ),
        ],
      ),
      'certificate': const OfficialCertificateCriterion(
        kind: 'any_certificate',
        certificates: [
          OfficialCertificateChoice(
            certificateId: programId,
            expectedVersion: 2,
          ),
        ],
      ),
      'thesis': const OfficialThesisCriterion(
        kind: 'thesis',
        thesisType: 'capstone',
        requiresApproval: false,
        acceptedGrades: ['P'],
      ),
      'custom': const OfficialManualCriterion(
        kind: 'manual_review',
        instruction: '학적 확인',
      ),
    };
    for (final e in conditions.entries) {
      expect(
        AdminRequirementDraft.fromCondition(e.value)
            .condition(e.key, [course], [cert], '학적 확인')
            .toJson(),
        e.value.toJson(),
      );
    }
    final stale = AdminRequirementDraft.fromCondition(
      conditions['required_course']!,
    );
    expect(
      () => stale.condition(
        'required_course',
        [
          AdminRecord(
            id: fixture.courseId,
            kind: AdminKind.course,
            version: 4,
            values: {},
          ),
        ],
        [],
        '',
      ),
      throwsFormatException,
    );
  });
}
