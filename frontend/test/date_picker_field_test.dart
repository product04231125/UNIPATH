import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/records/personal_record_form.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/shared/widgets/date_picker_field.dart';

import 'support/date_picker.dart';

void main() {
  test('days are read only when real and written as YYYY-MM-DD', () {
    expect(parseDay('2026-02-28'), DateTime(2026, 2, 28));
    expect(parseDay('2026-02-30'), isNull);
    expect(parseDay('2026.2.28'), isNull);
    expect(formatDay(DateTime(2026, 3, 2)), '2026-03-02');
    expect(displayDay(DateTime(2026, 3, 2)), '2026.3.2 (월)');
  });

  testWidgets(
    'a date is picked, shown like the schedule, cleared and checked',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final form = GlobalKey<FormState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              key: form,
              child: DatePickerFormField(
                key: const ValueKey('day'),
                controller: controller,
                label: '시작일',
                validator: (v) => v.isEmpty ? '시작일을 고르세요.' : null,
              ),
            ),
          ),
        ),
      );
      expect(form.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('시작일을 고르세요.'), findsOneWidget);
      await pickDate(
        tester,
        find.byKey(const ValueKey('day')),
        DateTime(2026, 3, 2),
      );
      expect(controller.text, '2026-03-02');
      expect(find.text('2026.3.2 (월)'), findsOneWidget);
      expect(form.currentState!.validate(), isTrue);
      await tester.tap(find.byTooltip('시작일 지우기'));
      await tester.pump();
      expect(controller.text, isEmpty);
      // Typed or older values that are not a real day stay visible to be replaced.
      controller.text = '2024년 봄';
      await tester.pump();
      expect(find.text('2024년 봄'), findsOneWidget);
    },
  );

  for (final (width, sideBySide) in [(1200.0, true), (420.0, false)]) {
    testWidgets('an experience period sits on one line at $width', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = PersonalRecordRepository(PersonalRecordKind.experience);
      await repo.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPersonalRecordForm(
                  context: context,
                  kind: PersonalRecordKind.experience,
                  repository: repo,
                  addLabel: '경험 추가',
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      final start = find.byKey(const ValueKey('record-field-startedOn'));
      final end = find.byKey(const ValueKey('record-field-endedOn'));
      expect(
        tester.getTopLeft(start).dy == tester.getTopLeft(end).dy,
        sideBySide,
      );
      if (!sideBySide) return;
      await tester.enterText(
        find.byKey(const ValueKey('record-field-title')),
        '합성 프로젝트',
      );
      await tester.enterText(
        find.byKey(const ValueKey('record-field-type')),
        '프로젝트',
      );
      await pickDate(tester, start, DateTime(2026, 3, 2));
      await pickDate(tester, end, DateTime(2026, 2, 1));
      await tester.tap(find.text('내 기록에 저장'));
      await tester.pumpAndSettle();
      expect(find.textContaining('시작·취득일보다 빠를 수 없습니다'), findsOneWidget);
      await pickDate(tester, end, DateTime(2026, 6, 30));
      await tester.tap(find.text('내 기록에 저장'));
      await tester.pumpAndSettle();
      expect(repo.records.single.value('startedOn'), '2026-03-02');
      expect(repo.records.single.value('endedOn'), '2026-06-30');
    });
  }
}
