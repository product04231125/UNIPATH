import 'package:university_path_frontend/features/settings/ai_consent_preferences.dart';
import 'package:university_path_frontend/features/assistant/ai_record_catalog.dart';

import 'dart:async';

import 'package:university_path_frontend/features/api/job_analysis_api.dart';
import 'package:university_path_frontend/features/api/academic_guidance_models.dart';
import 'package:university_path_frontend/features/api/job_analysis_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/personal_repository_scope.dart';
import 'package:university_path_frontend/features/records/portfolio/job_analysis_page.dart';
import 'package:university_path_frontend/features/writing/posting_link.dart';
import 'package:university_path_frontend/features/writing/writing_api.dart';

late AiConsentPreferences consent;
const id = '10000000-0000-4000-8000-000000000001';

class Records extends PersonalRecordRepository {
  Records(super.kind);
  @override
  Future<void> load() async {}
  @override
  List<PersonalRecord> get records => kind == PersonalRecordKind.activity
      ? [
          PersonalRecord(id: id, version: 3, values: {'title': '선택 봉사'}),
        ]
      : [];
}

class Gateway implements ApiGateway {
  final bodies = <Map<String, Object?>>[];
  final pending = <Completer<Map<String, dynamic>?>>[];
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) {
    expect(method, 'POST');
    expect(path, 'me/job-analyses');
    bodies.add(body!);
    final c = Completer<Map<String, dynamic>?>();
    pending.add(c);
    return c.future;
  }
}

Widget host(
  StudentApi api, {
  Future<List<AssistantMaterial>> Function()? loadMaterials,
  Future<List<GuidanceDocument>> Function(List<String> ids)? loadDocuments,
  WriteForPosting? onWrite,
}) => MaterialApp(
  home: PersonalRepositoryScope(
    records: (kind) => Records(kind),
    child: Scaffold(
      body: JobAnalysisPage(
        api: api,
        consent: consent,
        loadMaterials: loadMaterials,
        loadDocuments: loadDocuments,
        onWrite: onWrite,
        loadRecords: () async => [
          const AiRecordOption(
            kind: 'activity',
            id: id,
            version: 3,
            title: '선택 봉사',
          ),
        ],
      ),
    ),
  ),
);
Future<void> prepare(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('job-posting-text')),
    '공고 본문',
  );
}

Future<void> run(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('job-analysis-run'));
  await tester.ensureVisible(button);
  await tester.pump();
  expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
  await tester.tap(button);
  await tester.pump();
  expect(consent.allows(AiConsentFeature.jobAnalysis), true);
}

void main() {
  setUp(() {
    consent = AiConsentPreferences(
      ownerId: id,
      reader: (_) async => null,
      writer: (_, _) async => true,
    );
  });
  test('response cannot cite an unselected record version', () async {
    final gateway = Gateway();
    final pending = JobAnalysisApi(gateway).analyze(
      JobAnalysisRequest(
        postingText: '공고 본문',
        records: [
          PersonalEvidenceSelection(
            kind: 'activity',
            recordId: id,
            expectedVersion: 3,
          ),
        ],
      ),
    );
    final check = expectLater(pending, throwsFormatException);
    gateway.pending.single.complete({
      'analysis_id': id,
      'status': 'completed',
      'reason': 'compared_with_personal_evidence',
      'official': false,
      'missing_fields': [],
      'comparisons': [
        {
          'requirement_id': id,
          'priority': 'required',
          'requirement': '요건',
          'status': 'supported',
          'posting_evidence': {'start': 0, 'end': 2, 'excerpt': '공고'},
          'personal_evidence': [
            {
              'kind': 'activity',
              'record_id': id,
              'version': 4,
              'excerpt': '선택 봉사',
            },
          ],
          'explanation': '잘못된 버전',
        },
      ],
    });
    await check;
  });
  testWidgets('a late analysis never appears in a replaced owner session', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await consent.load();
    await consent.setAllowed(AiConsentFeature.jobAnalysis, true);
    final old = Gateway();
    await tester.pumpWidget(host(StudentApi(old, ownerId: id)));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    await prepare(tester);
    await run(tester);
    await tester.pumpWidget(host(StudentApi(Gateway(), ownerId: id)));
    await tester.pumpAndSettle();
    old.pending.single.complete({
      'analysis_id': id,
      'status': 'not_configured',
      'reason': 'analyzer_not_configured',
      'official': false,
      'comparisons': [],
      'missing_fields': [],
    });
    await tester.pumpAndSettle();
    expect(find.text('분석 기능 준비 중'), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('job-posting-text')))
          .controller!
          .text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected 내 자료 are sent and their citations are labelled', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await consent.load();
    await consent.setAllowed(AiConsentFeature.jobAnalysis, true);
    final gateway = Gateway();
    final requested = <List<String>>[];
    await tester.pumpWidget(
      host(
        StudentApi(gateway, ownerId: id),
        loadMaterials: () async => const [
          AssistantMaterial(id: 'm1', title: '합성 포트폴리오', type: '포트폴리오'),
        ],
        loadDocuments: (ids) async {
          requested.add(ids);
          return const [
            GuidanceDocument(filename: '합성.txt', contentBase64: 'Zm9v'),
          ];
        },
      ),
    );
    await tester.pumpAndSettle();
    await prepare(tester);
    final box = find.byKey(const ValueKey('job-analysis-material-m1'));
    await tester.ensureVisible(box);
    await tester.tap(box);
    await tester.pump();
    await run(tester);
    expect(requested, [
      ['m1'],
    ]);
    expect(gateway.bodies.single['documents'], [
      {'filename': '합성.txt', 'content_base64': 'Zm9v'},
    ]);
    const doc = '20000000-0000-4000-8000-000000000002';
    gateway.pending.single.complete({
      'analysis_id': id,
      'status': 'completed',
      'reason': 'compared_with_personal_evidence',
      'official': false,
      'missing_fields': [],
      'warnings': [],
      'document_sources': [
        {
          'record_id': doc,
          'filename': '합성.txt',
          'location': '본문',
          'ocr': false,
        },
      ],
      'comparisons': [
        {
          'requirement_id': id,
          'priority': 'required',
          'requirement': '요건',
          'status': 'supported',
          'posting_evidence': {'start': 0, 'end': 2, 'excerpt': '공고'},
          'personal_evidence': [
            {
              'kind': 'experience',
              'record_id': doc,
              'version': 1,
              'excerpt': '합성 근거',
            },
          ],
          'explanation': '직무 해석: 합성',
        },
      ],
    });
    await tester.pumpAndSettle();
    expect(find.text('내 자료 근거 (합성.txt · 본문): 합성 근거'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a compared posting opens 자기소개서·포트폴리오 with its requirements', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await consent.load();
    await consent.setAllowed(AiConsentFeature.jobAnalysis, true);
    final gateway = Gateway();
    final written = <(PostingLink, WritingType)>[];
    await tester.pumpWidget(
      host(
        StudentApi(gateway, ownerId: id),
        onWrite: (link, type) => written.add((link, type)),
      ),
    );
    await tester.pumpAndSettle();
    await prepare(tester);
    await run(tester);
    gateway.pending.single.complete({
      'analysis_id': id,
      'status': 'completed',
      'reason': 'compared_with_personal_evidence',
      'official': false,
      'missing_fields': [],
      'warnings': [],
      'comparisons': [
        {
          'requirement_id': id,
          'priority': 'required',
          'requirement': '봉사 경험',
          'status': 'supported',
          'posting_evidence': {'start': 0, 'end': 2, 'excerpt': '공고'},
          'personal_evidence': [
            {
              'kind': 'activity',
              'record_id': id,
              'version': 3,
              'excerpt': '선택 봉사',
            },
          ],
          'explanation': '봉사 기록이 있습니다.',
        },
      ],
    });
    await tester.pumpAndSettle();
    final portfolio = find.byKey(
      const ValueKey('job-analysis-write-portfolio'),
    );
    await tester.ensureVisible(portfolio);
    await tester.tap(portfolio);
    await tester.pumpAndSettle();
    final (link, type) = written.single;
    expect(type, WritingType.portfolio);
    expect(link.text, '공고 본문');
    expect(link.source, 'manual');
    expect(link.requirements.single.requirement, '봉사 경험');
    expect(link.requirements.single.records.single.recordId, id);
    expect(link.analyzedAt, isNotNull);
    expect(
      find.byKey(const ValueKey('job-analysis-write-cover_letter')),
      findsOneWidget,
    );
  });

  testWidgets('analysis notes are shown with the result', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await consent.load();
    await consent.setAllowed(AiConsentFeature.jobAnalysis, true);
    final gateway = Gateway();
    await tester.pumpWidget(host(StudentApi(gateway, ownerId: id)));
    await tester.pumpAndSettle();
    await prepare(tester);
    await run(tester);
    gateway.pending.single.complete({
      'analysis_id': id,
      'status': 'insufficient_evidence',
      'reason': 'no_requirements_found',
      'official': false,
      'comparisons': [],
      'missing_fields': [],
      'warnings': ['기록이 많아 이 공고와 관련이 높은 기록 1개만 비교했습니다(전체 2개).'],
    });
    await tester.pumpAndSettle();
    expect(find.text('분석 근거 부족'), findsOneWidget);
    expect(
      find.text('기록이 많아 이 공고와 관련이 높은 기록 1개만 비교했습니다(전체 2개).'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'text analysis pins selected versions, blocks duplicates, and preserves retry input',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await consent.load();
      await consent.setAllowed(AiConsentFeature.jobAnalysis, true);
      final gateway = Gateway();
      await tester.pumpWidget(host(StudentApi(gateway, ownerId: id)));
      await tester.pumpAndSettle();
      await prepare(tester);
      await run(tester);
      final body = Map<String, Object?>.of(gateway.bodies.single);
      // The fixture explicitly granted account-scoped consent before sending.
      expect(body.remove('external_processing_consent'), isTrue);
      expect(body, {
        'posting_text': '공고 본문',
        'records': [
          {'kind': 'activity', 'record_id': id, 'expected_version': 3},
        ],
        // Nothing from 내 자료 unless the student selects it.
        'documents': [],
      });
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('job-analysis-run')),
            )
            .onPressed,
        isNull,
      );
      gateway.pending.single.completeError(
        const AuthFailure('공고를 확인하세요.', status: 422, fields: ['posting_text']),
      );
      await tester.pumpAndSettle();
      expect(find.text('공고를 확인하세요.'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('job-posting-text')),
            )
            .controller!
            .text,
        '공고 본문',
      );
      await run(tester);
      expect(gateway.bodies, hasLength(2));
      gateway.pending.last.complete({
        'analysis_id': id,
        'status': 'not_configured',
        'reason': 'analyzer_not_configured',
        'official': false,
        'comparisons': [],
        'missing_fields': [],
      });
      await tester.pumpAndSettle();
      expect(find.text('분석 기능 준비 중'), findsOneWidget);
      expect(find.textContaining('분석 모델이 아직 설정되지 않았습니다'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
