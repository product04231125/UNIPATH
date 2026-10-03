import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/personal_record_fields.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('personal repositories persist CRUD and isolate domains', () async {
    for (final kind in PersonalRecordKind.values) {
      final repo = PersonalRecordRepository(kind);
      await repo.load();
      final id = PersonalRecord.newId();
      await repo.save(PersonalRecord(id: id, values: {'title': kind.name}));
      final loaded = PersonalRecordRepository(kind);
      await loaded.load();
      expect(loaded.records.single.value('title'), kind.name);
      await loaded.save(PersonalRecord(id: id, values: {'title': '수정'}));
      expect(loaded.records.single.id, id);
      await loaded.delete(id);
      final empty = PersonalRecordRepository(kind);
      await empty.load();
      expect(empty.records, isEmpty);
    }
  });

  test('corrupted storage is not overwritten on load failure', () async {
    final repo = PersonalRecordRepository(PersonalRecordKind.course);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(repo.storageKey, 'invalid');
    await expectLater(repo.load(), throwsFormatException);
    await expectLater(
      repo.save(PersonalRecord(id: 'new', values: {'title': '새 기록'})),
      throwsStateError,
    );
    expect(prefs.getString(repo.storageKey), 'invalid');
  });

  test(
    'structured fields reject impossible values and preserve provenance',
    () {
      final fields = personalRecordFields(PersonalRecordKind.course);
      final credit = fields.firstWhere((f) => f.key == 'credits');
      for (final value in ['-1', '0', 'NaN', 'Infinity']) {
        expect(credit.validate(value), isNotNull);
      }
      expect(credit.validate('1.5'), isNull);
      const date = PersonalRecordField(
        'date',
        '날짜',
        type: PersonalFieldType.date,
      );
      expect(date.validate('2026-02-30'), isNotNull);
      expect(date.validate('2026-02-28'), isNull);
      expect(
        personalRecordCrossError({
          'startedOn': '2026-02-28',
          'endedOn': '2026-01-01',
        }),
        isNotNull,
      );
      expect(
        personalRecordCrossError({'approvedHours': '4', 'approval': 'pending'}),
        isNotNull,
      );
      expect(
        personalRecordCrossError({
          'approvedHours': '4',
          'approval': 'approved',
          'observedOn': '2026-02-28',
        }),
        isNull,
      );
    },
  );

  testWidgets(
    'course validation retains input and filters personal semester totals',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = PersonalRecordRepository(PersonalRecordKind.course);
      await repo.load();
      await repo.save(
        PersonalRecord(
          id: PersonalRecord.newId(),
          values: {
            'title': '다른 학기 합성 과목',
            'term': '2025-1',
            'category': '교양',
            'credits': '2',
          },
        ),
      );
      await tester.pumpWidget(
        const UniversityPathApp(startAuthenticated: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('수강 관리').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('수강 과목 직접 입력'));
      await tester.pumpAndSettle();
      for (final field in {
        'title': '수정할 합성 과목',
        'term': '2026-2',
        'category': '전공',
        'credits': '-3',
      }.entries) {
        final input = find.byKey(ValueKey('record-field-${field.key}'));
        await tester.ensureVisible(input);
        await tester.enterText(input, field.value);
      }
      await tester.tap(find.text('내 기록에 저장'));
      await tester.pumpAndSettle();
      expect(find.text('0보다 큰 학점을 입력하세요.'), findsOneWidget);
      final title = tester.widget<TextFormField>(
        find.byKey(const ValueKey('record-field-title')),
      );
      expect(title.controller!.text, '수정할 합성 과목');
      await tester.enterText(
        find.byKey(const ValueKey('record-field-credits')),
        '3',
      );
      await tester.tap(find.text('내 기록에 저장'));
      await tester.pumpAndSettle();
      expect(find.textContaining('개인 입력 합계 5.0학점'), findsOneWidget);
      await tester.tap(find.text('전체 학기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026-2').last);
      await tester.pumpAndSettle();
      expect(find.text('다른 학기 합성 과목'), findsNothing);
      expect(find.textContaining('개인 입력 합계 3.0학점'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'structured activity dialog stays usable in a narrow enlarged window',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 520));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const UniversityPathApp(startAuthenticated: true),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('활동'));
      await tester.tap(find.byTooltip('활동'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('활동 직접 기록'));
      await tester.tap(find.text('활동 직접 기록'));
      await tester.pumpAndSettle();
      final title = find.byKey(const ValueKey('record-field-title'));
      await tester.ensureVisible(title);
      await tester.enterText(title, '합성 봉사');
      final end = find.byKey(const ValueKey('record-field-observedOn'));
      await tester.ensureVisible(end);
      await tester.enterText(end, '2026-10-03');
      expect(find.text('내 기록에 저장').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final item in [
    (
      '수강 관리',
      '수강 과목 직접 입력',
      {'title': '합성 과목', 'term': '2026-2', 'category': '개인 전공', 'credits': '3'},
    ),
    ('활동', '활동 직접 기록', {'title': '합성 활동'}),
    ('경험', '경험 직접 기록', {'title': '합성 경험', 'type': '프로젝트'}),
    ('자격', '자격 직접 등록', {'title': '합성 자격'}),
    (
      '포트폴리오·성과',
      '성과 직접 기록',
      {'title': '합성 성과', 'type': '프로젝트', 'role': '설계', 'result': '시연 완료'},
    ),
  ]) {
    testWidgets(
      '${item.$1} supports structured input, remount and confirmed delete',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          const UniversityPathApp(startAuthenticated: true),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(item.$1).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(item.$2));
        await tester.pumpAndSettle();
        for (final field in item.$3.entries) {
          final input = find.byKey(ValueKey('record-field-${field.key}'));
          await tester.ensureVisible(input);
          await tester.enterText(input, field.value);
        }
        await tester.tap(find.text('내 기록에 저장'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('홈').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(item.$1).first);
        await tester.pumpAndSettle();
        expect(find.text(item.$3['title']!), findsOneWidget);
        await tester.ensureVisible(find.text('수정').first);
        await tester.tap(find.text('수정').first);
        await tester.pumpAndSettle();
        final name = find.byKey(const ValueKey('record-field-title'));
        await tester.ensureVisible(name);
        await tester.enterText(name, '수정된 합성 기록');
        await tester.tap(find.text('내 기록에 저장'));
        await tester.pumpAndSettle();
        expect(find.text('수정된 합성 기록'), findsOneWidget);
        await tester.ensureVisible(find.text('삭제').first);
        await tester.tap(find.text('삭제').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('삭제').last);
        await tester.pumpAndSettle();
        expect(find.text(item.$3['title']!), findsNothing);
        expect(find.text('수정된 합성 기록'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
