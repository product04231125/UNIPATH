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
import 'package:university_path_frontend/features/career/career_goal.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/assistant/ai_record_catalog.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/auth/guest_preview_scope.dart';
import 'package:university_path_frontend/features/records/portfolio/job_recommendation_page.dart';
import 'package:university_path_frontend/features/records/portfolio/job_recommendation_result.dart';
import 'package:university_path_frontend/features/settings/ai_consent_preferences.dart';
import 'package:university_path_frontend/shared/app_style.dart';

import 'package:university_path_frontend/features/career/requirement_result.dart';

import 'support/saved_analyses_store.dart';

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
  final saved = SavedAnalysesStore();
  final calls = <Map<String, Object?>>[];
  int categoryCalls = 0;
  Object? categoryFailure;
  Completer<Map<String, dynamic>>? pendingCategories;
  Object? failure;
  Completer<Map<String, dynamic>>? pending;
  Map<String, dynamic> result = {'status': 'not_configured'};
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    if (SavedAnalysesStore.handles(path)) {
      return saved.handle(method, path, body);
    }
    if (method == 'GET' && path == 'me/job-categories') {
      categoryCalls++;
      if (categoryFailure != null) throw categoryFailure!;
      return pendingCategories == null
          ? categoryFixture
          : await pendingCategories!.future;
    }
    expect(method, 'POST');
    expect(path, 'me/job-recommendations');
    calls.add(body!);
    if (failure != null) throw failure!;
    return pending == null ? result : await pending!.future;
  }
}

const categoryFixture = {
  'categories': [
    {
      'code': '02',
      'name': '연구 및 공학기술',
      'children': [
        {'code': '024', 'name': '소프트웨어'},
      ],
    },
    {
      'code': '03',
      'name': '교육',
      'children': [
        {'code': '031', 'name': '학교 교사'},
      ],
    },
  ],
};

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
  CareerGoal? goal,
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
            goal: goal,
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
  await selectOption(tester, 'recommend-region', '전국');
}

Future<void> selectOption(WidgetTester tester, String key, String label) async {
  final field = find.byKey(ValueKey(key));
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> run(WidgetTester tester) async {
  await tester.ensureVisible(find.text('분석 실행'));
  await tester.tap(find.text('분석 실행'));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('직종 단독 검색과 세부 검색어, 상위 직종 변경을 처리한다', (tester) async {
    final api = RecommendationGateway()
      ..result = {
        'status': 'completed',
        'query': {'occupation_label': '소프트웨어'},
        'search_notice': '고른 직종에서 ‘프론트엔드’와 맞는 공고를 찾지 못했습니다. 다른 세부 검색어로 찾거나 직종 전체 공고를 볼 수 있습니다.',
        'sources': [
          {
            'source': 'saramin',
            'status': 'skipped',
            'reason': 'category_unsupported',
          },
        ],
      };
    final p = await permission();
    addTearDown(p.dispose);
    await mount(tester, api, p);
    await selectOption(tester, 'recommend-region', '전국');
    await run(tester);
    expect(api.calls, isEmpty);
    expect(find.text('직종을 선택하거나 세부 검색어를 입력하세요.'), findsOneWidget);

    await selectOption(tester, 'recommend-category', '연구 및 공학기술');
    await run(tester);
    expect(api.calls.single['category_codes'], ['02']);
    expect(api.calls.single['keyword'], '');

    await selectOption(tester, 'recommend-subcategory-02', '소프트웨어');
    await tester.enterText(
      find.byKey(const ValueKey('recommend-keyword')),
      '프론트엔드',
    );
    await run(tester);
    expect(api.calls.last['category_codes'], ['024']);
    expect(api.calls.last['keyword'], '프론트엔드');
    expect(find.text('검색 직종 · 소프트웨어'), findsOneWidget);
    expect(
      find.text(
        '고른 직종에서 ‘프론트엔드’와 맞는 공고를 찾지 못했습니다. 다른 세부 검색어로 찾거나 직종 전체 공고를 볼 수 있습니다.',
      ),
      findsOneWidget,
    );
    expect(find.text('사람인 · 직종 검색 미지원'), findsOneWidget);

    await selectOption(tester, 'recommend-category', '교육');
    await run(tester);
    expect(api.calls.last['category_codes'], ['03']);

    await selectOption(tester, 'recommend-category', '선택 안 함');
    await run(tester);
    expect(api.calls.last, isNot(contains('category_codes')));
    expect(api.calls.last['keyword'], '프론트엔드');
  });

  testWidgets('세부 검색어 0건이면 학생이 직종 전체 보기를 고른다', (tester) async {
    final api = RecommendationGateway()
      ..result = {
        'status': 'no_results',
        'query': {
          'keyword': '프런트엔드',
          'occupation_codes': ['024'],
          'occupation_label': '소프트웨어',
        },
        'search_notice': '고른 직종에서 ‘프런트엔드’와 맞는 공고를 찾지 못했습니다. 다른 세부 검색어로 찾거나 직종 전체 공고를 볼 수 있습니다.',
        'category_browse_available': true,
        'sources': [
          {'source': 'work24', 'status': 'completed'},
        ],
        'items': [],
      };
    final p = await permission();
    addTearDown(p.dispose);
    await mount(tester, api, p);
    await selectOption(tester, 'recommend-region', '전국');
    await selectOption(tester, 'recommend-category', '연구 및 공학기술');
    await selectOption(tester, 'recommend-subcategory-02', '소프트웨어');
    await tester.enterText(
      find.byKey(const ValueKey('recommend-keyword')),
      '프런트엔드',
    );
    await run(tester);
    await tester.pumpAndSettle();
    final browse = find.byKey(const ValueKey('recommend-browse-category'));
    expect(find.text('검색 직종 · 소프트웨어'), findsOneWidget);
    expect(browse, findsOneWidget);
    // The server never substitutes postings; nothing runs until the student chooses.
    expect(api.calls, hasLength(1));

    // A different category in the form no longer matches the empty result.
    await selectOption(tester, 'recommend-category', '교육');
    expect(browse, findsNothing);
    await selectOption(tester, 'recommend-category', '연구 및 공학기술');
    await selectOption(tester, 'recommend-subcategory-02', '소프트웨어');
    expect(browse, findsOneWidget);

    api.result = {
      'status': 'completed',
      'query': {
        'keyword': '',
        'occupation_codes': ['024'],
        'occupation_label': '소프트웨어',
      },
      'search_notice': null,
      'category_browse_available': false,
      'sources': [
        {'source': 'work24', 'status': 'completed'},
      ],
    };
    await tester.ensureVisible(browse);
    await tester.tap(browse);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(api.calls, hasLength(2));
    expect(api.calls.last['keyword'], '');
    expect(api.calls.last['category_codes'], ['024']);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('recommend-keyword')),
          )
          .controller!
          .text,
      '',
    );
    expect(find.text('검색 직종 · 소프트웨어 · 세부 검색어 없음'), findsOneWidget);
    expect(browse, findsNothing);
  });

  testWidgets('저장한 목표 직무로 검색 조건을 채운다', (tester) async {
    final api = RecommendationGateway();
    final p = await permission();
    addTearDown(p.dispose);
    await mount(
      tester,
      api,
      p,
      goal: const CareerGoal(
        categoryCodes: ['024'],
        keyword: '프론트엔드',
        version: 1,
        categoryLabel: '소프트웨어',
      ),
    );
    expect(find.text('소프트웨어'), findsOneWidget);
    expect(find.text('프론트엔드'), findsOneWidget);
    await selectOption(tester, 'recommend-region', '전국');
    await run(tester);
    expect(api.calls.single['category_codes'], ['024']);
    expect(api.calls.single['keyword'], '프론트엔드');
  });

  testWidgets('직종 조회 실패에서 검색어 검색과 재시도를 제공한다', (tester) async {
    final api = RecommendationGateway()
      ..categoryFailure = const AuthFailure('synthetic');
    final p = await permission();
    addTearDown(p.dispose);
    await mount(tester, api, p);
    final retry = find.text('직종 목록을 불러오지 못했습니다. 다시 시도');
    expect(retry, findsOneWidget);
    await fill(tester);
    await run(tester);
    expect(api.calls.single['keyword'], 'Engineer');
    expect(api.calls.single, isNot(contains('category_codes')));

    api.categoryFailure = null;
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(api.categoryCalls, 2);
    expect(retry, findsNothing);
    expect(find.text('Engineer'), findsOneWidget);
    await selectOption(tester, 'recommend-category', '교육');
  });

  testWidgets('계정이 바뀌면 늦게 도착한 이전 직종 목록을 표시하지 않는다', (tester) async {
    final old = RecommendationGateway()..pendingCategories = Completer();
    final p = await permission();
    addTearDown(p.dispose);
    await mount(tester, old, p);
    final next = RecommendationGateway();
    await mount(tester, next, p, owner: 'next');
    old.pendingCategories!.complete({
      'categories': [
        {'code': '01', 'name': '이전 응답'},
      ],
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('recommend-category')));
    await tester.pumpAndSettle();
    expect(find.text('이전 응답'), findsNothing);
    expect(find.text('교육'), findsOneWidget);
  });

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
      expect(find.text('세부 검색어를 쉼표로 구분해 1~5개 입력하세요.'), findsOneWidget);
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

  test('every compared posting is ranked with its own verdict', () {
    final json = responseFixture();
    final base = (json['items'] as List).first as Map<String, dynamic>;
    Map<String, dynamic> item(
      String id,
      List<(String, String)> rows, {
      String status = 'completed',
    }) {
      final copy = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
      (copy['posting'] as Map)['source_id'] = id;
      (copy['posting'] as Map)['title'] = '공고 $id';
      copy['analysis_status'] = status;
      final template = (base['comparisons'] as List).first as Map;
      copy['comparisons'] = [
        for (final (i, (priority, state)) in rows.indexed)
          {
            ...jsonDecode(jsonEncode(template)) as Map<String, dynamic>,
            'requirement_id': '$id-$i',
            'priority': priority,
            'status': state,
            if (state != 'supported') 'personal_evidence': [],
          },
      ];
      return copy;
    }

    json['items'] = [
      item('failed', [], status: 'failed'),
      item('none', [('required', 'insufficient_evidence')]),
      item('preferred-only', [
        ('required', 'partially_supported'),
        ('preferred', 'supported'),
      ]),
      item('match', [('required', 'supported'), ('preferred', 'supported')]),
      // Saved before every 필수 was required: the server still listed it as a match.
      item('half', [
        ('required', 'supported'),
        ('required', 'insufficient_evidence'),
      ]),
    ];
    final recommended = json['recommendations'] as List;
    recommended.first['source_id'] = 'match';
    recommended.add({
      ...jsonDecode(jsonEncode(recommended.first)) as Map<String, dynamic>,
      'source_id': 'half',
    });
    final ranked = rankPostings(JobRecommendationResponse.fromJson(json));
    expect(ranked.map((p) => p.posting.id), [
      'match',
      'half',
      'preferred-only',
      'none',
      'failed',
    ]);
    expect(ranked.map((p) => p.verdict), [
      PostingVerdict.recommended,
      PostingVerdict.closest,
      PostingVerdict.requiredMissing,
      PostingVerdict.noEvidence,
      PostingVerdict.unavailable,
    ]);
    expect(ranked.first.reason, '필수 요건 1개를 모두 갖춰 추천했습니다.');
    expect(ranked[1].required, (1, 2));
    expect(ranked[1].reason, contains('확인되지 않은 필수 요건: 「'));
    expect(ranked[2].required, (0, 1));
    expect(ranked[2].reason, contains('추천에서 제외'));
  });

  testWidgets('several regions and 졸업예정 are sent with the search', (
    tester,
  ) async {
    final api = RecommendationGateway();
    final consent = await permission();
    await mount(tester, api, consent);
    await tester.enterText(
      find.byKey(const ValueKey('recommend-keyword')),
      'Engineer',
    );
    Future<void> chip(String name) async {
      final finder = find.byKey(ValueKey('recommend-region-$name'));
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pump();
    }

    bool selected(String name) => tester
        .widget<FilterChip>(find.byKey(ValueKey('recommend-region-$name')))
        .selected;
    await chip('전국');
    await chip('경기');
    // A region replaces 전국; picking 전국 again clears the regions.
    expect(selected('전국'), isFalse);
    await chip('서울');
    expect(selected('경기') && selected('서울'), isTrue);
    await selectOption(tester, 'recommend-academic-stage', '졸업예정');
    await run(tester);
    expect(api.calls.single['regions'], ['서울', '경기']);
    expect(api.calls.single['region'], '서울·경기');
    expect(api.calls.single['academic_stage'], 'graduating');
    await chip('전국');
    expect(selected('서울') || selected('경기'), isFalse);
    expect(selected('전국'), isTrue);
  });

  testWidgets('shows display candidate states without duplicate cards', (
    tester,
  ) async {
    for (final (type, label) in [
      ('evidence_match', '추천'),
      ('closest_needs_review', '조건 확인 필요'),
      ('analysis_unavailable', '분석 미완료'),
      // An unknown type is judged by its comparisons, never shown as recommended.
      ('unknown', '조건 확인 필요'),
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
        find.byType(ReadinessBar),
        type == 'analysis_unavailable' ? findsNothing : findsOneWidget,
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

  testWidgets('a search with postings is saved and opened again', (
    tester,
  ) async {
    final api = RecommendationGateway()
      ..result = displayCandidateFixture('evidence_match');
    final consent = await permission();
    await mount(tester, api, consent);
    await fill(tester);
    await run(tester);
    await tester.pumpAndSettle();
    final saved = api.saved.items.single;
    expect(saved['kind'], 'search');
    expect(saved['summary'], {
      'postings': (api.result['items'] as List).length,
    });
    expect((saved['input'] as Map)['region'], isNotEmpty);
    expect(saved['result'], api.result);
    expect(
      find.byKey(const ValueKey('saved-analysis-current-star')),
      findsOneWidget,
    );
    final row = find.byKey(const ValueKey('saved-analysis-saved-0'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recommend-opened')), findsOneWidget);
    expect(find.text('웹 서비스 개발자'), findsOneWidget);
    expect(api.calls, hasLength(1));
  });

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
        find.text('기기 파일이나 내 자료를 고르거나 수강·활동·경험·자격·성과 기록을 등록해 주세요.'),
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
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const ValueKey('recommend-region-전국')),
            )
            .selected,
        isFalse,
      );
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
      expect(find.text('분석 미완료'), findsOneWidget);
      expect(find.text('추천'), findsNothing);
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
