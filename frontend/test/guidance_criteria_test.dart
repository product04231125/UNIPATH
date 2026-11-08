import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/guidance_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/assistant/academic_guidance_view.dart';
import 'package:university_path_frontend/features/assistant/assistant_api.dart';
import 'package:university_path_frontend/features/assistant/assistant_conversation.dart';
import 'package:university_path_frontend/features/assistant/conversation_bridge.dart';

import 'rule_program_api_test.dart' as contracts;

class CriteriaGateway extends ApiGateway {
  final paths = <String>[];
  Map<String, dynamic> selection = contracts.selection();
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    expect(method, 'GET');
    paths.add(path);
    if (path.startsWith('catalog/rule-programs?'))
      return pending?.future ?? selection;
    return {
      'schema_version': 'academic-click-v3',
      'node_id': path.split('/').last.split('?').first,
      'title': '이수학점',
      'state': 'needs_input',
      'reason': 'verified_audit_required',
      'message': '개인 감사를 선택해 주세요.',
      'cards': [],
      'warnings': [],
      'buttons': [
        {
          'id': 'home',
          'label': '처음으로',
          'action': 'select_node',
          'node_id': 'home',
          'availability': 'available',
        },
      ],
    };
  }
}

AssistantConversation conversation(CriteriaGateway api) =>
    AssistantConversation(guidanceApi: GuidanceApi(api), registeredOnly: true)
      ..setContext(
        const SchoolQueryContext(
          institutionId: contracts.identifier,
          departmentId: contracts.identifier,
          curriculumId: contracts.identifier,
          admissionYear: 2026,
          track: 'single_major',
          institution: '합성 대학교',
          department: '합성학과',
        ),
      );

Future<void> show(WidgetTester tester, AssistantConversation c) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AcademicGuidanceView(conversation: c),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'credits displays approved threshold without an audit, summary stays personal',
    (tester) async {
      final api = CriteriaGateway();
      final c = conversation(api)..guidanceAuditId = 'old-audit';
      api.selection['programs'][0]['rules'][0]['condition']['minimum'] = '130';
      await c.navigateGuidance('credits');
      expect(api.paths.first, 'me/academic-guidance/nodes/credits');
      expect(api.paths.last, startsWith('catalog/rule-programs?'));
      expect(
        Uri.parse(api.paths.last).queryParameters['curriculum_id'],
        contracts.identifier,
      );
      await show(tester, c);
      expect(find.text('필요 학점: 130학점'), findsOneWidget);
      expect(find.text('개인 감사를 선택해 주세요.'), findsNothing);
      expect(find.textContaining('결과 불러오기'), findsNothing);
      expect(find.textContaining('점검 기준일'), findsNothing);
      expect(api.paths.any((p) => p.contains('graduation-audits')), false);
      await tester.pumpWidget(const SizedBox());
      await c.navigateGuidance('summary');
      expect(
        api.paths.last,
        'me/academic-guidance/nodes/summary?audit_id=old-audit',
      );
      await show(tester, c);
      expect(find.text('저장된 내 졸업요건 결과 불러오기'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'unregistered criteria explain school review rather than personal evaluation',
    (tester) async {
      final api = CriteriaGateway()
        ..selection = {
          ...contracts.selection(),
          'status': 'needs_review',
          'reason': 'rule_program_review_required',
          'programs': [],
          'issues': [],
        };
      final c = conversation(api);
      await c.navigateGuidance('volunteer');
      await show(tester, c);
      expect(find.textContaining('학교 관리자의 기준 등록·검토'), findsOneWidget);
      expect(find.textContaining('결과 불러오기'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  test('incomplete school scope never queries criteria and stale scope response is ignored', () async {
    final api = CriteriaGateway();
    final c = AssistantConversation(
      guidanceApi: GuidanceApi(api),
      registeredOnly: true,
    );
    await c.navigateGuidance('credits');
    expect(api.paths.length, 1);
    expect(c.criteriaError, contains('교육과정'));
    c.dispose();
    final pending = CriteriaGateway()..pending = Completer();
    final owner = conversation(pending);
    final fetch = owner.navigateGuidance('credits');
    await Future<void>.delayed(Duration.zero);
    owner.setContext(const SchoolQueryContext());
    pending.pending!.complete(contracts.selection());
    await fetch;
    expect(owner.guidanceCriteria, isNull);
    owner.dispose();
  });

  test(
    'criteria snapshots reach detached window and reject a mismatched school',
    () async {
      final api = CriteriaGateway();
      final c = conversation(api);
      await c.navigateGuidance('credits');
      final bridge = ConversationBridge(c, (_) async {});
      final remote = RemoteConversation(
        request: (command) async =>
            command == null ? bridge.read() : bridge.command(command),
        changes: const Stream.empty(),
      );
      await remote.load();
      expect(remote.showingCriteria, true);
      expect(
        remote.guidanceCriteria!.programs.single.rules.single.condition.kind,
        'minimum_credits',
      );
      api.selection['programs'][0]['institution_id'] = 'other-school';
      await c.navigateGuidance('credits');
      expect(c.guidanceCriteria, isNull);
      expect(c.criteriaError, isNotNull);
      remote.dispose();
      bridge.dispose();
      c.dispose();
    },
  );
}
