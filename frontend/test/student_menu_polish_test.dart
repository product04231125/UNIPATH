import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/portfolio/job_analysis_page.dart';
import 'package:university_path_frontend/features/records/portfolio/materials_page.dart';
import 'package:university_path_frontend/features/settings/ai_consent_preferences.dart';

import 'job_analysis_test.dart' as analysis;
import 'job_recommendation_test.dart' as recommendation;

class PendingRecommendation extends ApiGateway {
  final pending = Completer<Map<String, dynamic>>();
  int calls = 0;
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    if (method == 'GET' && path == 'me/job-categories') {
      return recommendation.categoryFixture;
    }
    expect(path, 'me/job-recommendations');
    expect(body?['records'], [
      {
        'kind': analysis.record.kind,
        'record_id': analysis.record.id,
        'expected_version': analysis.record.version,
      },
    ]);
    calls++;
    return pending.future;
  }
}

void main() {
  testWidgets(
    'long activity list keeps add reachable and row actions clear of chat',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = PersonalRecordRepository(PersonalRecordKind.activity);
      await repo.load();
      for (var i = 0; i < 24; i++) {
        await repo.save(
          PersonalRecord(
            id: 'item-$i',
            values: {
              'title': '검토용 활동 $i',
              'detail': '활동 내용과 증빙을 정리한 합성 메모입니다.',
              'reportedHours': '3',
            },
          ),
        );
      }
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const UniversityPathApp(startAuthenticated: true),
      );
      await tester.pumpAndSettle();
      // 활동 records are listed in 자료 › 내 자료.
      await tester.tap(find.text('자료').first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('자료 추가').hitTestable(), findsOneWidget);
      // Draft restore lives in the header's more menu next to add.
      expect(find.byTooltip('더보기').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('더보기'));
      await tester.pumpAndSettle();
      expect(find.text('임시저장 불러오기').hitTestable(), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      final chat = tester.getRect(find.byType(FloatingActionButton));
      final page = find.byType(MaterialsPage);
      for (var i = 0; i < 4; i++) {
        for (final element
            in find
                .descendant(of: page, matching: find.byType(TextButton))
                .hitTestable()
                .evaluate()) {
          expect(
            tester.getRect(find.byWidget(element.widget)).overlaps(chat),
            false,
          );
        }
        await tester.drag(page, const Offset(0, -260));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recommendation processing blocks purpose changes and does not replay on return',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final transport = PendingRecommendation();
      final consent = await analysis.consent();
      await consent.setAllowed(AiConsentFeature.jobRecommendation, true);
      addTearDown(consent.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JobAnalysisPage(
              api: StudentApi(transport, ownerId: 'owner'),
              consent: consent,
              loadRecords: () async => [analysis.record],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('job-purpose-search')),
      );
      await tester.tap(find.byKey(const ValueKey('job-purpose-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('recommend-keyword')),
        '개발',
      );
      await tester.tap(find.byKey(const ValueKey('recommend-region')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('전국').last);
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.ensureVisible(find.text('분석 실행'));
      await tester.tap(find.text('분석 실행'));
      await tester.pump();
      expect(transport.calls, 1);
      expect(
        tester
            .widget<InkWell>(find.byKey(const ValueKey('job-purpose-posting')))
            .onTap,
        isNull,
      );
      transport.pending.complete(recommendation.responseFixture());
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<InkWell>(find.byKey(const ValueKey('job-purpose-posting')))
            .onTap,
        isNotNull,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('job-purpose-posting')),
      );
      await tester.tap(find.byKey(const ValueKey('job-purpose-posting')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('job-purpose-search')),
      );
      await tester.tap(find.byKey(const ValueKey('job-purpose-search')));
      await tester.pumpAndSettle();
      expect(transport.calls, 1);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('recommend-keyword')),
            )
            .controller!
            .text,
        '개발',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
