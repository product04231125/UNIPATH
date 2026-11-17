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
    'posts only chosen files and records with explicit consent; never replays a pending request',
    (tester) async {
      final api = RecommendationGateway()..pending = Completer();
      final consent = await permission();
      await mount(
        tester,
        api,
        consent,
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
      await tester.ensureVisible(find.text('선택한 경험'));
      await tester.tap(find.text('선택한 경험'));
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
          {
            'kind': 'experience',
            'record_id': 'record-id',
            'expected_version': 2,
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

  testWidgets('cancel consent sends nothing and preserves selection', (
    tester,
  ) async {
    final api = RecommendationGateway();
    final consent = await permission(allowed: false);
    await mount(tester, api, consent);
    await fill(tester);
    await tester.tap(find.text('선택한 경험'));
    await run(tester);
    expect(find.text('내 자료로 공고 찾기 외부 전송'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);
    expect(find.text('Engineer'), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );
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
      expect(find.text('기기 파일 또는 저장 기록을 하나 이상 선택하세요.'), findsOneWidget);
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
      await tester.tap(find.text('선택한 경험'));
      await run(tester);
      expect(find.textContaining('공고 추천 API가 연결되지 않았거나'), findsOneWidget);
      expect(find.text('Engineer'), findsOneWidget);
      expect(find.text('문의 식별자: synthetic-id'), findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
    },
  );

  testWidgets(
    'files alone work when record loading fails and guest never sends',
    (tester) async {
      final api = RecommendationGateway();
      final consent = await permission();
      await mount(
        tester,
        api,
        consent,
        loadRecords: () async => throw Exception('record failure'),
        pickFiles: () async => [
          XFile.fromData(Uint8List.fromList([65]), path: 'a.txt'),
        ],
      );
      await fill(tester);
      await tester.tap(find.text('기기 파일 선택'));
      await tester.pumpAndSettle();
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
      await tester.tap(find.text('선택한 경험'));
      await tester.ensureVisible(find.text('분석 실행'));
      await tester.tap(find.text('분석 실행'));
      await tester.pump();
      await mount(tester, api, consent, owner: 'replacement');
      api.pending!.complete(responseFixture());
      await tester.pumpAndSettle();
      expect(find.text('Engineer'), findsNothing);
      expect(find.text('전국'), findsNothing);
      expect(find.text('공고 비교 결과'), findsNothing);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
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
