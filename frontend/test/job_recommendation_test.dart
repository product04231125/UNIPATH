import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/features/api/academic_guidance_models.dart';
import 'package:university_path_frontend/features/api/job_recommendation_api.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/assistant/ai_record_catalog.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/auth/guest_preview_scope.dart';
import 'package:university_path_frontend/features/records/portfolio/job_recommendation_page.dart';
import 'package:university_path_frontend/features/records/portfolio/job_recommendation_result.dart';
import 'package:university_path_frontend/features/settings/ai_consent_preferences.dart';
import 'package:university_path_frontend/shared/app_style.dart';

Map<String, dynamic> responseFixture() => jsonDecode(
  File('test/fixtures/job_recommendation_response.json').readAsStringSync(),
) as Map<String, dynamic>;

Map<String, dynamic> displayCandidateFixture(String type) {
  final json = responseFixture();
  final item = json['items'][0] as Map<String, dynamic>;
  final recommendation = json['recommendations'][0] as Map<String, dynamic>;
  final posting = item['posting'] as Map<String, dynamic>;
  posting.addAll({'title': '웹 서비스 개발자', 'company': '예시소프트', 'location': '서울'});
  final failed = type == 'analysis_unavailable';
  final needsReview = type == 'closest_needs_review';
  final notice = switch (type) {
    'closest_needs_review' => '선택한 자료로 필수조건 충족을 확인하지 못했습니다.',
    'analysis_unavailable' => '직무가 일치하는 공고를 찾았지만 비교를 완료하지 못했습니다.',
    _ => '선택한 자료에서 공고와 일치하는 근거를 확인했습니다.',
  };
  if (needsReview) {
    recommendation['matched_requirements'] = [];
    item['comparisons'][0]['status'] = 'insufficient_evidence';
    item['comparisons'][0]['personal_evidence'] = [];
    item['comparisons'][0]['explanation'] = '선택한 자료에 Python 사용 기록이 없습니다.';
    (item['warnings'] as List).add(notice);
  }
  if (failed) {
    item['comparisons'] = [];
    item['analysis_status'] = 'failed';
    item['failure_reason'] = 'model_timeout';
    json['recommendations'] = [];
  }
  recommendation['recommendation_type'] = type;
  json['display_candidates'] = [
    {
      'posting': posting,
      'display_type': type,
      'analysis_status': item['analysis_status'],
      'notice': notice,
      'stage_guidance': {
        'sentences': failed
            ? [
                '공고와 자료의 비교가 완료되지 않아 현재 역량을 판단할 수 없습니다.',
                '분석 실패나 자료 부족을 역량 부족으로 해석하지 마세요.',
                '분석을 다시 시도하고 공고 원문과 제출 자료를 함께 확인하세요.',
              ]
            : [
                needsReview
                    ? '현재 제출 자료에서는 공고 조건을 충족하는 근거가 확인되지 않습니다.'
                    : '제출 자료에서 1개 조건의 충족 근거가 확인됩니다.',
                needsReview
                    ? '우선 확인할 격차는 Python 사용 경험입니다.'
                    : '분석한 조건에서 추가로 확인할 격차가 없습니다.',
                '남은 학기에는 실무 프로젝트 경험과 지원 서류를 정리하세요.',
              ],
      },
    },
  ];
  return json;
}

const record = AiRecordOption(
  kind: 'experience',
  id: 'record-id',
  version: 2,
  title: '선택한 경험',
);

class RecommendationGateway extends ApiGateway {
  final calls = <Map<String, Object?>>[];
  Object? failure;
  Completer<Map<String, dynamic>>? pending;
  Map<String, dynamic> result = {'status': 'not_configured'};
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    expect(method, 'POST');
    expect(path, 'me/job-recommendations');
    calls.add(body!);
    if (failure != null) throw failure!;
    return pending == null ? result : await pending!.future;
  }
}

Future<AiConsentPreferences> permission({bool allowed = true}) async {
  final value = AiConsentPreferences(
    ownerId: 'owner',
    reader: (_) async => null,
    writer: (_, _) async => true,
  );
  await value.load();
  if (allowed) await value.setAllowed(AiConsentFeature.jobRecommendation, true);
  return value;
}

Future<void> mount(
  WidgetTester tester,
  RecommendationGateway api,
  AiConsentPreferences consent, {
  Future<List<XFile>> Function()? pickFiles,
  bool guest = false,
  String owner = 'owner',
  Future<List<AiRecordOption>> Function()? loadRecords,
  Future<List<AssistantMaterial>> Function()? loadMaterials,
  Future<List<GuidanceDocument>> Function(List<String> ids)? loadDocuments,
}) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: GuestPreviewScope(
        active: guest,
        child: Scaffold(
          body: JobRecommendationPage(
            api: StudentApi(api, ownerId: owner),
            consent: consent,
            pickFiles: pickFiles,
            loadRecords: loadRecords ?? () async => [record],
            loadMaterials: loadMaterials,
            loadDocuments: loadDocuments,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('recommend-keyword')),
    'Engineer',
  );
  await tester.tap(find.byKey(const ValueKey('recommend-region')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('전국').last);
  await tester.pumpAndSettle();
}

Future<void> run(WidgetTester tester) async {
  await tester.ensureVisible(find.text('분석 실행'));
  await tester.tap(find.text('분석 실행'));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets(
    'validates job count and sends only the selected academic stage',
    (tester) async {
      final api = RecommendationGateway();
      await mount(tester, api, await permission());
      await fill(tester);
      final keyword = find.byKey(const ValueKey('recommend-keyword'));
      final stage = find.byKey(const ValueKey('recommend-academic-stage'));
      await tester.enterText(keyword, 'A, B, C, D, E, F');
      await run(tester);
      expect(api.calls, isEmpty);
      expect(find.text('직무를 쉼표로 구분해 1~5개 입력하세요.'), findsOneWidget);
      await tester.ensureVisible(keyword);
      await tester.enterText(keyword, '프론트엔드, 백엔드, 전산실');
      await tester.ensureVisible(stage);
      await tester.tap(stage);
      await tester.pumpAndSettle();
      await tester.tap(find.text('4학년').last);
      await tester.pumpAndSettle();
      await run(tester);
      expect(api.calls.single['keyword'], '프론트엔드, 백엔드, 전산실');
      expect(api.calls.single['academic_stage'], 'year4');
      await tester.ensureVisible(stage);
      await tester.tap(stage);
      await tester.pumpAndSettle();
      await tester.tap(find.text('선택 안 함').last);
      await tester.pumpAndSettle();
      await run(tester);
      expect(api.calls.last.containsKey('academic_stage'), isFalse);
    },
  );

  testWidgets('shows display candidate states without duplicate cards', (
    tester,
  ) async {
    for (final (type, label) in [
      ('evidence_match', '근거가 확인된 후보'),
      ('closest_needs_review', '조건 확인 필요'),
      ('analysis_unavailable', '분석 미완료 · 검색 후보'),
      ('unknown', '후보 유형 확인 필요'),
    ]) {
      final json = displayCandidateFixture(type);
      final result = JobRecommendationResponse.fromJson(json);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: JobRecommendationResult(result: result),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
      expect(find.text('웹 서비스 개발자'), findsOneWidget);
      expect(find.text('원 공고 · 외부 열기'), findsOneWidget);
      expect(find.text('함께 비교한 공고'), findsNothing);
      expect(find.textContaining('추천 공고가 없습니다.'), findsNothing);
      expect(
        find.text('왜 추천됐나요?'),
        type == 'evidence_match' ? findsOneWidget : findsNothing,
      );
      expect(
        find.textContaining('미확인 필수조건'),
        type == 'evidence_match' ? findsOneWidget : findsNothing,
      );
      for (final sentence
          in result.displayCandidates!.single.guidanceSentences) {
        expect(find.text(sentence), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'candidate postings can be displayed without comparison details',
    (tester) async {
      final json = displayCandidateFixture('analysis_unavailable');
      json['items'] = [];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: JobRecommendationResult(
                result: JobRecommendationResponse.fromJson(json),
              ),
            ),
          ),
        ),
      );
      expect(find.text('웹 서비스 개발자'), findsOneWidget);
      expect(find.text('원 공고 · 외부 열기'), findsOneWidget);
      expect(find.text('전체 요건과 비교 근거'), findsNothing);
    },
  );

  testWidgets(
    'posts attached files and all current records with explicit consent; never replays a pending request',
    (tester) async {
      final api = RecommendationGateway()..pending = Completer();
      final consent = await permission();
      final records = [
        for (var i = 0; i < 21; i++)
          AiRecordOption(
            kind: 'experience',
            id: 'id-$i',
            version: 2,
            title: '경험 $i',
          ),
      ];
      await mount(
        tester,
        api,
        consent,
        loadRecords: () async => records,
        pickFiles: () async => [
          XFile.fromData(
            Uint8List.fromList(utf8.encode('Synthetic portfolio')),
            path: 'portfolio.txt',
          ),
        ],
      );
      await fill(tester);
      await tester.tap(find.text('기기 파일 선택'));
      await tester.pumpAndSettle();
      await tester.pump();
      await tester.ensureVisible(find.text('분석 실행'));
      await tester.tap(find.text('분석 실행'));
      await tester.pump();
      expect(api.calls.single, {
        'keyword': 'Engineer',
        'region': '전국',
        'documents': [
          {
            'filename': 'portfolio.txt',
            'content_base64': base64Encode(utf8.encode('Synthetic portfolio')),
          },
        ],
        'records': [
          for (final record in records)
            {
              'kind': record.kind,
              'record_id': record.id,
              'expected_version': record.version,
            },
        ],
        'external_processing_consent': true,
        'limit': 3,
      });
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      api.pending!.complete({'status': 'not_configured'});
      await tester.pumpAndSettle();
      expect(api.calls, hasLength(1));
      expect(find.textContaining('서버 분석 설정이 필요'), findsOneWidget);
    },
  );

  testWidgets('selected 내 자료 travel with attached files', (tester) async {
    final api = RecommendationGateway()..pending = Completer();
    final consent = await permission();
    await mount(
      tester,
      api,
      consent,
      loadMaterials: () async => const [
        AssistantMaterial(id: 'm1', title: '합성 포트폴리오', type: '포트폴리오'),
      ],
      loadDocuments: (ids) async => [
        GuidanceDocument(
          filename: '합성.txt',
          contentBase64: base64Encode(utf8.encode('Synthetic material')),
        ),
      ],
    );
    await fill(tester);
    final box = find.byKey(const ValueKey('job-recommendation-material-m1'));
    await tester.ensureVisible(box);
    await tester.tap(box);
    await tester.pump();
    await run(tester);
    expect(api.calls.single['documents'], [
      {
        'filename': '합성.txt',
        'content_base64': base64Encode(utf8.encode('Synthetic material')),
      },
    ]);
    api.pending!.complete({'status': 'not_configured'});
    await tester.pumpAndSettle();
  });

  testWidgets('cancel consent sends nothing and preserves search input', (
    tester,
  ) async {
    final api = RecommendationGateway();
    final consent = await permission(allowed: false);
    await mount(tester, api, consent);
    await fill(tester);
    await run(tester);
    expect(find.text('내 자료로 공고 찾기 외부 전송'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);
    expect(find.text('Engineer'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
  });

  testWidgets(
    'missing conditions, missing materials and oversized files do not request',
    (tester) async {
      final api = RecommendationGateway();
      final consent = await permission();
      await mount(
        tester,
        api,
        consent,
        loadRecords: () async => [],
        pickFiles: () async => [
          XFile.fromData(
            Uint8List(recommendationMaxBytes + 1),
            path: 'large.pdf',
          ),
        ],
      );
      await run(tester);
      expect(api.calls, isEmpty);
      expect(find.text('근무 지역을 선택하세요.'), findsOneWidget);
      await fill(tester);
      await run(tester);
      expect(
        find.text('기기 파일이나 내 자료를 고르거나 활동·경험·자격·성과 기록을 등록해 주세요.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('기기 파일 선택'));
      await tester.tap(find.text('기기 파일 선택'));
      await tester.pumpAndSettle();
      expect(find.textContaining('합계 8MiB 이하로 선택'), findsOneWidget);
      expect(api.calls, isEmpty);
    },
  );

  testWidgets(
    '404 preserves inputs and reports endpoint or selected-resource absence',
    (tester) async {
      final api = RecommendationGateway()
        ..failure = const AuthFailure(
          '없음',
          status: 404,
          requestId: 'synthetic-id',
        );
      await mount(tester, api, await permission());
      await fill(tester);
      await run(tester);
      expect(find.textContaining('공고 추천 API가 연결되지 않았거나'), findsOneWidget);
      expect(find.text('Engineer'), findsOneWidget);
      expect(find.text('문의 식별자: synthetic-id'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
    },
  );

  testWidgets(
    'record read failures preserve attachments; files work without records; guest never sends',
    (tester) async {
      final api = RecommendationGateway();
      final consent = await permission();
      var fail = true;
      await mount(
        tester,
        api,
        consent,
        loadRecords: () async {
          if (fail) throw Exception('record failure');
          return [];
        },
        pickFiles: () async => [
          XFile.fromData(Uint8List.fromList([65]), path: 'a.txt'),
        ],
      );
      await fill(tester);
      await tester.tap(find.text('기기 파일 선택'));
      await tester.pumpAndSettle();
      await run(tester);
      expect(api.calls, isEmpty);
      expect(find.textContaining('저장 기록을 읽지 못했습니다'), findsOneWidget);
      expect(find.text('a.txt'), findsOneWidget);
      fail = false;
      await run(tester);
      expect(api.calls.single['records'], isEmpty);
      await mount(tester, api, consent, guest: true);
      await tester.ensureVisible(find.text('분석 실행'));
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(api.calls, hasLength(1));
    },
  );

  testWidgets(
    'account replacement discards a late result and clears selected content',
    (tester) async {
      final api = RecommendationGateway()..pending = Completer();
      final consent = await permission();
      await mount(tester, api, consent);
      await fill(tester);
      await tester.ensureVisible(find.text('분석 실행'));
      await tester.tap(find.text('분석 실행'));
      await tester.pump();
      await mount(tester, api, consent, owner: 'replacement');
      api.pending!.complete(responseFixture());
      await tester.pumpAndSettle();
      expect(find.text('Engineer'), findsNothing);
      expect(find.text('전국'), findsNothing);
      expect(find.text('공고 비교 결과'), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
    },
  );

  testWidgets(
    'partial recommendations show OCR citations and keep failures separate from zero matches',
    (tester) async {
      final json = responseFixture();
      (json['document_locations'] as Map).values.first['method'] = 'ocr';
      final parsed = JobRecommendationResponse.fromJson(json);
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: JobRecommendationResult(result: parsed),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('사람인 · 설정 필요'), findsOneWidget);
      await tester.tap(find.text('왜 추천됐나요?'));
      await tester.pumpAndSettle();
      expect(find.text('내 자료: private-name.pdf · 1쪽'), findsOneWidget);
      expect(find.text('자동 문자 인식 · 원본 확인'), findsOneWidget);
      json['recommendations'] = [];
      json['items'][0]['analysis_status'] = 'failed';
      json['items'][0]['failure_reason'] = 'posting_quote';
      (json['sources'] as List).add({
        'source': 'greenhouse',
        'status': 'failed',
        'reason': 'source_failed',
        'failure_reason': 'http_503',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: JobRecommendationResult(
                result: JobRecommendationResponse.fromJson(json),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('추천 공고가 없습니다'), findsOneWidget);
      expect(find.text('처리 실패'), findsOneWidget);
      expect(
        find.text(
          'AI가 공고 문장을 정확히 인용하지 못했습니다. 잠시 후 다시 시도해 주세요. (코드: posting_quote)',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('(코드: http_503)'), findsOneWidget);
      expect(
        recommendationFailureLabel('output_missing_personal_evidence'),
        startsWith('AI 응답 형식이 맞지 않았습니다.'),
      );
    },
  );

  testWidgets(
    'capture desktop input and result states in all themes and enlarged text',
    (tester) async {
      if (!const bool.fromEnvironment('PR69_CAPTURE')) return;
      await (FontLoader('Pretendard')..addFont(
            rootBundle.load('assets/fonts/pretendard/Pretendard-Regular.otf'),
          ))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final output = Directory('../output/pr69-frontend/visuals')
        ..createSync(recursive: true);
      Future<void> capture(
        String name,
        Widget child,
        AppPalette palette, {
        double scale = 1,
      }) async {
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: universityPathTheme(palette: palette),
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(1440, 1000),
                textScaler: TextScaler.linear(scale),
              ),
              child: RepaintBoundary(
                key: boundary,
                child: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(24),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (name == 'partial') {
          await tester.tap(find.text('왜 추천됐나요?'));
          await tester.pumpAndSettle();
        }
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${output.path}/${palette.name}-$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox());
      }

      final json = responseFixture();
      (json['document_locations'] as Map).values.first['method'] = 'ocr';
      for (final palette in AppPalette.values) {
        await capture(
          'input',
          JobRecommendationPage(
            api: StudentApi(RecommendationGateway(), ownerId: 'owner'),
            consent: await permission(),
            loadRecords: () async => [record],
          ),
          palette,
        );
        await capture(
          'partial',
          SingleChildScrollView(
            child: JobRecommendationResult(
              result: JobRecommendationResponse.fromJson(json),
            ),
          ),
          palette,
        );
      }
      await capture(
        'enlarged-input',
        JobRecommendationPage(loadRecords: () async => []),
        AppPalette.orange,
        scale: 2,
      );
      json['recommendations'] = [];
      json['items'][0]['analysis_status'] = 'failed';
      await capture(
        'zero-with-failure',
        SingleChildScrollView(
          child: JobRecommendationResult(
            result: JobRecommendationResponse.fromJson(json),
          ),
        ),
        AppPalette.cream,
      );
    },
  );
}
