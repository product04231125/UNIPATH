import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:university_path_frontend/features/assistant/assistant_api.dart';
import 'package:university_path_frontend/features/assistant/assistant_conversation.dart';
import 'package:university_path_frontend/features/assistant/assistant_panel.dart';
import 'package:university_path_frontend/features/assistant/detached_chat_page.dart';
import 'package:university_path_frontend/features/assistant/remote_school_profile.dart';

Map<String, Object?> result({
  String status = 'insufficient_evidence',
  String reason = 'no_approved_matching_evidence',
  Object? answer,
  List<Object?> citations = const [],
  List<String> missing = const [],
}) => {
  'query_id': '280b7c97-4827-4b7b-baf8-11359d316b99',
  'status': status,
  'reason': reason,
  'answer': answer,
  'citations': citations,
  'missing_fields': missing,
};
http.Response response(Map<String, Object?> body, [int code = 200]) =>
    http.Response(
      jsonEncode(body),
      code,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
const school = SchoolQueryContext(
  institution: '합성대학교',
  department: '합성학과',
  admissionYear: 2026,
  track: 'single_major',
);

void main() {
  test(
    'sends only snake_case question/context and reads Korean response',
    () async {
      final api = AssistantApi(
        baseUrl: Uri.parse('http://localhost:8010'),
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(
            request.url.toString(),
            'http://localhost:8010/api/v1/assistant/queries',
          );
          expect(jsonDecode(request.body), {
            'question': '사회봉사 조건은?',
            'context': {
              'institution': '합성대학교',
              'department': '합성학과',
              'admission_year': 2026,
              'track': 'single_major',
            },
          });
          return response(result());
        }),
      );
      final value = await api.query('사회봉사 조건은?', school);
      expect(value.label, '공식 근거 부족');
      expect(value.answer, isNull);
      api.close();
    },
  );

  for (final malformed in [
    result(status: 'invented'),
    result(status: 'grounded', answer: '임의 답변'),
    result(answer: '근거 없이 노출하면 안 되는 답변'),
    result(
      status: 'grounded',
      answer: '답변',
      citations: [
        {
          'chunk_id': 'id',
          'document_id': 'id',
          'title': '문서',
          'source_url': 'javascript:alert(1)',
          'page': 1,
          'excerpt': '본문',
        },
      ],
    ),
  ]) {
    test(
      'invalid response is rejected: ${malformed['status']} ${malformed['answer']}',
      () async {
        final api = AssistantApi(
          client: MockClient((_) async => response(malformed)),
        );
        await expectLater(
          api.query('질문', school),
          throwsA(
            isA<AssistantApiException>().having(
              (e) => e.message,
              'safe message',
              isNot(contains('임의 답변')),
            ),
          ),
        );
        api.close();
      },
    );
  }

  test(
    '422 parses common error fields and request id without echoing input',
    () async {
      final api = AssistantApi(
        client: MockClient(
          (_) async => response({
            'error': {
              'code': 'VALIDATION_ERROR',
              'message': 'synthetic-sensitive-input',
              'request_id': 'request-id',
              'field_errors': [
                {'field': 'body.context.admission_year', 'reason': 'int_type'},
              ],
            },
          }, 422),
        ),
      );
      await expectLater(
        api.query('질문', school),
        throwsA(
          isA<AssistantApiException>()
              .having((e) => e.fields, 'fields', [
                'body.context.admission_year',
              ])
              .having((e) => e.requestId, 'request id', 'request-id')
              .having(
                (e) => e.message,
                'safe message',
                isNot(contains('synthetic-sensitive-input')),
              ),
        ),
      );
      api.close();
    },
  );
  test('network and timeout failures become recoverable messages', () async {
    for (final timeout in [false, true]) {
      final api = AssistantApi(
        timeout: const Duration(milliseconds: 1),
        client: MockClient((_) {
          if (timeout) return Completer<http.Response>().future;
          throw http.ClientException('private-provider-detail');
        }),
      );
      await expectLater(
        api.query('질문', school),
        throwsA(
          isA<AssistantApiException>().having(
            (e) => e.message,
            'redaction',
            isNot(contains('private-provider-detail')),
          ),
        ),
      );
      api.close();
    }
  });

  test('blocks duplicate send, preserves failure draft, retries same turn with amended context', () async {
    final pending = Completer<http.Response>();
    var calls = 0;
    final conversation = AssistantConversation(
      api: AssistantApi(
        client: MockClient((request) async {
          calls++;
          if (calls == 1) return pending.future;
          expect(jsonDecode(request.body)['context']['institution'], '합성대학교');
          return response(result());
        }),
      ),
    );
    conversation.input.text = '사회봉사 조건은?';
    final sending = conversation.send();
    await conversation.send();
    expect(conversation.turns.length, 1);
    pending.complete(
      response(result(status: 'failed', reason: 'rag_processing_failed')),
    );
    await sending;
    expect(conversation.input.text, '사회봉사 조건은?');
    conversation.setContext(school);
    await conversation.retry(conversation.turns.single);
    expect(conversation.turns.length, 1);
    expect(calls, 2);
    expect(conversation.input.text, isEmpty);
    conversation.dispose();
  });
  test('late completion after disposal is ignored', () async {
    final pending = Completer<http.Response>();
    final conversation = AssistantConversation(
      api: AssistantApi(client: MockClient((_) => pending.future)),
    );
    conversation.input.text = '질문';
    final sending = conversation.send();
    conversation.dispose();
    pending.complete(response(result()));
    await sending;
  });
  test(
    'typing a new draft during a request does not lose that draft',
    () async {
      final pending = Completer<http.Response>();
      final conversation = AssistantConversation(
        api: AssistantApi(client: MockClient((_) => pending.future)),
      );
      conversation.input.text = '첫 질문';
      final sending = conversation.send();
      conversation.input.text = '다음 질문';
      pending.complete(response(result()));
      await sending;
      expect(conversation.input.text, '다음 질문');
      conversation.dispose();
    },
  );

  testWidgets('context form validates year and sends confirmed scope', (
    tester,
  ) async {
    final requests = <Map<String, dynamic>>[];
    final conversation = AssistantConversation(
      api: AssistantApi(
        client: MockClient((r) async {
          requests.add(jsonDecode(r.body) as Map<String, dynamic>);
          return response(
            result(
              status: 'needs_user_input',
              reason: 'academic_scope_required',
              missing: ['track'],
            ),
          );
        }),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssistantPanel(
            conversation: conversation,
            width: 360,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('테스트용 설정창'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextFormField, '학교 (선택)'),
      '합성대학교',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '학과 (선택)'),
      '합성학과',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '입학연도 (선택)'),
      'true',
    );
    await tester.ensureVisible(find.text('질의에 사용'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('질의에 사용'));
    await tester.pump();
    expect(find.text('네 자리 입학연도를 입력해 주세요.'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, '입학연도 (선택)'),
      '2026',
    );
    await tester.ensureVisible(find.text('질의에 사용'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('질의에 사용'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '총 학점은?');
    await tester.tap(find.text('보내기'));
    await tester.pumpAndSettle();
    expect(requests.single['context'], {
      'institution': '합성대학교',
      'department': '합성학과',
      'admission_year': 2026,
      'track': null,
    });
    expect(find.text('필요한 정보: 이수경로'), findsOneWidget);
    expect(conversation.input.text, '총 학점은?');
    await tester.pumpWidget(const SizedBox());
    conversation.dispose();
  });

  for (final width in [220.0, 360.0, 480.0]) {
    testWidgets(
      'answer and source remain readable at width=$width and scale=2',
      (tester) async {
        final conversation = AssistantConversation(
          api: AssistantApi(
            client: MockClient(
              (_) async => response(
                result(
                  status: 'grounded',
                  reason: 'generated_from_evidence',
                  answer: '합성 문서에 근거한 설명',
                  citations: [
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
              ),
            ),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: SizedBox(
                  height: 520,
                  child: AssistantPanel(
                    conversation: conversation,
                    width: width,
                    onClose: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        conversation.input.text = '질문';
        await conversation.send();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('공식 문서 열기 · 새 창'),
          100,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('합성 학사규정 · 2페이지'), findsOneWidget);
        expect(find.text('합성 근거 원문'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        conversation.dispose();
      },
    );
  }
  testWidgets('detached window uses the same API, not mock answers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DetachedChatWindow(
          schoolProfileFactory: () =>
              RemoteSchoolProfile(request: (_) async => const {}),
          assistantFactory: () =>
              AssistantApi(client: MockClient((_) async => response(result()))),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '사회봉사 조건은?');
    await tester.tap(find.text('보내기'));
    await tester.pumpAndSettle();
    expect(find.text('공식 근거 부족'), findsOneWidget);
    expect(find.textContaining('AI 답변:'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
