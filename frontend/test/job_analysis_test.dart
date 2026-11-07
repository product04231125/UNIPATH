import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/portfolio/job_analysis_page.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('posting PNG validation checks the complete signature', () {
    expect(
      () => validateJobPostingFile(
        'notice.png',
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]),
      ),
      throwsStateError,
    );
    expect(
      () => validateJobPostingFile(
        'notice.png',
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
      ),
      returnsNormally,
    );
  });

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
      final courses = PersonalRecordRepository(PersonalRecordKind.course);
      await courses.load();
      await courses.save(
        PersonalRecord(id: 'job-course', values: {'title': '수강만 있는 과목'}),
      );
      await tester.pumpWidget(
        const UniversityPathApp(startAuthenticated: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('채용공고 분석'));
      await tester.pumpAndSettle();
      expect(find.text('수강'), findsNothing);
      expect(find.text('수강만 있는 과목'), findsNothing);
      expect(
        find.byKey(const ValueKey('job-record-course/job-course')),
        findsNothing,
      );
      expect(find.textContaining('로그인한 계정의 분석 연결이 필요합니다'), findsOneWidget);
      expect(
        find.textContaining('공고 텍스트, 주소, PDF·캡처 중 하나가 필요합니다'),
        findsOneWidget,
      );
      expect(find.text('답변: 받은 답변 없음'), findsOneWidget);
      expect(find.text('근거: 받은 근거 없음'), findsOneWidget);
      expect(find.text('불확실한 부분: 받은 내용 없음'), findsOneWidget);
      expect(find.text('분석 실행'), findsOneWidget);
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
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('job-record-activity/job-act')));
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

  testWidgets('job analysis empty copy guides activity experience credential portfolio', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: JobAnalysisPage())),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('활동·경험·자격·성과 메뉴에서 기록을 추가한 뒤 다시 열어 주세요'),
      findsOneWidget,
    );
    expect(find.textContaining('활동·수강·자격'), findsNothing);
    expect(find.text('수강'), findsNothing);
    expect(tester.takeException(), isNull);
  });

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
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        name: 'notice.png',
        path: 'notice.png',
        mimeType: 'image/png',
      );
      await tester.tap(find.byKey(const ValueKey('job-posting-file')));
      await tester.pumpAndSettle();
      expect(find.textContaining('notice.png'), findsOneWidget);
      expect(find.textContaining('중 하나가 필요합니다'), findsNothing);
      expect(find.textContaining('로그인한 계정의 분석 연결이 필요합니다'), findsOneWidget);
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
