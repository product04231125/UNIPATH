import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/admin/admin_editor.dart';
import 'package:university_path_frontend/features/admin/admin_fields.dart';
import 'package:university_path_frontend/features/admin/admin_models.dart';
import 'package:university_path_frontend/features/admin/admin_repository.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';
import 'package:university_path_frontend/shared/widgets/input_dialog.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

Future<void> openCurriculumEditor(
  WidgetTester tester,
  FakeAdminRepository repo,
) async {
  await tester.pumpWidget(
    host(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showInputDialog<String>(
            context: context,
            builder: (_) => AdminEditor(
              repository: repo,
              actorId: 'super-admin',
              kind: AdminKind.curriculum,
              schoolId: 'school-a',
            ),
          ),
          child: const Text('열기'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

Finder yearField() => find.byKey(const ValueKey('admin-field-year'));

void main() {
  test('adminYearChoices keeps nearby years, loaded curricula, and the current value', () {
    expect(
      adminYearChoices(
        records: [
          AdminRecord(
            id: 'old',
            kind: AdminKind.curriculum,
            values: const {'year': '2010'},
          ),
          AdminRecord(
            id: 'dept',
            kind: AdminKind.department,
            values: const {'year': '1999'},
          ),
        ],
        selected: '2035',
        now: DateTime(2026, 11, 2),
      ),
      [
        2010,
        2016,
        2017,
        2018,
        2019,
        2020,
        2021,
        2022,
        2023,
        2024,
        2025,
        2026,
        2027,
        2028,
        2035,
      ],
    );
  });

  testWidgets('curriculum year is a searchable select, not a text box', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    addTearDown(repo.dispose);
    await openCurriculumEditor(tester, repo);
    final year = tester.widget<AnchoredSelectField<String>>(yearField());
    expect(year.searchable, isTrue);
    expect(year.searchLabel, '연도 검색');
    expect(
      find.descendant(of: yearField(), matching: find.byType(TextFormField)),
      findsNothing,
    );
    expect(
      year.options.map((option) => option.value),
      containsAll(['', '2026']),
    );
    expect(find.byKey(const ValueKey('admin-field-name')), findsOneWidget);
    expect(
      tester.widget(find.byKey(const ValueKey('admin-field-name'))),
      isA<TextFormField>(),
    );
  });

  testWidgets('year search keeps 2026 and saving still stores year 2026', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    addTearDown(repo.dispose);
    await openCurriculumEditor(tester, repo);
    await tester.tap(yearField());
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('select-search-input'));
    expect(search, findsOneWidget);
    await tester.enterText(search, '2026');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(MenuItemButton, '2026년'), findsOneWidget);
    expect(find.widgetWithText(MenuItemButton, '2016년'), findsNothing);
    expect(find.widgetWithText(MenuItemButton, '2027년'), findsNothing);
    await tester.tap(find.widgetWithText(MenuItemButton, '2026년'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnchoredSelectField<String>>(yearField()).value,
      '2026',
    );
    await tester.enterText(
      find.byKey(const ValueKey('admin-field-name')),
      '검색 선택 2026 과정',
    );
    tester
        .widget<AnchoredSelectField<String>>(
          find.byKey(const ValueKey('admin-field-departmentId')),
        )
        .onChanged('school-a-dept');
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.byType(InputDialog), findsNothing);
    final created = repo.records.singleWhere((r) => r.name == '검색 선택 2026 과정');
    expect(created.value('year'), '2026');
    expect(int.parse(created.value('year')), 2026);
  });

  testWidgets('empty year asks the user to select and keeps the name', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    addTearDown(repo.dispose);
    await openCurriculumEditor(tester, repo);
    await tester.enterText(
      find.byKey(const ValueKey('admin-field-name')),
      '연도 없는 과정',
    );
    tester
        .widget<AnchoredSelectField<String>>(
          find.byKey(const ValueKey('admin-field-departmentId')),
        )
        .onChanged('school-a-dept');
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('적용 연도을 선택하세요.'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('admin-field-name')))
          .controller!
          .text,
      '연도 없는 과정',
    );
  });

  testWidgets('course link category and course are searchable selects', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    addTearDown(repo.dispose);
    await repo.save(
      'super-admin',
      AdminRecord(
        id: 'course-search',
        kind: AdminKind.course,
        values: const {
          'name': '검색할 과목',
          'institutionId': 'school-a',
          'code': 'SRCH',
          'credits': '3',
        },
      ),
    );
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showInputDialog<String>(
              context: context,
              builder: (_) => AdminEditor(
                repository: repo,
                actorId: 'super-admin',
                kind: AdminKind.curriculumCourse,
                schoolId: 'school-a',
              ),
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    final course = tester.widget<AnchoredSelectField<String>>(
      find.byKey(const ValueKey('admin-field-courseId')),
    );
    final category = tester.widget<AnchoredSelectField<String>>(
      find.byKey(const ValueKey('admin-field-category')),
    );
    expect(course.searchable, isTrue);
    expect(category.searchable, isTrue);
    expect(course.searchLabel, '검색');
    await tester.tap(find.byKey(const ValueKey('admin-field-courseId')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('select-search-input')),
      '검색할',
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(MenuItemButton, '검색할 과목'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
