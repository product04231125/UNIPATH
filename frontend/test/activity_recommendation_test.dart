import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/assistant/ai_record_catalog.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/career/activity_recommendation.dart';
import 'package:university_path_frontend/features/career/activity_recommendation_view.dart';
import 'package:university_path_frontend/features/settings/ai_consent_preferences.dart';

const record = AiRecordOption(
  kind: 'experience',
  id: 'record-id',
  version: 1,
  title: '합성 웹 프로젝트',
);

Map<String, dynamic> completed({bool withGap = true}) => {
  'status': 'completed',
  'official': false,
  'goal': {
    'category_codes': ['024'],
    'keyword': '프론트엔드',
    'label': '소프트웨어',
  },
  'gap_basis': {
    'analyzed_at': withGap ? '2026-11-24T02:13:00+09:00' : null,
    'gaps': withGap ? 2 : 0,
  },
  'summary': '배포와 협업 경험을 채우는 활동입니다.',
  'recommendations': [
    {
      'kind': 'hackathon',
      'kind_label': '해커톤',
      'title': '웹 서비스 해커톤 참가',
      'reason': '배포 경험이 부족해 짧은 기간에 서비스를 완성해 봅니다.',
      'requirements': ['Docker 배포 경험'],
      'keywords': ['웹 해커톤'],
      'sites': ['devpost'],
      'deliverable': '배포한 서비스 주소와 맡은 역할',
      'weeks': 2,
    },
  ],
  'sites': {
    'devpost': {'name': 'Devpost', 'url': 'https://devpost.com'},
  },
};

class ActivityGateway extends ApiGateway {
  final calls = <Map<String, Object?>>[];
  Map<String, dynamic> result = completed();
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    expect((method, path), ('POST', 'me/activity-recommendations'));
    calls.add(body!);
    return result;
  }
}

Future<AiConsentPreferences> consent() async {
  final p = AiConsentPreferences(
    ownerId: 'owner',
    reader: (_) async => null,
    writer: (_, _) async => true,
  );
  await p.load();
  await p.setAllowed(AiConsentFeature.activityRecommendation, true);
  return p;
}

Future<void> mount(
  WidgetTester tester,
  ActivityGateway api,
  AiConsentPreferences p, {
  AddActivityPlan? onAddPlan,
  VoidCallback? onOpenCareerGap,
}) async {
  await tester.binding.setSurfaceSize(const Size(1600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ActivityRecommendationView(
          api: StudentApi(api, ownerId: 'owner'),
          consent: p,
          loadRecords: () async => [record],
          onAddPlan: onAddPlan,
          onOpenCareerGap: onOpenCareerGap,
          now: () => DateTime(2026, 11, 24),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> run(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('activity-recommend-run'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sends all records and stage and shows the plan', (tester) async {
    final api = ActivityGateway();
    final p = await consent();
    final added = <(ActivityRecommendation, DateTime)>[];
    await mount(tester, api, p, onAddPlan: (a, d) async => added.add((a, d)));
    await tester.tap(find.byKey(const ValueKey('activity-academic-stage')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('졸업예정').last);
    await tester.pumpAndSettle();
    await run(tester);
    expect(api.calls.single, {
      'records': [
        {'kind': 'experience', 'record_id': 'record-id', 'expected_version': 1},
      ],
      'academic_stage': 'graduating',
      'external_processing_consent': true,
    });
    expect(find.text('웹 서비스 해커톤 참가'), findsOneWidget);
    expect(find.text('보완 · Docker 배포 경험'), findsOneWidget);
    expect(find.text('기록할 결과 · 배포한 서비스 주소와 맡은 역할'), findsOneWidget);
    expect(find.text('Devpost · 외부 열기'), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-gap-basis')), findsOneWidget);
    // No region input and no posting list: real postings live in 공고 찾기.
    expect(find.byKey(const ValueKey('activity-region-서울')), findsNothing);
    expect(find.textContaining('인턴·일경험 모집 공고'), findsNothing);

    final add = find.byKey(const ValueKey('activity-add-plan-0'));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    // Default target day: today + the suggested 2 weeks.
    expect(added.single.$1.title, '웹 서비스 해커톤 참가');
    expect(added.single.$2, DateTime(2026, 12, 8));
    await tester.pumpWidget(const SizedBox());
    p.dispose();
  });

  testWidgets('without a gap analysis it offers to run one first', (
    tester,
  ) async {
    final api = ActivityGateway()..result = completed(withGap: false);
    final p = await consent();
    var opened = 0;
    await mount(tester, api, p, onOpenCareerGap: () => opened++);
    await run(tester);
    expect(find.byKey(const ValueKey('activity-no-gap')), findsOneWidget);
    await tester.tap(find.text('목표 직무 분석'));
    expect(opened, 1);
    expect(api.calls.single.containsKey('regions'), isFalse);
    await tester.pumpWidget(const SizedBox());
    p.dispose();
  });

  testWidgets('missing goal and failures stay explicit', (tester) async {
    final api = ActivityGateway()
      ..result = {
        'status': 'needs_user_input',
        'missing_fields': ['career_goal'],
      };
    final p = await consent();
    await mount(tester, api, p);
    await run(tester);
    expect(find.text('목표 직무를 먼저 정해 주세요.'), findsOneWidget);
    api.result = {'status': 'failed', 'failure_reason': 'model_timeout'};
    await run(tester);
    expect(find.textContaining('응답 시간이 초과되었습니다.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    p.dispose();
  });
}
