import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/guidance_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/assistant/assistant_api.dart';
import 'package:university_path_frontend/features/assistant/assistant_conversation.dart';
import 'package:university_path_frontend/features/assistant/assistant_panel.dart';
import 'package:university_path_frontend/features/assistant/ai_record_catalog.dart';
import 'package:university_path_frontend/features/assistant/conversation_bridge.dart';
import 'package:university_path_frontend/features/settings/ai_consent_preferences.dart';

class Api extends ApiGateway {
  final calls = <(String, Map<String, Object?>?)>[];
  Object? failure;
  Completer<Map<String, dynamic>>? pending;
  String personalizedStatus = 'evidence_only';
  String personalizedReason = 'generator_not_configured';
  Map<String, dynamic>? personalizedResponse;
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    calls.add((path, body));
    if (failure != null) throw failure!;
    if (pending != null) return pending!.future;
    if (path == 'me/personalized-guidance') {
      if (personalizedResponse != null) return personalizedResponse;
      return {
        'query_id': 'q',
        'status': personalizedStatus,
        'reason': personalizedReason,
        'official': false,
        'school': {
          'query_id': 's',
          'status': 'insufficient_evidence',
          'reason': 'no_approved_matching_evidence',
        },
        'personal': {'records': [], 'official': false},
      };
    }
    return schoolResult;
  }
}

final schoolResult = <String, dynamic>{
  'query_id': 'q',
  'status': 'insufficient_evidence',
  'reason': 'no_approved_matching_evidence',
  'answer': null,
  'citations': [],
  'missing_fields': [],
};
const school = SchoolQueryContext(
  institution: '학교',
  department: '학과',
  institutionId: 'school-id',
  departmentId: 'department-id',
  admissionYear: 2026,
  track: 'single_major',
);
const record = AiRecordOption(
  kind: 'activity',
  id: 'activity-id',
  version: 3,
  title: '봉사 기록',
);
Future<AiConsentPreferences> permissions() async {
  final value = AiConsentPreferences(
    ownerId: 'account',
    reader: (_) async => null,
    writer: (_, _) async => true,
  );
  await value.load();
  return value;
}

AssistantConversation conversation(Api api, AiConsentPreferences prefs) =>
    AssistantConversation(
      api: RegisteredAssistantApi(api),
      guidanceApi: GuidanceApi(api),
      consent: prefs,
      registeredOnly: true,
      loadRecords: () async => [record],
    )..setContext(school);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final state in [
    ('needs_user_input', 'external_processing_consent_required'),
    ('needs_user_input', 'personal_records_required'),
    ('insufficient_evidence', 'school_evidence_unavailable'),
    ('failed', 'generation_failed'),
  ]) {
    test(
      'personalized server state ${state.$1}/${state.$2} preserves draft and selection',
      () async {
        final api = Api()
          ..personalizedStatus = state.$1
          ..personalizedReason = state.$2;
        final p = await permissions(), c = conversation(api, p);
        c.setMode(AssistantMode.personalized);
        await c.refreshRecords();
        c.selectRecord(record.key, true);
        c.input.text = '입력을 유지할 질문';
        await c.permit(AssistantMode.personalized, remember: false);
        await c.send();
        expect(c.turns.single.personalized!.status, state.$1);
        expect(c.turns.single.personalized!.reason, state.$2);
        expect(c.turns.single.personalized!.answer, isNull);
        expect(c.input.text, '입력을 유지할 질문');
        expect(c.selectedRecords.single.version, 3);
        c.dispose();
        p.dispose();
      },
    );
  }
  test('personalized grounded answer carries distinct school and personal citations', () async {
    final api = Api()
      ..personalizedResponse = {
        'query_id': 'q',
        'status': 'grounded',
        'reason': 'generated_from_separated_evidence',
        'official': false,
        'answer': '학교 안내와 선택한 봉사 기록을 구분한 설명입니다.',
        'school': {
          'query_id': 's',
          'status': 'evidence_found',
          'reason': 'approved_sources_found',
          'sources': [
            {
              'chunk_id': 'chunk',
              'document_id': 'document',
              'title': '학교 안내',
              'source_url': 'https://example.invalid/source',
              'page': 1,
              'excerpt': '학교 안내 문장',
            },
          ],
        },
        'personal': {
          'official': false,
          'records': [
            {
              'kind': 'activity',
              'record_id': 'activity-id',
              'version': 3,
              'origin': 'personal',
              'official': false,
              'title': '봉사 기록',
              'text': '선택한 봉사 기록',
              'truncated': false,
            },
          ],
        },
        'school_chunk_ids': ['chunk'],
        'personal_citations': [
          {
            'kind': 'activity',
            'record_id': 'activity-id',
            'version': 3,
            'excerpt': '선택한 봉사 기록',
          },
        ],
      };
    final p = await permissions(), c = conversation(api, p);
    c.setMode(AssistantMode.personalized);
    await c.refreshRecords();
    c.selectRecord(record.key, true);
    c.input.text = '설명 요청';
    await c.permit(AssistantMode.personalized, remember: false);
    await c.send();
    final result = c.turns.single.personalized!;
    expect(result.school.sources.single.chunkId, 'chunk');
    expect(result.personal.records.single.recordId, 'activity-id');
    expect(result.personalCitations.single.version, 3);
    expect(result.official, false);
    expect(c.input.text, isEmpty);
    c.dispose();
    p.dispose();
  });
  test('personalized missing selection blocks before network', () async {
    final api = Api(), p = await permissions();
    final c = conversation(api, p);
    c.setMode(AssistantMode.personalized);
    c.input.text = '기록 질문';
    await c.send();
    expect(api.calls, isEmpty);
    expect(c.submissionError, contains('기록을 선택'));
    expect(c.input.text, '기록 질문');
    c.dispose();
    p.dispose();
  });
  test(
    'unregistered personal profile never sends and preserves draft',
    () async {
      final api = Api(), p = await permissions();
      final c = conversation(api, p);
      c.setContext(const SchoolQueryContext(institution: '직접 등록한 학교'));
      c.input.text = '질문';
      await c.send();
      expect(api.calls, isEmpty);
      expect(c.input.text, '질문');
      expect(c.submissionError, contains('등록된 학교'));
      c.dispose();
      p.dispose();
    },
  );
  test(
    'UUID route omits consent field and revocation blocks the next request',
    () async {
      final api = Api(), p = await permissions();
      final c = conversation(api, p);
      c.input.text = '학교 질문';
      await c.send();
      expect(api.calls, isEmpty);
      await p.setAllowed(AiConsentFeature.schoolQuestion, true);
      await c.send();
      expect(api.calls.single.$1, 'me/school-queries');
      expect(api.calls.single.$2!['context'], school.catalogJson());
      expect(
        api.calls.single.$2!.containsKey('external_processing_consent'),
        false,
      );
      await p.setAllowed(AiConsentFeature.schoolQuestion, false);
      c.input.text = '다음 질문';
      await c.send();
      expect(api.calls.length, 1);
      c.dispose();
      p.dispose();
    },
  );
  test(
    'mode switch keeps draft and personalized snapshots selected ID/version',
    () async {
      final api = Api(), p = await permissions();
      final c = conversation(api, p);
      c.input.text = '내 기록으로 설명';
      c.setMode(AssistantMode.personalized);
      await c.refreshRecords();
      c.selectRecord(record.key, true);
      expect(c.input.text, '내 기록으로 설명');
      await c.permit(AssistantMode.personalized, remember: false);
      await c.send();
      expect(api.calls.single.$1, 'me/personalized-guidance');
      expect(api.calls.single.$2!['records'], [
        {'kind': 'activity', 'record_id': 'activity-id', 'expected_version': 3},
      ]);
      expect(api.calls.single.$2!['external_processing_consent'], true);
      expect(c.turns.single.personalized!.status, 'evidence_only');
      expect(c.input.text, '내 기록으로 설명');
      c.setMode(AssistantMode.school);
      await c.retry(
        c.turns.single,
      ); // one-time permission consumed: no second request
      expect(api.calls.length, 1);
      await c.permit(AssistantMode.personalized, remember: false);
      await c.retry(c.turns.single);
      expect(api.calls.last.$1, 'me/personalized-guidance');
      c.dispose();
      p.dispose();
    },
  );
  test(
    '409 preserves draft and selection with safe request identifier',
    () async {
      final api = Api()
        ..failure = const AuthFailure(
          '다른 변경',
          status: 409,
          requestId: 'safe-id',
        );
      final p = await permissions(), c = conversation(api, p);
      c.input.text = '보존';
      c.setMode(AssistantMode.personalized);
      await c.refreshRecords();
      c.selectRecord(record.key, true);
      await c.permit(AssistantMode.personalized, remember: false);
      await c.send();
      expect(c.input.text, '보존');
      expect(c.selectedRecords.single.id, record.id);
      expect(c.turns.single.error!.requestId, 'safe-id');
      c.dispose();
      p.dispose();
    },
  );
  test('failed profile reload blocks use of stale context', () async {
    final api = Api(), p = await permissions();
    final c = conversation(api, p);
    await p.setAllowed(AiConsentFeature.schoolQuestion, true);
    c.setContextAvailable(false);
    c.input.text = '질문';
    await c.send();
    expect(api.calls, isEmpty);
    expect(c.submissionError, contains('프로필'));
    c.dispose();
    p.dispose();
  });
  test(
    'remote mode record permission and request remain owned by main',
    () async {
      final api = Api()..pending = Completer<Map<String, dynamic>>();
      final p = await permissions();
      final c = conversation(api, p);
      final updates = StreamController<Map<String, dynamic>>.broadcast(
        sync: true,
      );
      final bridge = ConversationBridge(c, (value) async => updates.add(value));
      final remote = RemoteConversation(
        request: (command) async =>
            command == null ? bridge.read() : bridge.command(command),
        changes: updates.stream,
      );
      await remote.load();
      expect(remote.registeredOnly, true);
      remote.setMode(AssistantMode.personalized);
      await remote.flush();
      await remote.refreshRecords();
      await Future<void>.delayed(Duration.zero);
      remote.selectRecord(record.key, true);
      await remote.flush();
      remote.input.text = '분리 질문';
      await remote.flush();
      expect(
        await remote.permit(AssistantMode.personalized, remember: false),
        true,
      );
      await remote.send();
      expect(api.calls.length, 1);
      expect(c.sending, true);
      remote.dispose();
      api.pending!.complete({
        'query_id': 'q',
        'status': 'evidence_only',
        'reason': 'generator_not_configured',
        'official': false,
        'school': {
          'query_id': 's',
          'status': 'insufficient_evidence',
          'reason': 'no_approved_matching_evidence',
        },
        'personal': {'records': [], 'official': false},
      });
      await Future<void>.delayed(Duration.zero);
      expect(c.turns.single.personalized!.status, 'evidence_only');
      expect(api.calls.length, 1);
      bridge.dispose();
      c.dispose();
      p.dispose();
      await updates.close();
    },
  );
  testWidgets('registered panel offers modes and shows evidence-only safely', (
    tester,
  ) async {
    final api = Api(), p = await permissions();
    final c = conversation(api, p);
    c.setMode(AssistantMode.personalized);
    await c.refreshRecords();
    c.selectRecord(record.key, true);
    c.input.text = '질문';
    await c.permit(AssistantMode.personalized, remember: false);
    await c.send();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 480,
            height: 850,
            child: AssistantPanel(conversation: c, onClose: () {}, width: 480),
          ),
        ),
      ),
    );
    expect(find.widgetWithText(ChoiceChip, '내 자료로 질문'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration!.labelText,
      '내 자료로 질문',
    );
    expect(find.text('학교 문서'), findsOneWidget);
    expect(find.text('내 기록'), findsOneWidget);
    expect(find.textContaining('답변 생성 준비 중'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    p.dispose();
  });
}
