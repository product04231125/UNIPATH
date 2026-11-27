import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/assistant/ai_record_catalog.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/career/certificate_lookup_view.dart';
import 'package:university_path_frontend/features/career/certificate_recommendation_view.dart';
import 'package:university_path_frontend/features/career/certificate_study_plan.dart';
import 'package:university_path_frontend/features/career/certificates.dart';
import 'package:university_path_frontend/features/settings/ai_consent_preferences.dart';

import 'support/saved_analyses_store.dart';

const summary = {
  'id': 'qnet-9738',
  'name': '사회복지사 1급',
  'kind': 'national_professional',
  'kind_label': '국가전문자격',
  'issuer': '한국산업인력공단',
  'grade': '사회복지사 1급',
  'field': '사회복지·종교',
};

Map<String, dynamic> schedule({bool upcoming = true}) => {
  'status': upcoming ? 'upcoming' : 'unpublished',
  'rounds': upcoming
      ? [
          {
            'name': '2027년도 25회',
            'events': [
              {
                'kind': 'registration',
                'label': '필기 접수',
                'start': '2026-12-07',
                'end': '2026-12-11',
              },
              {
                'kind': 'exam',
                'label': '필기 시험',
                'start': '2027-01-16',
                'end': '2027-01-16',
              },
            ],
          },
        ]
      : [],
  'reference_rounds': upcoming
      ? []
      : [
          {
            'name': '2026년 정기 기사 1회',
            'events': [
              {
                'kind': 'registration',
                'label': '필기 접수',
                'start': '2026-01-12',
                'end': '2026-01-15',
              },
            ],
          },
        ],
  'next_registration': upcoming
      ? {
          'kind': 'registration',
          'label': '필기 접수',
          'start': '2026-12-07',
          'end': '2026-12-11',
        }
      : null,
  'source': 'Q-Net 공개 API(한국산업인력공단)',
  'source_url': 'https://www.q-net.or.kr/synthetic',
  'checked_at': '2026-11-24',
};

class CertificateGateway extends ApiGateway {
  final calls = <(String, String, Map<String, Object?>?)>[];
  final saved = SavedAnalysesStore();
  Map<String, dynamic> recommendation = {};
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    if (SavedAnalysesStore.handles(path)) {
      return saved.handle(method, path, body);
    }
    calls.add((method, path, body));
    if (path.startsWith('me/certificates?')) {
      return {
        'items': [summary],
      };
    }
    if (path == 'me/certificates/qnet-9738') {
      return {
        ...summary,
        'official_url': 'https://www.q-net.or.kr/synthetic',
        'fee': '필기 25,000원',
        'method': '시험과목\n- 사회복지기초',
        'trend': null,
        'subjects': [],
        'eligibility_note': null,
        'schedule': schedule(),
      };
    }
    if (path == 'me/certificate-study-plans') {
      return {
        'status': 'completed',
        'exam_date': '2027-01-16',
        'scope': {
          'subjects': ['사회복지기초'],
          'source': 'Q-Net 공개 API(한국산업인력공단)',
        },
        'advice': '마지막 2주는 기출 위주로 복습합니다.',
        'weeks': [
          {
            'week': 1,
            'start': '2026-11-24',
            'end': '2026-11-30',
            'focus': '사회복지기초 개념 잡기',
            'subjects': ['사회복지기초'],
            'tasks': ['인간행동과 사회환경 정리'],
            'hours': 8,
            'related_records': ['합성 사회복지 실습'],
          },
        ],
      };
    }
    expect(path, 'me/certificate-recommendations');
    return recommendation;
  }
}

Future<void> wide(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('search, official schedule with D-day and adding events', (
    tester,
  ) async {
    await wide(tester);
    final api = CertificateGateway();
    final added = <(String, List<ScheduleEvent>)>[];
    final selection = CertificateSelection();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CertificateLookupView(
            api: StudentApi(api, ownerId: 'owner'),
            selection: selection,
            onAddEvents: (name, events) async => added.add((name, events)),
            now: () => DateTime(2026, 11, 24),
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('certificate-search')),
      '사회복지',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(
      api.calls.first.$2,
      'me/certificates?query=%EC%82%AC%ED%9A%8C%EB%B3%B5%EC%A7%80',
    );
    await tester.tap(
      find.byKey(const ValueKey('certificate-result-qnet-9738')),
    );
    await tester.pumpAndSettle();
    expect(find.text('다음 필기 접수 12월 7일 ~ 12월 11일 (D-13)'), findsOneWidget);
    expect(find.text('2027년도 25회'), findsOneWidget);
    expect(find.text('응시료 · 필기 25,000원'), findsOneWidget);
    expect(find.textContaining('출처 · Q-Net 공개 API'), findsOneWidget);

    final add = find.byKey(const ValueKey('certificate-add-events'));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.tap(find.text('필기 시험').last);
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('certificate-add-events-confirm')),
    );
    await tester.pumpAndSettle();
    expect(added.single.$1, '사회복지사 1급');
    expect(added.single.$2.map((e) => e.label), ['필기 접수']);
    await tester.pumpWidget(const SizedBox());
    selection.dispose();
  });

  testWidgets(
    'recommendations show posting evidence, held certificates and schedules',
    (tester) async {
      await wide(tester);
      final api = CertificateGateway()
        ..recommendation = {
          'status': 'completed',
          'goal': {'label': '사회복지', 'keyword': ''},
          'gap_basis': {
            'analyzed_at': '2026-11-24T02:13:00+09:00',
            'gaps': 2,
            'postings': 3,
          },
          'held': ['정보처리기사'],
          'summary': '사회복지 현장 공고가 요구하는 자격입니다.',
          'recommendations': [
            {
              'certificate': summary,
              'reason': '공고 대부분이 요구합니다.',
              'requirements': ['사회복지사 1급'],
              'related_records': ['합성 사회복지 실습'],
              'timing': '4학년 겨울방학',
              'weeks': 10,
              'evidence': [
                {'requirement': '사회복지사 1급', 'frequency': 3},
              ],
              'schedule': schedule(),
            },
            {
              'certificate': {...summary, 'id': 'qnet-1320', 'name': '정보처리기사'},
              'reason': '행정 전산화 업무에 도움이 됩니다.',
              'requirements': [],
              'related_records': [],
              'evidence': [],
              'schedule': schedule(upcoming: false),
            },
          ],
        };
      final consent = AiConsentPreferences(
        ownerId: 'owner',
        reader: (_) async => null,
        writer: (_, _) async => true,
      );
      await consent.load();
      await consent.setAllowed(
        AiConsentFeature.certificateRecommendation,
        true,
      );
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CertificateRecommendationView(
              api: StudentApi(api, ownerId: 'owner'),
              consent: consent,
              loadRecords: () async => const [
                AiRecordOption(
                  kind: 'course',
                  id: 'record-id',
                  version: 2,
                  title: '합성 사회복지 실습',
                ),
              ],
              onOpenSchedule: (c) => opened.add(c.id),
              now: () => DateTime(2026, 11, 24),
            ),
          ),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('certificate-academic-stage')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('4학년').last);
      await tester.pumpAndSettle();
      final run = find.byKey(const ValueKey('certificate-recommend-run'));
      await tester.ensureVisible(run);
      await tester.tap(run);
      await tester.pumpAndSettle();
      expect(api.calls.single.$3, {
        'records': [
          {'kind': 'course', 'record_id': 'record-id', 'expected_version': 2},
        ],
        'academic_stage': 'year4',
        'external_processing_consent': true,
      });
      expect(find.text('공고 3건 중 3건 · 사회복지사 1급'), findsOneWidget);
      expect(find.text('보유 자격 제외 · 정보처리기사'), findsOneWidget);
      expect(find.text('도움 되는 기록 · 합성 사회복지 실습'), findsOneWidget);
      expect(find.text('다음 필기 접수 12월 7일 ~ 12월 11일 (D-13)'), findsOneWidget);
      expect(find.text('다음 접수 일정 공개 전 · 지난 회차를 참고하세요'), findsOneWidget);
      final open = find.byKey(const ValueKey('certificate-open-schedule-1'));
      await tester.ensureVisible(open);
      await tester.tap(open);
      expect(opened, ['qnet-1320']);
      // The finished recommendation was kept in the account.
      final kept = api.saved.items.single;
      expect(kept['kind'], 'certificate');
      expect((kept['input'] as Map)['academic_stage'], 'year4');
      expect(
        (kept['summary'] as Map)['recommendations'],
        (api.recommendation['recommendations'] as List).length,
      );
      await tester.pumpWidget(const SizedBox());
      consent.dispose();
    },
  );

  testWidgets(
    'study plan targets the next official exam and adds weekly goals',
    (tester) async {
      await wide(tester);
      final api = CertificateGateway();
      final consent = AiConsentPreferences(
        ownerId: 'owner',
        reader: (_) async => null,
        writer: (_, _) async => true,
      );
      await consent.load();
      await consent.setAllowed(AiConsentFeature.certificateStudyPlan, true);
      final selection = CertificateSelection();
      final added = <(String, List<StudyWeek>)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CertificateLookupView(
              api: StudentApi(api, ownerId: 'owner'),
              selection: selection,
              consent: consent,
              loadRecords: () async => const [
                AiRecordOption(
                  kind: 'course',
                  id: 'record-id',
                  version: 1,
                  title: '합성 사회복지 실습',
                ),
              ],
              onAddStudyPlan: (name, weeks) async => added.add((name, weeks)),
              now: () => DateTime(2026, 11, 24),
            ),
          ),
        ),
      );
      selection.select(CertificateSummary.fromJson(summary));
      await tester.pumpAndSettle();
      expect(find.text('2027. 1. 16. (D-53)'), findsOneWidget);
      final run = find.byKey(const ValueKey('study-plan-run'));
      await tester.ensureVisible(run);
      await tester.tap(run);
      await tester.pumpAndSettle();
      final body = api.calls.last.$3!;
      expect(body['certificate_id'], 'qnet-9738');
      expect(body['exam_date'], '2027-01-16');
      expect(body['hours_per_week'], 8);
      expect(find.text('사회복지기초 개념 잡기'), findsOneWidget);
      expect(find.text('참고할 내 기록 · 합성 사회복지 실습'), findsOneWidget);
      final add = find.byKey(const ValueKey('study-plan-add'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(added.single.$1, '사회복지사 1급');
      expect(added.single.$2.single.week, 1);
      await tester.pumpWidget(const SizedBox());
      selection.dispose();
      consent.dispose();
    },
  );
}
