import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/features/api/student_academic_api.dart';
import 'package:university_path_frontend/features/api/student_api_models.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/graduation/student_academic_controller.dart';
import 'package:university_path_frontend/features/graduation/student_academic_page.dart';
import 'package:university_path_frontend/features/graduation/student_academic_course_link.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';

class AcademicTransport implements ApiGateway {
  bool failRead = false, failWrite = false, wrongOwner = false;
  bool active = true, failReadAfterWrite = false;
  int version = 1;
  final writes = <Map<String, dynamic>>[];
  final courses = <Map<String, dynamic>>[
    {
      'id': 'entry',
      'course_name': '공통 설계',
      'course_code': 'SHARED',
      'classification_node_id': 'node',
      'classification_label': '교양 / 기초',
      'requirement': 'required',
      'recognized_credits': '3.125',
    },
  ];
  late List<Map<String, dynamic>> contexts = [
    {
      'id': 'context',
      'institution_id': 'school',
      'department_id': 'department',
      'track_id': 'track',
      'curriculum_revision_id': 'curriculum',
      'admission_year': 2026,
      'primary': true,
      'department_name': '주학과',
      'track_name': '단일전공',
      'curriculum_name': '공통 교육과정',
      'courses': courses,
    },
  ];
  final docs = <Map<String, dynamic>>[
    {
      'id': 'checklist',
      'name': '졸업 안내',
      'kind': 'checklist',
      'revision': 1,
      'status': 'published',
      'context_ids': ['context'],
      'content': {
        'kind': 'checklist',
        'lines': [
          {'id': 'line', 'text': '졸업시험에 합격해야 한다.'},
        ],
      },
      'responses': <Object>[],
    },
    {
      'id': 'certification',
      'name': '졸업 인증',
      'kind': 'certification',
      'revision': 1,
      'status': 'published',
      'context_ids': ['context'],
      'content': {
        'kind': 'certification',
        'groups': [
          {
            'id': 'group',
            'label': '정보화',
            'choice': 'pickOne',
            'pick_count': null,
            'items': [
              {'id': 'item', 'label': '정보화 자격 취득', 'kind': 'text'},
            ],
            'groups': <Object>[],
            'exemptions': ['학교별 면제 안내'],
          },
        ],
        'tables': [
          {
            'title': '점수 안내',
            'columns': ['시험', '기준'],
            'rows': [
              ['합성 시험', '합성 점수'],
            ],
          },
        ],
      },
      'responses': <Object>[],
      'group_results': {'group': 'needs_review'},
    },
    {
      'id': 'credits',
      'name': '학점 기준',
      'kind': 'credit_table',
      'revision': 1,
      'status': 'published',
      'context_ids': ['context'],
      'content': {
        'kind': 'credit_table',
        'headers': [
          {
            'id': 'outer',
            'label': '교양',
            'role': 'group',
            'position': 0,
            'parent_id': null,
          },
          {
            'id': 'inner',
            'label': '필수',
            'role': 'group',
            'position': 0,
            'parent_id': 'outer',
          },
          {
            'id': 'column',
            'label': '기초',
            'role': 'value',
            'position': 0,
            'parent_id': 'inner',
            'classification_node_id': 'node',
            'requirement': 'required',
          },
        ],
        'rows': [
          {'id': 'row', 'label': '단일전공', 'note': '원문 비고', 'scope': null},
        ],
        'cells': [
          {
            'row_id': 'row',
            'header_id': 'column',
            'state': 'number',
            'value': '3.25',
          },
        ],
      },
      'responses': <Object>[],
    },
  ];
  final links = <Map<String, dynamic>>[];
  Map<String, dynamic> get requirements => {
    'owner_id': wrongOwner ? 'other' : 'owner',
    'workspace_version': version,
    'activation_id': active ? 'activation' : null,
    'issues': <Object>[],
    'documents': active ? docs : <Object>[],
  };
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final route = Uri.parse(path).path;
    if (method == 'GET') {
      if (failRead) throw const AuthFailure('읽기 실패', status: 503);
      if (route.endsWith('academic-contexts')) {
        return {
          'owner_id': wrongOwner ? 'other' : 'owner',
          'version': version,
          'institution_id': 'school',
          'issues': <Object>[],
          'contexts': contexts,
        };
      }
      if (route.endsWith('academic-requirements')) return requirements;
      if (route.endsWith('academic-requirements/preview')) {
        return {
          'owner_id': 'owner',
          'workspace_version': version,
          'active_activation_id': active ? 'activation' : null,
          'digest': 'a' * 64,
          'issues': <Object>[],
          'documents': docs,
          'changes': <Object>[],
        };
      }
      if (route.endsWith('academic-credit-progress')) {
        return {
          'owner_id': 'owner',
          'activation_id': active ? 'activation' : null,
          'issues': <Object>[],
          'links': links,
          'tables': [
            {
              'requirement_revision_id': 'credits',
              'cells': [
                {
                  'row_id': 'row',
                  'header_id': 'column',
                  'target': '3.25',
                  'earned': '3.125',
                  'remaining': '0.125',
                  'status': 'not_satisfied',
                  'evidence': [
                    {
                      'title': '내 설계 수강',
                      'state': 'included',
                      'reason': 'confirmed',
                      'credits': '3.125',
                    },
                  ],
                },
              ],
            },
          ],
        };
      }
      if (route.endsWith('academic/options')) {
        return {
          'institution_id': 'school',
          'departments': [
            {'id': 'department', 'name': '주학과'},
            {'id': 'additional', 'name': '추가학과'},
          ],
          'tracks': [
            {'id': 'track', 'name': '단일전공'},
            {'id': 'extra-track', 'name': '복수전공'},
          ],
          'curricula': [
            {
              'id': 'curriculum',
              'name': '공통 교육과정',
              'revision': 1,
              'scope': {
                'clauses': [{}],
              },
            },
          ],
        };
      }
      if (route.endsWith('course-records')) {
        return {
          'items': [
            {
              'id': 'record',
              'owner_id': 'owner',
              'title': '내 설계 수강',
              'version': 1,
              'credits': '3.5',
              'completion': 'recorded',
            },
          ],
          'next_cursor': null,
        };
      }
      if (route.endsWith('credential-records')) {
        return {
          'items': [
            {
              'id': 'credential',
              'owner_id': 'owner',
              'title': '합성 자격',
              'version': 2,
            },
          ],
          'next_cursor': null,
        };
      }
      return {'items': <Object>[], 'next_cursor': null};
    }
    writes.add({
      'method': method,
      'path': path,
      'body': jsonDecode(jsonEncode(body)),
    });
    if (failWrite) throw const AuthFailure('응답 유실', status: 503);
    if (failReadAfterWrite) failRead = true;
    if (route.endsWith('academic-requirements/activate')) {
      active = true;
      version++;
      return requirements;
    }
    if (route.contains('/responses/')) {
      final id = route.split('/')[2], item = route.split('/').last;
      final doc = docs.firstWhere((d) => d['id'] == id);
      doc['responses'] = [
        {
          'item_id': item,
          'value': body!['value'],
          'previous_value': null,
          'version': 1,
          'stale': false,
          'records': [
            for (final raw in body['records'] as List)
              {
                'record_id': raw['record_id'],
                'kind': raw['kind'],
                'version': raw['expected_version'],
                'title': raw['kind'] == 'credential' ? '합성 자격' : '내 설계 수강',
                'available': true,
                'current_version': raw['expected_version'],
              },
          ],
        },
      ];
      if (id == 'certification') {
        doc['group_results'] = {
          'group': body['value'] == true ? 'satisfied' : 'needs_review',
        };
      }
      return requirements;
    }
    if (route.endsWith('academic-contexts')) {
      version++;
      contexts = [
        for (final raw in body!['contexts'] as List)
          {
            ...Map<String, dynamic>.from(raw as Map),
            'id': raw['id'] ?? 'new-context',
            'institution_id': 'school',
            'department_name': raw['department_id'] == 'department'
                ? '주학과'
                : '추가학과',
            'track_name': raw['track_id'] == 'track' ? '단일전공' : '복수전공',
            'curriculum_name': '공통 교육과정',
            'courses': courses,
          },
      ];
      return {
        'owner_id': 'owner',
        'version': version,
        'institution_id': 'school',
        'issues': <Object>[],
        'contexts': contexts,
      };
    }
    if (route.endsWith('academic-link')) {
      final value = {
        'owner_id': 'owner',
        'id': 'link',
        'course_record_id': 'record',
        'context_id': body!['context_id'],
        'entry_id': body['entry_id'],
        'result': body['result'],
        'earned_credits': body['earned_credits'],
        'included': body['included'],
        'version': 1,
      };
      links.add(value);
      return value;
    }
    throw StateError('Unexpected $method $path');
  }
}

const capture = bool.fromEnvironment('STUDENT_ACADEMIC_CAPTURE');
Future<void> screenshot(WidgetTester tester, GlobalKey key, String name) async {
  if (!capture) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final frame = await boundary.toImage(pixelRatio: 1);
    final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('../output/student-academic')
      ..createSync(recursive: true);
    await File('${dir.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    frame.dispose();
  });
}

const profile = PlanningProfile(
  school: '합성 대학',
  department: '주학과',
  institutionId: 'school',
  departmentId: 'department',
  admissionYear: 2026,
);
Future<GlobalKey> mount(
  WidgetTester tester,
  AcademicTransport transport, {
  Widget? child,
}) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      theme: universityPathTheme(),
      builder: (context, child) => RepaintBoundary(key: key, child: child!),
      home: Scaffold(
        body:
            child ??
            StudentAcademicPage(
              api: StudentAcademicApi(transport, 'owner'),
              profile: profile,
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return key;
}

Future<void> choose(
  WidgetTester tester,
  String label,
  String text, {
  bool last = false,
}) async {
  final all = find.byWidgetPredicate(
    (w) => w is AnchoredSelectField<String> && w.label == label,
  );
  final field = last ? all.last : all.first;
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MenuItemButton, text).last);
  await tester.pumpAndSettle();
}

void main() {
  test('catalog P/F unknown credits decode without a numeric value', () {
    final course = StudentCoursePublicView.fromJson({
      'id': 'course',
      'version': 1,
      'name': 'P/F 실습',
      'institution_id': 'school',
      'code': '',
      'credits': null,
      'grading_basis': 'pass_fail',
    });
    expect(course.credits, isEmpty);
    final academic = AcademicStudentCourse({
      'id': 'entry',
      'course_name': 'P/F 실습',
      'course_code': '',
      'classification_node_id': 'node',
      'requirement': 'elective',
      'grading_basis': 'pass_fail',
      'recognized_credits': null,
    });
    expect(academic.label, contains('P/F · 학점 미확인'));
    expect(academic.label, isNot(contains('0학점')));
  });
  setUpAll(() async {
    if (!capture) return;
    await (FontLoader('Pretendard')..addFont(
          rootBundle.load('assets/fonts/pretendard/Pretendard-Regular.otf'),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets('student previews new content and explicitly activates it', (
    tester,
  ) async {
    final transport = AcademicTransport()..active = false;
    final boundary = await mount(tester, transport);
    expect(
      find.byKey(const ValueKey('academic-response-line-true')),
      findsNothing,
    );
    await tester.tap(find.text('새 기준 본문·적용 대상 보기'));
    await tester.pumpAndSettle();
    await screenshot(tester, boundary, 'preview-before-activation');
    expect(find.textContaining('졸업시험에 합격해야 한다.'), findsOneWidget);
    final apply = find.text('확인한 기준 적용');
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '적용'));
    await tester.pumpAndSettle();
    expect(transport.writes.single['body']['expected_digest'], 'a' * 64);
    expect(transport.active, isTrue);
    expect(
      find.byKey(const ValueKey('academic-response-line-true')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'old record references disappear and are cleared on the next O/X save',
    (tester) async {
      final transport = AcademicTransport();
      transport.docs[1]['responses'] = [
        {
          'item_id': 'item',
          'value': true,
          'previous_value': null,
          'version': 1,
          'stale': true,
          'records': [
            {
              'record_id': 'deleted',
              'kind': 'credential',
              'version': 1,
              'title': '이전 자격',
              'available': false,
              'current_version': null,
            },
          ],
        },
      ];
      await mount(tester, transport);
      await tester.tap(find.widgetWithText(ChoiceChip, '인증 요건'));
      await tester.pumpAndSettle();
      expect(find.text('기록 연결'), findsNothing);
      expect(find.text('이전 자격'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('academic-response-item-true')),
      );
      await tester.pumpAndSettle();
      expect(transport.writes.single['body']['records'], isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'confirmed write followed by read failure is never sent again',
    () async {
      final transport = AcademicTransport();
      final c = StudentAcademicController(
        StudentAcademicApi(transport, 'owner'),
      );
      addTearDown(c.dispose);
      await c.load();
      transport.failReadAfterWrite = true;
      final result = await c.respond(
        c.requirements!.documents.first,
        'line',
        true,
        [],
      );
      expect(result, isTrue);
      expect(c.loaded, isFalse);
      expect(c.uncertain, isFalse);
      expect(await c.retry(), isFalse);
      expect(transport.writes, hasLength(1));
    },
  );
  testWidgets(
    'checklist retains O/X and exact uncertain request then refreshes',
    (tester) async {
      final transport = AcademicTransport();
      final key = await mount(tester, transport);
      expect(find.text('졸업시험에 합격해야 한다.'), findsOneWidget);
      transport.failWrite = true;
      await tester.tap(
        find.byKey(const ValueKey('academic-response-line-true')),
      );
      await tester.pumpAndSettle();
      expect(transport.writes, hasLength(1));
      expect(transport.writes.single['body']['value'], isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('academic-response-line-false')),
            )
            .onSelected,
        isNull,
      );
      transport.failWrite = false;
      await tester.tap(find.text('같은 요청으로 다시 저장').last);
      await tester.pumpAndSettle();
      expect(transport.writes, hasLength(2));
      expect(transport.writes[0], transport.writes[1]);
      expect(find.text('O · 충족'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('academic-response-line-false')),
      );
      await tester.pumpAndSettle();
      expect(transport.writes.last['body']['value'], isFalse);
      await tester.tap(find.text('초기화'));
      await tester.pumpAndSettle();
      expect(transport.writes.last['body']['value'], isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await screenshot(tester, key, 'checklist');
    },
  );
  testWidgets('certification offers read-only record search and separate O/X', (
    tester,
  ) async {
    final transport = AcademicTransport();
    final key = await mount(tester, transport);
    await tester.tap(find.widgetWithText(ChoiceChip, '인증 요건'));
    await tester.pumpAndSettle();
    await screenshot(tester, key, 'certification');
    expect(find.text('기록 연결'), findsNothing);
    expect(find.text('내 기록 찾기'), findsOneWidget);
    expect(transport.writes, isEmpty);
    await tester.tap(find.byKey(const ValueKey('academic-response-item-true')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(transport.writes.single['body']['records'], isEmpty);
    expect(transport.writes.last['body']['value'], isTrue);
    expect(find.textContaining('정보화 · 택1 · 충족'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'credit table uses server exact progress with aligned multilevel headers',
    (tester) async {
      final key = await mount(tester, AcademicTransport());
      await tester.tap(find.widgetWithText(ChoiceChip, '학점표'));
      await tester.pumpAndSettle();
      expect(find.text('교양'), findsOneWidget);
      expect(find.text('필수'), findsOneWidget);
      expect(find.text('단일전공\n취득학점'), findsOneWidget);
      expect(find.text('3.125'), findsOneWidget);
      expect(find.text('단일전공\n부족학점'), findsOneWidget);
      expect(find.text('0.125'), findsOneWidget);
      await screenshot(tester, key, 'credit-progress');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'additional major selection saves alongside existing primary context',
    (tester) async {
      final transport = AcademicTransport();
      final boundary = await mount(tester, transport);
      await tester.tap(find.text('학업 기준 설정'));
      await tester.pumpAndSettle();
      final add = find.text('추가 전공 연결');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      await choose(tester, '학과', '추가학과', last: true);
      await choose(tester, '이수 경로', '복수전공', last: true);
      await choose(tester, '교육과정', '공통 교육과정 · 1판', last: true);
      await screenshot(tester, boundary, 'additional-context-dialog');
      final save = find.text('학업 기준 저장');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(transport.writes, hasLength(1));
      final values = transport.writes.single['body']['contexts'] as List;
      expect(values, hasLength(2));
      expect(values.first['id'], 'context');
      expect(values.last['primary'], isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('course link stores explicit completion and earned credits', (
    tester,
  ) async {
    final transport = AcademicTransport();
    await mount(
      tester,
      transport,
      child: SingleChildScrollView(
        child: StudentAcademicCourseLinkEditor(
          api: StudentAcademicApi(transport, 'owner'),
          recordId: 'record',
          onChanged: () {},
        ),
      ),
    );
    await choose(tester, '교육과정 과목', '공통 설계 · SHARED · 교양 / 기초 · 3.125학점 · 필수');
    await choose(tester, '이수 결과', '이수');
    await tester.enterText(
      find.byKey(const ValueKey('academic-earned-credits')),
      '3.25',
    );
    final save = find.text('수강 산입 연결 저장');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(transport.writes.single['body']['earned_credits'], '3.25');
    expect(transport.writes.single['body']['expected_record_version'], 1);
    expect(transport.writes.single['body']['entry_id'], 'entry');
    expect(tester.takeException(), isNull);
  });
  test(
    'read failures and wrong owners never become empty successful requirements',
    () async {
      final transport = AcademicTransport()..failRead = true;
      final c = StudentAcademicController(
        StudentAcademicApi(transport, 'owner'),
      );
      addTearDown(c.dispose);
      await c.load();
      expect(c.loaded, isFalse);
      expect(c.error, isNotNull);
      expect(c.requirements, isNull);
      transport
        ..failRead = false
        ..wrongOwner = true;
      await c.load();
      expect(c.loaded, isFalse);
      expect(c.requirements, isNull);
    },
  );
}
