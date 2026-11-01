import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/portfolio/portfolio_page.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'job analysis keeps posting text and selected records without inventing results',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final activities = PersonalRecordRepository(PersonalRecordKind.activity);
      await activities.load();
      await activities.save(
        PersonalRecord(id: 'job-act', values: {'title': '선택한 봉사'}),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PortfolioPage(showMockData: false)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '채용공고 분석'));
      await tester.pumpAndSettle();
      expect(find.textContaining('분석 실행은 아직 연결되지 않았습니다'), findsWidgets);
      expect(find.text('분석 실행 불가 · 연결 전'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('job-posting-text')),
        '합성 채용공고 본문',
      );
      await tester.tap(
        find.byKey(const ValueKey('job-record-activity/job-act')),
      );
      await tester.pumpAndSettle();
      expect(find.text('선택한 기록 1개'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, '내 자료'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '채용공고 분석'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('job-posting-text')),
            )
            .controller!
            .text,
        '합성 채용공고 본문',
      );
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const ValueKey('job-record-activity/job-act')),
            )
            .value,
        isTrue,
      );
      expect(find.textContaining('합격'), findsNothing);
      expect(find.textContaining('분석 결과'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
