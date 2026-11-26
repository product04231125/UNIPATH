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

Future<AdminRecord> seedCurriculumMenu(
  FakeAdminRepository repo,
  AdminKind kind,
) async {
  final curriculum = AdminRecord(
    id: 'review-curriculum',
    kind: AdminKind.curriculum,
    values: const {
      'name': '기존 교육과정',
      'departmentId': 'school-a-dept',
      'year': '2026',
    },
  );
  final course = AdminRecord(
    id: 'review-course',
    kind: AdminKind.course,
    values: const {
      'name': '기존 과목',
      'institutionId': 'school-a',
      'code': 'REVIEW',
      'credits': '3',
    },
  );
  final link = AdminRecord(
    id: 'review-link',
    kind: AdminKind.curriculumCourse,
    values: const {
      'name': '기존 과목 연결',
      'curriculumId': 'review-curriculum',
      'courseId': 'review-course',
      'category': 'major',
      'required': 'true',
    },
  );
  final secondCurriculum = AdminRecord(
    id: 'review-curriculum-second',
    kind: AdminKind.curriculum,
    values: {...curriculum.values, 'name': '다른 교육과정'},
  );
  for (final record in [curriculum, course, link, secondCurriculum]) {
    await repo.save('super-admin', record);
  }
  return repo.records.singleWhere(
    (record) =>
        record.id ==
        switch (kind) {
          AdminKind.curriculum => curriculum.id,
          AdminKind.course => course.id,
          _ => link.id,
        },
  );
}

void main() {
  for (final kind in [
    AdminKind.curriculum,
    AdminKind.course,
    AdminKind.curriculumCourse,
  ]) {
    testWidgets('${kind.name} clears the editing target before creating', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeAdminRepository();
      addTearDown(repo.dispose);
      final original = await seedCurriculumMenu(repo, kind);
      final key = GlobalKey<AdminEditorState>();
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: AdminEditor(
              key: key,
              repository: repo,
              actorId: 'super-admin',
              kind: kind,
              schoolId: 'school-a',
              record: original,
              inline: true,
            ),
          ),
        ),
      );
      expect(key.currentState!.activeRecord?.id, original.id);
      await key.currentState!.clearToCreate();
      await tester.pumpAndSettle();
      expect(key.currentState!.activeRecord, isNull);
      expect(key.currentState!.dirty, isFalse);
      expect(find.text('${kind.label} 등록'), findsOneWidget);

      for (final field in repo.fields(kind)) {
        final finder = find.byKey(ValueKey('admin-field-${field.key}'));
        final value = switch (field.key) {
          'name' => '새 ${kind.label}',
          'code' => 'REVIEW-NEW',
          // Use another relation pair so the mock duplicate check stays active.
          'curriculumId' => 'review-curriculum-second',
          _ => original.value(field.key),
        };
        if (tester.widget(finder) is TextFormField) {
          await tester.enterText(finder, value);
        } else {
          tester.widget<AnchoredSelectField<String>>(finder).onChanged(value);
        }
        await tester.pump();
      }
      if (kind == AdminKind.course) {
        for (final entry in {'curriculumId': 'review-curriculum-second', 'category': 'major', 'required': 'true'}.entries) {
          tester.widget<AnchoredSelectField<String>>(find.byKey(ValueKey('admin-field-${entry.key}'))).onChanged(entry.value);
          await tester.pump();
        }
      }
      await tester.ensureVisible(find.widgetWithText(FilledButton, '등록'));
      await tester.tap(find.widgetWithText(FilledButton, '등록'));
      await tester.pumpAndSettle();
      expect(
        repo.records.singleWhere((r) => r.id == original.id).values,
        original.values,
      );
      final created = repo.records.singleWhere(
        (r) => r.name == '새 ${kind.label}',
      );
      expect(created.id, isNot(original.id));
      expect(key.currentState!.activeRecord, isNull);
      expect(key.currentState!.dirty, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${kind.name} resets validation when switching records', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeAdminRepository();
      addTearDown(repo.dispose);
      final record = await seedCurriculumMenu(repo, kind);
      final key = GlobalKey<AdminEditorState>();
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: AdminEditor(
              key: key,
              repository: repo,
              actorId: 'super-admin',
              kind: kind,
              schoolId: 'school-a',
              inline: true,
            ),
          ),
        ),
      );
      final form = tester.state<FormState>(find.byType(Form));
      expect(form.validate(), isFalse);
      await tester.pump();
      expect(find.text('이름을 입력하세요.'), findsOneWidget);
      await key.currentState!.loadRecord(record);
      await tester.pumpAndSettle();
      expect(find.text('이름을 입력하세요.'), findsNothing);
      expect(find.textContaining('을 선택하세요.'), findsNothing);
      expect(key.currentState!.dirty, isFalse);
      await key.currentState!.clearToCreate();
      await tester.pumpAndSettle();
      expect(form.validate(), isFalse);
      await tester.pump();
      await key.currentState!.clearToCreate();
      await tester.pumpAndSettle();
      expect(find.text('이름을 입력하세요.'), findsNothing);
      expect(find.textContaining('을 선택하세요.'), findsNothing);
      expect(key.currentState!.dirty, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

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
