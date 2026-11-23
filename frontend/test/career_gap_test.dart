import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/assistant/ai_record_catalog.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/career/career_gap.dart';
import 'package:university_path_frontend/features/career/career_gap_summary_card.dart';
import 'package:university_path_frontend/features/career/career_gap_view.dart';
import 'package:university_path_frontend/features/career/career_goal.dart';
import 'package:university_path_frontend/features/settings/ai_consent_preferences.dart';

import 'job_recommendation_test.dart' show categoryFixture;
import 'support/saved_analyses_store.dart';

const record = AiRecordOption(
  kind: 'course',
  id: 'course-id',
  version: 1,
  title: '웹프로그래밍',
);

Map<String, dynamic> completed() => {
  'status': 'completed',
  'goal': {
    'category_codes': ['024'],
    'keyword': '프론트엔드',
    'label': '소프트웨어',
  },
  'postings': [
    for (final n in [1, 2])
      {
        'posting': n,
        'source': 'work24',
        'source_id': 'K$n',
        'title': '합성 프론트엔드 개발자 $n',
        'company': '합성 회사',
        'location': '서울',
        'url': 'https://www.work24.go.kr/synthetic/$n',
        'closing_label': '채용시까지',
        'expires_at': null,
      },
  ],
  'requirements': [
    {
      'requirement_id': 'r1',
      'requirement': '정보처리기사',
      'category': 'certificate',
      'frequency': 2,
      'postings': [
        {'posting': 1, 'excerpt': '우대: 정보처리기사'},
        {'posting': 2, 'excerpt': '정보처리기사 소지자'},
      ],
      'status': 'insufficient_evidence',
      'personal_evidence': [],
      'explanation': '두 공고 모두 정보처리기사를 우대합니다.',
      'actions': [
        {
          'type': 'certificate',
          'title': '정보처리기사 필기',
          'detail': '필기 기출 3회분 풀이',
          'weeks': 6,
        },
      ],
    },
    {
      'requirement_id': 'r2',
      'requirement': 'React 경험',
      'category': 'skill',
      'frequency': 1,
      'postings': [
        {'posting': 1, 'excerpt': 'React 실무 경험'},
      ],
      'status': 'supported',
      'personal_evidence': [
        {
          'kind': 'course',
          'record_id': 'course-id',
          'version': 1,
          'excerpt': 'React 과제',
        },
      ],
      'explanation': '수업 과제에서 React를 다뤘습니다.',
      'actions': [],
    },
  ],
  'summary': '자격증 준비가 가장 필요합니다.',
  'warnings': ['목표 직무 공고가 2건만 수집되어 공통 요건이 적게 나올 수 있습니다.'],
  'generated_at': '2026-11-23T03:00:00+00:00',
};

class GapGateway extends ApiGateway {
  final saved = SavedAnalysesStore();
  final posts = <Map<String, Object?>>[];
  final results = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    if (SavedAnalysesStore.handles(path)) {
      return saved.handle(method, path, body);
    }
    if (path == 'me/job-categories') return categoryFixture;
    if (path == 'me/career-goal') {
      return {
        'category_codes': ['024'],
        'keyword': '프론트엔드',
        'version': 1,
        'category_label': '소프트웨어',
      };
    }
    expect((method, path), ('POST', 'me/career-gap-analyses'));
    posts.add(body!);
    return results.removeAt(0);
  }
}

Future<(GapGateway, List<(GapAction, GapRequirement, DateTime)>)> mountGap(
  WidgetTester tester, {
  List<Map<String, dynamic>> results = const [],
  Map<String, String> saved = const {},
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final api = GapGateway()..results.addAll(results);
  final consent = AiConsentPreferences(
    ownerId: 'owner',
    reader: (_) async => null,
    writer: (_, _) async => true,
  );
  await consent.load();
  await consent.setAllowed(AiConsentFeature.careerGap, true);
  addTearDown(consent.dispose);
  final goal = CareerGoalController(api);
  addTearDown(goal.dispose);
  await goal.load();
  final storage = {...saved};
  final plans = <(GapAction, GapRequirement, DateTime)>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CareerGapView(
          api: StudentApi(api, ownerId: 'owner'),
          consent: consent,
          careerGoal: goal,
          store: GapReportStore(
            ownerId: 'owner',
            reader: (key) async => storage[key],
            writer: (key, value) async {
              storage[key] = value;
              return true;
            },
          ),
          loadRecords: () async => [record],
          now: () => DateTime(2026, 11, 23),
          onAddPlan: (action, requirement, date) async =>
              plans.add((action, requirement, date)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (api, plans);
}

Future<void> runAnalysis(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('career-gap-run')));
  await tester.tap(find.byKey(const ValueKey('career-gap-run')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('목표 직무 분석은 모든 기록을 보내고 요건·준비 계획을 보여 준다', (tester) async {
    final (api, plans) = await mountGap(tester, results: [completed()]);
    expect(find.text('소프트웨어 · 프론트엔드'), findsOneWidget);
    await runAnalysis(tester);
    expect(api.posts.single, {
      'records': [
        {'kind': 'course', 'record_id': 'course-id', 'expected_version': 1},
      ],
      'category_codes': [],
      'keyword': '',
      'external_processing_consent': true,
    });
    expect(find.text('정보처리기사'), findsOneWidget);
    expect(find.text('준비 필요'), findsOneWidget);
    expect(find.text('공고 2건 중 2건'), findsOneWidget);
    expect(find.text('내 기록 근거: React 과제'), findsOneWidget);
    expect(find.text('준비 제안 · 자격증 · 정보처리기사 필기 · 약 6주'), findsOneWidget);
    expect(find.text('Q-Net에서 확인 · 외부 열기'), findsOneWidget);
    expect(find.text('자격증 준비가 가장 필요합니다.'), findsOneWidget);
    // Saved automatically; opening it again marks it as a saved result.
    final saved = api.saved.items.single;
    expect(saved['kind'], 'gap');
    expect(saved['title'], '소프트웨어 · 프론트엔드');
    expect((saved['summary'] as Map)['total'], isA<int>());
    final row = find.byKey(const ValueKey('saved-analysis-saved-0'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.textContaining('(저장된 결과)'), findsOneWidget);
    expect(api.posts, hasLength(1));

    final add = find.text('일정에 추가');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    // Default target day: today + 6 weeks.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(plans.single.$1.title, '정보처리기사 필기');
    expect(plans.single.$3, DateTime(2027, 1, 4));
    expect(find.text('1월 4일 일정에 추가했습니다.'), findsOneWidget);
  });

  testWidgets('공고가 없으면 직종 전체 분석을 학생이 고른다', (tester) async {
    final (api, _) = await mountGap(
      tester,
      results: [
        {
          'status': 'no_postings',
          'goal': {
            'category_codes': ['024'],
            'keyword': '프론트엔드',
          },
          'search_notice': '고른 직종에서 ‘프론트엔드’와 맞는 공고를 찾지 못했습니다.',
          'category_browse_available': true,
        },
        completed(),
      ],
    );
    await runAnalysis(tester);
    expect(api.posts, hasLength(1));
    final whole = find.byKey(const ValueKey('career-gap-whole-category'));
    await tester.ensureVisible(whole);
    await tester.tap(whole);
    await tester.pumpAndSettle();
    expect(api.posts.last['category_codes'], ['024']);
    expect(api.posts.last['keyword'], '');
    expect(find.text('정보처리기사'), findsOneWidget);
  });

  testWidgets('최근 분석은 기기에 남아 홈 요약에 쓰인다', (tester) async {
    final report = ValueNotifier<GapReport?>(GapReport.fromJson(completed()));
    addTearDown(report.dispose);
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CareerGapSummaryCard(
            report: report,
            onOpen: () => opened = true,
          ),
        ),
      ),
    );
    expect(find.text('정보처리기사'), findsOneWidget);
    expect(find.byTooltip('공고 2건 중 2건이 요구'), findsOneWidget);
    expect(find.text('요건 2개 중 준비됨 1 · 일부 0 · 준비 필요 1'), findsOneWidget);
    await tester.tap(find.text('자세히 보기'));
    expect(opened, isTrue);
  });

  test('기기 저장소는 실패해도 분석을 막지 않는다', () async {
    final store = GapReportStore(
      ownerId: 'owner',
      reader: (_) async => '{broken',
      writer: (_, _) async => throw const AuthFailure('x'),
    );
    expect(await store.load(), isNull);
    await store.save(GapReport.fromJson(completed()));
  });
}
