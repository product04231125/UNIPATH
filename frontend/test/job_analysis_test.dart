import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/portfolio/job_analysis_page.dart';
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
      expect(
        find.textContaining('공고 텍스트, 주소, PDF·캡처 중 하나가 필요합니다'),
        findsOneWidget,
      );
      expect(find.text('답변: 받은 답변 없음'), findsOneWidget);
      expect(find.text('근거: 받은 근거 없음'), findsOneWidget);
      expect(find.text('불확실한 부분: 받은 내용 없음'), findsOneWidget);
      expect(find.text('분석 실행 불가 · 연결 전'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('job-posting-text')),
        '합성 채용공고 본문',
      );
      await tester.pump();
      expect(find.textContaining('중 하나가 필요합니다'), findsNothing);
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

  testWidgets(
    'a screenshot or pdf alone is enough and other files are refused',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      XFile? next;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: JobAnalysisPage(pickFile: () async => next)),
        ),
      );
      await tester.pumpAndSettle();
      next = XFile.fromData(
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]),
        name: 'notice.png',
        path: 'notice.png',
        mimeType: 'image/png',
      );
      await tester.tap(find.byKey(const ValueKey('job-posting-file')));
      await tester.pumpAndSettle();
      expect(find.textContaining('notice.png'), findsOneWidget);
      expect(find.textContaining('중 하나가 필요합니다'), findsNothing);
      expect(find.textContaining('학생용 채용 분석 API가 아직 없습니다'), findsOneWidget);
      expect(find.textContaining('합격'), findsNothing);

      next = XFile.fromData(
        Uint8List.fromList('%PDF-1.4'.codeUnits),
        name: 'notice.pdf',
        path: 'notice.pdf',
        mimeType: 'application/pdf',
      );
      await tester.tap(find.byKey(const ValueKey('job-posting-file')));
      await tester.pumpAndSettle();
      expect(find.textContaining('notice.pdf'), findsOneWidget);

      next = XFile.fromData(
        Uint8List.fromList('memo'.codeUnits),
        name: 'memo.txt',
        path: 'memo.txt',
      );
      await tester.tap(find.byKey(const ValueKey('job-posting-file')));
      await tester.pumpAndSettle();
      expect(find.textContaining('PDF 또는 캡처 이미지'), findsWidgets);
      expect(find.textContaining('notice.pdf'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('job-posting-file-clear')));
      await tester.pumpAndSettle();
      expect(find.textContaining('notice.pdf'), findsNothing);
      expect(find.textContaining('중 하나가 필요합니다'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
