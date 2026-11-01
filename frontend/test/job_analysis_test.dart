import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/main.dart';

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
        const UniversityPathApp(startAuthenticated: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('채용공고 분석'));
      await tester.pumpAndSettle();
      expect(find.textContaining('학생용 채용 분석 API가 아직 없습니다'), findsOneWidget);
      expect(find.textContaining('비교할 공고 텍스트와 주소가 없습니다'), findsOneWidget);
      expect(find.text('답변: 받은 답변 없음'), findsOneWidget);
      expect(find.text('근거: 받은 근거 없음'), findsOneWidget);
      expect(find.text('불확실한 부분: 받은 내용 없음'), findsOneWidget);
      expect(find.text('분석 실행 불가 · 연결 전'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('job-posting-text')),
        '합성 채용공고 본문',
      );
      await tester.enterText(
        find.byKey(const ValueKey('job-posting-url')),
        '공고주소',
      );
      await tester.pump();
      expect(find.textContaining('주소가 http:// 또는 https://'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('job-posting-url')),
        'https://example.test/jobs/1',
      );
      await tester.tap(
        find.byKey(const ValueKey('job-record-activity/job-act')),
      );
      await tester.pumpAndSettle();
      expect(find.text('선택한 기록 1개'), findsOneWidget);
      await tester.tap(find.text('자료'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('채용공고 분석').first);
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
            .widget<TextFormField>(
              find.byKey(const ValueKey('job-posting-url')),
            )
            .controller!
            .text,
        'https://example.test/jobs/1',
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
