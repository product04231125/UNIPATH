import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/records/course/course_page.dart';
import 'package:university_path_frontend/features/records/course/course_term.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';

Future<void> enter(WidgetTester tester, String key, String value) async {
  final input = find.byKey(ValueKey('record-field-$key'));
  await tester.ensureVisible(input);
  await tester.enterText(input, value);
}

Future<void> choose(WidgetTester tester, String key, String label) async {
  final field = find.byKey(ValueKey('record-course-$key-filter'));
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MenuItemButton, label));
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, '내 기록에 저장');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> open(WidgetTester tester, {double scale = 1}) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const Scaffold(body: CoursePage(showMockData: false)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<PersonalRecordRepository> seed(Map<String, String> periods) async {
  final repo = PersonalRecordRepository(PersonalRecordKind.course);
  await repo.load();
  for (final row in periods.entries) {
    await repo.save(
      PersonalRecord(
        id: PersonalRecord.newId(),
        values: {
          'title': row.key,
          'term': row.value,
          'category': '전공',
          'credits': '3',
        },
      ),
    );
  }
  return repo;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'course period parses only explicit formats and preserves free text',
    () {
      for (final raw in ['2026-1', '2026/1', '2026년 1학기', '2026학년도 1학기']) {
        final period = CourseTerm.parse(raw);
        expect(period.year, '2026');
        expect(period.semester, '1학기');
      }
      expect(CourseTerm.parse('2025년 여름 계절학기').semester, '여름 계절학기');
      for (final raw in ['1학기', '지난 봄', '2026 계획', '0000-1', '  사용자 학기  ']) {
        expect(CourseTerm.parse(raw).year, isEmpty);
        expect(CourseTerm.parse(raw).semester, raw);
      }
      expect(CourseTerm.encode('2024', ' 겨울 계절학기 '), '2024년 겨울 계절학기');
      expect(CourseTerm.validateYear('', required: false), isNull);
      for (final year in ['', '26', '202A', '0000', '10000']) {
        expect(CourseTerm.validateYear(year, required: true), isNotNull);
      }
    },
  );
  testWidgets(
    'course combines year and semester filters without inferring legacy year',
    (tester) async {
      await seed({
        '작년 과목': '2025-1',
        '올해 과목': '2026년 1학기',
        '계절 과목': '2026년 여름 계절학기',
        '기존 과목': '1학기',
      });
      await open(tester, scale: 2);
      expect(find.textContaining('연도 미지정 · 1학기'), findsOneWidget);
      await choose(tester, 'year', '2026년');
      await choose(tester, 'term', '1학기');
      expect(find.text('올해 과목'), findsOneWidget);
      expect(find.text('작년 과목'), findsNothing);
      expect(find.text('기존 과목'), findsNothing);
      expect(find.text('계절 과목'), findsNothing);
      expect(find.textContaining('개인 입력 합계 3.0학점'), findsOneWidget);
      await choose(tester, 'year', '연도 미지정');
      expect(find.text('기존 과목'), findsOneWidget);
      await choose(tester, 'term', '여름 계절학기');
      expect(find.textContaining('선택한 연도·학기에 맞는 개인 기록이 없습니다'), findsOneWidget);
      expect(find.textContaining('개인 입력 합계 0.0학점'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'new course validates split period and saves past seasonal term after reload',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('수강 과목 직접 입력'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('record-field-course-year')),
            )
            .controller!
            .text,
        '${DateTime.now().year}',
      );
      await enter(tester, 'title', '과거 계절 과목');
      await enter(tester, 'course-year', '26');
      await enter(tester, 'term', '여름 계절학기');
      await enter(tester, 'category', '전공');
      await enter(tester, 'credits', '3');
      await save(tester);
      expect(find.text('수강 연도를 네 자리 숫자로 입력하세요.'), findsOneWidget);
      await enter(tester, 'course-year', '2024');
      await enter(tester, 'term', '2024-1');
      await save(tester);
      expect(find.text('연도는 수강 연도 칸에, 학기는 이 칸에 나눠 입력하세요.'), findsOneWidget);
      await enter(tester, 'term', List.filled(124, '가').join());
      await save(tester);
      expect(find.text('연도와 학기를 합쳐 128자 이내로 입력하세요.'), findsOneWidget);
      await enter(tester, 'term', '여름 계절학기');
      await save(tester);
      final repo = PersonalRecordRepository(PersonalRecordKind.course);
      await repo.load();
      expect(repo.records.single.value('term'), '2024년 여름 계절학기');
      expect(repo.records.single.values.containsKey('year'), isFalse);
      await tester.pumpWidget(const SizedBox());
      await open(tester);
      expect(find.textContaining('수강 기간: 2024년 여름 계절학기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'legacy edit preserves exact term until year explicitly supplied',
    (tester) async {
      await seed({'기존 과목': '  1학기  '});
      await open(tester);
      await tester.tap(find.widgetWithText(TextButton, '수정'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('record-field-course-year')),
            )
            .controller!
            .text,
        isEmpty,
      );
      await enter(tester, 'title', '이름만 수정');
      await save(tester);
      final repo = PersonalRecordRepository(PersonalRecordKind.course);
      await repo.load();
      expect(repo.records.single.value('term'), '  1학기  ');
      await tester.tap(find.widgetWithText(TextButton, '수정'));
      await tester.pumpAndSettle();
      await enter(tester, 'course-year', '2023');
      await tester.tap(find.widgetWithText(TextButton, '취소'));
      await tester.pumpAndSettle();
      expect(find.text('작성한 내용을 폐기할까요?'), findsOneWidget);
      await tester.tap(find.text('계속 작성'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('record-field-course-year')),
            )
            .controller!
            .text,
        '2023',
      );
      await save(tester);
      await repo.load();
      expect(repo.records.single.value('term'), '2023년 1학기');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'deleting last filtered course preserves filters with safe empty result',
    (tester) async {
      await seed({'삭제 과목': '2025-1'});
      await open(tester);
      await choose(tester, 'year', '2025년');
      await choose(tester, 'term', '1학기');
      await tester.tap(find.widgetWithText(TextButton, '삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '삭제'));
      await tester.pumpAndSettle();
      expect(find.textContaining('선택한 연도·학기에 맞는 개인 기록이 없습니다'), findsOneWidget);
      await choose(tester, 'year', '전체 연도');
      await choose(tester, 'term', '전체 학기');
      expect(find.text('개인 기록이 없습니다. 직접 입력해 주세요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('new course whitespace period remains empty content', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('수강 과목 직접 입력'));
    await tester.pumpAndSettle();
    await enter(tester, 'course-year', '  ');
    await enter(tester, 'term', '  ');
    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pumpAndSettle();
    expect(find.text('작성한 내용을 폐기할까요?'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
  });
  testWidgets(
    'default new year is empty content but changed year requires discard',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('수강 과목 직접 입력'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '취소'));
      await tester.pumpAndSettle();
      expect(find.text('작성한 내용을 폐기할까요?'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      await tester.tap(find.text('수강 과목 직접 입력'));
      await tester.pumpAndSettle();
      await enter(tester, 'course-year', '2031');
      await tester.tap(find.widgetWithText(TextButton, '취소'));
      await tester.pumpAndSettle();
      expect(find.text('작성한 내용을 폐기할까요?'), findsOneWidget);
      await tester.tap(find.text('내용 폐기'));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
    },
  );
}
