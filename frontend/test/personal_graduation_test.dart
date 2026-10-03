import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/graduation/personal_graduation_workspace.dart';
import 'package:university_path_frontend/features/graduation/personal_graduation_fields.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/personal_record_fields.dart';

Future<void> seed(
  PersonalRecordKind kind,
  String id,
  Map<String, String> values,
) async {
  final repo = PersonalRecordRepository(kind);
  await repo.load();
  await repo.save(PersonalRecord(id: id, values: values));
}

Future<void> fill(WidgetTester tester, Map<String, String> values) async {
  for (final e in values.entries) {
    final field = find.byKey(ValueKey('record-field-${e.key}'));
    await tester.ensureVisible(field);
    await tester.enterText(field, e.value);
  }
}

Future<void> select(WidgetTester tester, String key, String label) async {
  final field = find.byKey(ValueKey('record-select-$key'));
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('personal graduation references validate ownership and preserve records on deletion', () async {
    await seed(PersonalRecordKind.personalCurriculum, 'a', {
      'title': 'A',
      'curriculumYear': '2024',
    });
    await seed(PersonalRecordKind.personalCurriculum, 'b', {
      'title': 'B',
      'curriculumYear': '2025',
    });
    await seed(PersonalRecordKind.personalCurriculumCourse, 'c', {
      'title': '과목',
      'curriculumId': 'a',
    });
    await seed(PersonalRecordKind.course, 'record', {'title': '수강 기록'});
    final values = {
      'title': '규칙',
      'curriculumId': 'a',
      'curriculumCourseId': 'c',
      'relatedRecord': 'course/record',
      'scope': '교육과정',
    };
    expect(
      await validatePersonalGraduationLinks(
        PersonalRecordKind.personalGraduationRule,
        values,
      ),
      isNull,
    );
    expect(
      await validatePersonalGraduationLinks(
        PersonalRecordKind.personalGraduationRule,
        {...values, 'curriculumId': 'b'},
      ),
      isNotNull,
    );
    await seed(PersonalRecordKind.personalGraduationRule, 'rule', values);
    final curricula = PersonalRecordRepository(
      PersonalRecordKind.personalCurriculum,
    );
    await curricula.load();
    await curricula.delete('a');
    expect(
      await validatePersonalGraduationLinks(
        PersonalRecordKind.personalGraduationRule,
        values,
      ),
      isNotNull,
    );
    final rules = PersonalRecordRepository(
      PersonalRecordKind.personalGraduationRule,
    );
    await rules.load();
    expect(rules.records.single.value('curriculumId'), 'a');
    final courses = PersonalRecordRepository(
      PersonalRecordKind.personalCurriculumCourse,
    );
    await courses.load();
    expect(courses.records.single.id, 'c');
  });

  test(
    'personal rules validate numeric values, years and effective period',
    () {
      final fields = personalRecordFields(
        PersonalRecordKind.personalGraduationRule,
      );
      final value = fields.firstWhere((f) => f.key == 'requiredValue');
      for (final raw in ['-1', 'NaN', 'Infinity']) {
        expect(value.validate(raw), isNotNull);
      }
      expect(value.validate('1.5'), isNull);
      final year = personalRecordFields(PersonalRecordKind.personalCurriculum)
          .firstWhere((f) => f.key == 'curriculumYear');
      expect(year.validate('2024.5'), isNotNull);
      expect(year.validate('2024'), isNull);
      expect(
        personalRecordCrossError({
          'effectiveFrom': '2026-10-03',
          'effectiveTo': '2026-10-02',
        }),
        isNotNull,
      );
    },
  );

  testWidgets(
    'curriculum, course and rule CRUD persist independently with explicit links',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await seed(PersonalRecordKind.course, 'record', {'title': '연결할 합성 수강'});
      Widget page() => MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: PersonalGraduationWorkspace(onBack: () {}),
          ),
        ),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.tap(find.text('교육과정 추가'));
      await tester.pumpAndSettle();
      await fill(tester, {
        'title': '합성 교육과정',
        'school': '합성 학교',
        'department': '합성 학과',
        'admissionYear': '2024',
        'curriculumYear': '2024',
      });
      await tester.tap(find.text('내 기록에 저장'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('교육과정 과목').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('교육과정 과목 추가'));
      await tester.pumpAndSettle();
      await fill(tester, {'title': '합성 과목', 'category': '전공', 'credits': '3'});
      await select(tester, 'requiredCourse', '필수');
      await select(tester, 'curriculumId', '합성 교육과정 · 2024');
      await tester.tap(find.text('내 기록에 저장'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('개인 규칙'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('개인 규칙 추가'));
      await tester.pumpAndSettle();
      await fill(tester, {
        'title': '합성 규칙',
        'ruleType': '필수 과목',
        'condition': '해당 과목을 기록으로 연결하여 확인',
        'requiredValue': '-1',
        'currentValue': '3',
        'unit': '학점',
      });
      await select(tester, 'scope', '교육과정');
      await select(tester, 'curriculumId', '합성 교육과정 · 2024');
      await select(tester, 'curriculumCourseId', '합성 과목 · 전공');
      await select(tester, 'relatedRecord', '수강 · 연결할 합성 수강');
      await tester.tap(find.text('내 기록에 저장'));
      await tester.pumpAndSettle();
      expect(find.text('0 이상의 숫자를 입력하세요.'), findsOneWidget);
      await fill(tester, {'requiredValue': '3'});
      await tester.tap(find.text('내 기록에 저장'));
      await tester.pumpAndSettle();
      expect(find.text('충족'), findsNothing);
      expect(find.text('미충족'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.tap(find.text('교육과정 과목').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('수정'));
      await tester.pumpAndSettle();
      await fill(tester, {'credits': '4'});
      await tester.tap(find.text('내 기록에 저장'));
      await tester.pumpAndSettle();
      expect(find.textContaining('과목 학점: 4'), findsOneWidget);
      await tester.tap(find.text('교육과정'));
      await tester.pumpAndSettle();
      // Editing the curriculum must not reset its rules or courses.
      await tester.tap(find.text('수정'));
      await tester.pumpAndSettle();
      await fill(tester, {'title': '수정된 교육과정'});
      await tester.tap(find.text('내 기록에 저장'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('개인 규칙'));
      await tester.pumpAndSettle();
      expect(find.text('합성 규칙'), findsOneWidget);
      expect(find.textContaining('수정된 교육과정'), findsOneWidget);
      expect(find.textContaining('수강 · 연결할 합성 수강'), findsOneWidget);
      await tester.tap(find.text('수정'));
      await tester.pumpAndSettle();
      await fill(tester, {'title': '수정된 규칙'});
      await tester.tap(find.text('내 기록에 저장'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('교육과정'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('개인 규칙'));
      await tester.pumpAndSettle();
      expect(find.text('수정된 규칙'), findsOneWidget);
      expect(find.textContaining('연결할 개인 교육과정: 연결 대상 없음'), findsOneWidget);
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제').last);
      await tester.pumpAndSettle();
      expect(find.text('수정된 규칙'), findsNothing);
      await tester.tap(find.text('교육과정 과목').first);
      await tester.pumpAndSettle();
      expect(find.text('합성 과목'), findsOneWidget);
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제').last);
      await tester.pumpAndSettle();
      expect(find.text('합성 과목'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'personal graduation form remains accessible at 480x520 with enlarged text',
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
          home: Scaffold(body: PersonalGraduationWorkspace(onBack: () {})),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('교육과정 추가'));
      await tester.tap(find.text('교육과정 추가'));
      await tester.pumpAndSettle();
      await fill(tester, {'curriculumYear': '2024'});
      expect(find.text('내 기록에 저장').hitTestable(), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
