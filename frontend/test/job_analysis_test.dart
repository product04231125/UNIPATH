import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/assistant/ai_record_catalog.dart';
import 'package:university_path_frontend/features/records/portfolio/job_analysis_page.dart';
import 'package:university_path_frontend/features/settings/ai_consent_preferences.dart';

class AnalysisGateway extends ApiGateway {
  final calls = <Map<String, Object?>>[];
  Object? failure;
  Map<String, dynamic> result = {
    'analysis_id': 'a',
    'status': 'not_configured',
    'reason': 'analyzer_not_configured',
    'official': false,
    'comparisons': [],
    'missing_fields': [],
  };
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    expect(path, 'me/job-analyses');
    calls.add(body!);
    if (failure != null) throw failure!;
    return result;
  }
}

const record = AiRecordOption(
  kind: 'experience',
  id: 'record-id',
  version: 2,
  title: '선택한 경험',
);
Future<AiConsentPreferences> consent() async {
  final p = AiConsentPreferences(
    ownerId: 'owner',
    reader: (_) async => null,
    writer: (_, _) async => true,
  );
  await p.load();
  return p;
}

Future<void> mount(
  WidgetTester tester,
  AnalysisGateway api,
  AiConsentPreferences p, {
  Future<List<AiRecordOption>> Function()? loadRecords,
}) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: JobAnalysisPage(
          api: StudentApi(api, ownerId: 'owner'),
          consent: p,
          loadRecords: loadRecords ?? () async => [record],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('job-posting-text')),
    '합성 공고 본문',
  );
  await tester.pump();
}

Future<void> execute(WidgetTester tester) async {
  await tester.ensureVisible(find.text('공고 분석'));
  await tester.tap(find.text('공고 분석'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sends all current records from the single analysis action', (
    tester,
  ) async {
    final options = [
      for (var i = 0; i < 21; i++)
        AiRecordOption(kind: 'activity', id: 'r$i', version: 1, title: '활동 $i'),
    ];
    var loads = 0;
    final api = AnalysisGateway()
      ..failure = const AuthFailure(
        '길이 제한',
        status: 422,
        fields: ['body.records'],
      );
    final p = await consent();
    await p.setAllowed(AiConsentFeature.jobAnalysis, true);
    await mount(
      tester,
      api,
      p,
      loadRecords: () async {
        loads++;
        return options;
      },
    );
    expect(loads, 0);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('기록 다시 읽기'), findsNothing);
    await execute(tester);
    expect(loads, 1);
    expect(api.calls.single['records'], [
      for (final r in options)
        {'kind': r.kind, 'record_id': r.id, 'expected_version': r.version},
    ]);
    expect(find.textContaining('서버가 전체 기록 요청을 받아들이지 못했습니다'), findsOneWidget);
    expect(find.text('합성 공고 본문'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    p.dispose();
  });

  testWidgets('retries with the latest server records after a conflict', (
    tester,
  ) async {
    const updated = AiRecordOption(
      kind: 'experience',
      id: 'record-id',
      version: 3,
      title: '변경된 경험',
    );
    var options = [record];
    final api = AnalysisGateway()
      ..failure = const AuthFailure('변경', status: 409);
    final p = await consent();
    await p.setAllowed(AiConsentFeature.jobAnalysis, true);
    await mount(tester, api, p, loadRecords: () async => options);
    await execute(tester);
    expect(find.textContaining('최신 기록을 불러옵니다'), findsOneWidget);
    options = [updated];
    api.failure = null;
    await execute(tester);
    expect(api.calls.last['records'], [
      {'kind': 'experience', 'record_id': 'record-id', 'expected_version': 3},
    ]);
    expect(find.text('합성 공고 본문'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    p.dispose();
  });

  testWidgets(
    'existing analysis opens recommendation form and returns with text preserved',
    (tester) async {
      final api = AnalysisGateway(), p = await consent();
      await mount(tester, api, p);
      await tester.ensureVisible(find.text('내 자료로 공고 찾기'));
      await tester.tap(find.text('내 자료로 공고 찾기'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recommend-keyword')), findsOneWidget);
      expect(api.calls, isEmpty);
      final recommendationElement = tester.element(
        find.byKey(const ValueKey('recommend-keyword')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('recommend-keyword')),
        '초안 개발 직무',
      );
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.ensureVisible(find.text('공고 1개 비교'));
      await tester.tap(find.text('공고 1개 비교'));
      await tester.pumpAndSettle();
      expect(find.text('합성 공고 본문'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('job-purpose-search')),
      );
      await tester.tap(find.byKey(const ValueKey('job-purpose-search')));
      await tester.pumpAndSettle();
      expect(
        identical(
          tester.element(find.byKey(const ValueKey('recommend-keyword'))),
          recommendationElement,
        ),
        true,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('recommend-keyword')),
            )
            .controller!
            .text,
        '초안 개발 직무',
      );
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(api.calls, isEmpty);
    },
  );
  testWidgets(
    'text analysis works without school and preserves explicit selected version',
    (tester) async {
      final api = AnalysisGateway(), p = await consent();
      await p.setAllowed(AiConsentFeature.jobAnalysis, true);
      await mount(tester, api, p);
      await execute(tester);
      expect(api.calls.single, {
        'posting_text': '합성 공고 본문',
        'records': [
          {
            'kind': 'experience',
            'record_id': 'record-id',
            'expected_version': 2,
          },
        ],
        'documents': [],
        'external_processing_consent': true,
      });
      expect(find.text('분석 기능 준비 중'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('job-posting-text')),
            )
            .controller!
            .text,
        '합성 공고 본문',
      );
      // No placeholder inputs for methods that are not available.
      expect(find.byKey(const ValueKey('job-posting-url')), findsNothing);
      expect(find.byKey(const ValueKey('job-posting-file')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      p.dispose();
    },
  );
  testWidgets(
    'cancel consent sends nothing and one-time consent remains unsaved',
    (tester) async {
      final api = AnalysisGateway(), p = await consent();
      await mount(tester, api, p);
      await execute(tester);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(api.calls, isEmpty);
      await execute(tester);
      await tester.tap(find.text('이번만 허용'));
      await tester.pumpAndSettle();
      expect(api.calls.length, 1);
      expect(p.allows(AiConsentFeature.jobAnalysis), false);
      await tester.pumpWidget(const SizedBox());
      p.dispose();
    },
  );
  testWidgets('version conflict retains text and diagnostic identifier', (
    tester,
  ) async {
    final api = AnalysisGateway()
      ..failure = const AuthFailure('변경', status: 409, requestId: 'request-id');
    final p = await consent();
    await p.setAllowed(AiConsentFeature.jobAnalysis, true);
    await mount(tester, api, p);
    await execute(tester);
    expect(find.textContaining('저장 기록이 변경'), findsOneWidget);
    expect(find.text('문의 식별자: request-id'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('job-posting-text')))
          .controller!
          .text,
      '합성 공고 본문',
    );
    await tester.pumpWidget(const SizedBox());
    p.dispose();
  });
  testWidgets(
    'consent field rejection explains API mismatch and preserves input',
    (tester) async {
      final api = AnalysisGateway()
        ..failure = const AuthFailure(
          '입력값의 형식과 길이를 확인해 주세요.',
          status: 422,
          fields: ['body.external_processing_consent'],
          requestId: 'synthetic-request',
        );
      final p = await consent();
      await p.setAllowed(AiConsentFeature.jobAnalysis, true);
      await mount(tester, api, p);
      await execute(tester);
      expect(find.textContaining('앱과 서버의 API 버전을 확인'), findsOneWidget);
      expect(find.text('입력값의 형식과 길이를 확인해 주세요.'), findsNothing);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('job-posting-text')),
            )
            .controller!
            .text,
        '합성 공고 본문',
      );
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(api.calls.single['external_processing_consent'], true);
      expect(find.text('문의 식별자: synthetic-request'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      p.dispose();
    },
  );
  testWidgets(
    'completed shows the multiline explanation before its citations',
    (tester) async {
      final api = AnalysisGateway()
        ..result = {
          'analysis_id': 'a',
          'status': 'completed',
          'reason': 'compared_with_personal_evidence',
          'official': false,
          'missing_fields': [],
          'comparisons': [
            {
              'requirement_id': 'r',
              'priority': 'required',
              'requirement': '개발 경험',
              'status': 'supported',
              'posting_evidence': {'start': 0, 'end': 2, 'excerpt': '합성'},
              'personal_evidence': [
                {
                  'kind': 'experience',
                  'record_id': 'record-id',
                  'version': 2,
                  'excerpt': '프로젝트 경험',
                },
              ],
              'explanation': '직무 해석: 개발 경험\n다음 행동: 역할을 정리하세요.',
            },
          ],
        };
      final p = await consent();
      await p.setAllowed(AiConsentFeature.jobAnalysis, true);
      await mount(tester, api, p);
      await execute(tester);
      expect(find.text('분석 완료'), findsOneWidget);
      expect(find.text('근거 있음'), findsNothing);
      // The next step is highlighted; the posting quote and role reading
      // open under it on demand.
      final next = find.text('역할을 정리하세요.');
      expect(next, findsOneWidget);
      expect(find.text('공고 근거: 합성'), findsNothing);
      await tester.ensureVisible(find.text('공고 근거·직무 해석'));
      await tester.tap(find.text('공고 근거·직무 해석'));
      await tester.pumpAndSettle();
      final citation = find.text('공고 근거: 합성');
      expect(citation, findsOneWidget);
      expect(find.text('직무 해석 · 개발 경험'), findsOneWidget);
      expect(
        tester.getTopLeft(next).dy,
        lessThan(tester.getTopLeft(citation).dy),
      );
      expect(find.byKey(const ValueKey('readiness-summary')), findsOneWidget);
      expect(find.text('근거: 받은 근거 없음'), findsNothing);
      // Evidence is named by the record it came from.
      expect(find.text('선택한 경험 · 프로젝트 경험'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      p.dispose();
    },
  );
  for (final item in [
    ('needs_user_input', 'external_processing_consent_required', '추가 입력 필요'),
    ('insufficient_evidence', 'no_requirements_found', '분석 근거 부족'),
    ('failed', 'analysis_failed', '분석 실패'),
  ]) {
    testWidgets('analysis state ${item.$1} remains explicit', (tester) async {
      final api = AnalysisGateway()
        ..result = {
          'analysis_id': 'a',
          'status': item.$1,
          'reason': item.$2,
          'official': false,
          'comparisons': [],
          'missing_fields': [],
        };
      final p = await consent();
      await p.setAllowed(AiConsentFeature.jobAnalysis, true);
      await mount(tester, api, p);
      await execute(tester);
      expect(find.text(item.$3), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('job-posting-text')),
            )
            .controller!
            .text,
        '합성 공고 본문',
      );
      await tester.pumpWidget(const SizedBox());
      p.dispose();
    });
  }
}
