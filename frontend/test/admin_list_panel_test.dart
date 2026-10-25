import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/admin/admin_editor.dart';
import 'package:university_path_frontend/features/admin/admin_models.dart';
import 'package:university_path_frontend/features/admin/admin_repository.dart';
import 'package:university_path_frontend/features/admin/admin_workspace.dart';
import 'package:university_path_frontend/features/auth/app_role.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';

Future<void> showWorkspace(
  WidgetTester tester,
  FakeAdminRepository repo,
  AppRole role,
  String path,
) async {
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(repo.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AdminWorkspace(
          repository: repo,
          role: role,
          path: path,
          onNavigate: (_) {},
          onSignedOut: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final role in [AppRole.superAdmin, AppRole.schoolAdmin]) {
    testWidgets(
      '${role.name} empty list becomes populated beside permanent form',
      (tester) async {
        var fail = true;
        final repo = FakeAdminRepository(
          beforeOperation: (operation) async {
            if (operation == 'save' && fail) throw StateError('저장 실패 · 입력 유지');
          },
        );
        await showWorkspace(tester, repo, role, '/admin/rules');
        final list = find.byKey(const ValueKey('admin-section-ruleSet'));
        final empty = find.byKey(const ValueKey('admin-empty-ruleSet'));
        final form = find.descendant(
          of: find.byKey(const ValueKey('admin-registration-ruleSet-school-a')),
          matching: find.byType(AdminEditor),
        );
        expect(
          find.descendant(of: list, matching: find.text('규칙 묶음 목록')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: list, matching: find.text('0개')),
          findsOneWidget,
        );
        expect(empty, findsOneWidget);
        expect(tester.getSize(list).height, inInclusiveRange(240, 360));
        expect(
          tester.getTopLeft(list).dy,
          tester
              .getTopLeft(find.byKey(const ValueKey('admin-basic-ruleSet')))
              .dy,
        );
        expect(
          tester.getTopLeft(list).dx,
          lessThan(
            tester
                .getTopLeft(find.byKey(const ValueKey('admin-basic-ruleSet')))
                .dx,
          ),
        );
        expect(find.widgetWithText(FilledButton, '규칙 묶음 등록'), findsNothing);
        expect(
          find.byKey(const ValueKey('admin-search-school-a-ruleSet')),
          findsNothing,
        );
        final name = find.descendant(
          of: form,
          matching: find.byKey(const ValueKey('admin-field-name')),
        );
        await tester.enterText(name, '내 규칙 묶음');
        final save = find.descendant(
          of: form,
          matching: find.widgetWithText(FilledButton, '등록'),
        );
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(find.text('저장 실패 · 입력 유지'), findsOneWidget);
        expect(tester.widget<TextFormField>(name).controller!.text, '내 규칙 묶음');
        expect(empty, findsOneWidget);
        fail = false;
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(empty, findsNothing);
        expect(
          find.descendant(of: list, matching: find.text('내 규칙 묶음')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: list, matching: find.text('1개')),
          findsOneWidget,
        );
        expect(form, findsOneWidget);
        expect(tester.widget<TextFormField>(name).controller!.text, isEmpty);
        final search = find.byKey(
          const ValueKey('admin-search-school-a-ruleSet'),
        );
        await tester.ensureVisible(search);
        await tester.enterText(search, '일치하지 않는 검색');
        await tester.pumpAndSettle();
        expect(empty, findsNothing);
        expect(find.textContaining('검색·필터에 맞는 항목'), findsOneWidget);
        expect(
          find.descendant(of: list, matching: find.text('1개')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'curriculum department and year share one row across field groups',
    (tester) async {
      final repo = FakeAdminRepository();
      await showWorkspace(tester, repo, AppRole.superAdmin, '/admin/curricula');
      final form = find.descendant(
        of: find.byKey(
          const ValueKey('admin-registration-curriculum-school-a'),
        ),
        matching: find.byType(AdminEditor),
      );
      Finder field(String key) => find.descendant(
        of: form,
        matching: find.byKey(ValueKey('admin-field-$key')),
      );
      final department = field('departmentId');
      final year = field('year');
      expect(
        tester.getBottomLeft(department).dy,
        tester.getBottomLeft(year).dy,
      );
      expect(
        tester.getTopLeft(department).dx,
        lessThan(tester.getTopLeft(year).dx),
      );
      expect(tester.getSize(department).width, tester.getSize(year).width);
      await tester.enterText(field('name'), '2026 교육과정');
      await tester.enterText(year, '2026');
      final save = find.descendant(
        of: form,
        matching: find.widgetWithText(FilledButton, '등록'),
      );
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('학과을 선택하세요.'), findsOneWidget);
      expect(tester.widget<TextFormField>(year).controller!.text, '2026');
      tester
          .widget<AnchoredSelectField<String>>(department)
          .onChanged('school-a-dept');
      await tester.pumpAndSettle();
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final created = repo.records.singleWhere((r) => r.name == '2026 교육과정');
      expect(created.value('departmentId'), 'school-a-dept');
      expect(created.value('year'), '2026');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'long descriptions keep full detail width and dates share a row',
    (tester) async {
      await showWorkspace(
        tester,
        FakeAdminRepository(),
        AppRole.superAdmin,
        '/admin/rules',
      );
      final form = find.descendant(
        of: find.byKey(const ValueKey('admin-registration-rule-school-a')),
        matching: find.byType(AdminEditor),
      );
      Finder field(String key) => find.descendant(
        of: form,
        matching: find.byKey(ValueKey('admin-field-$key')),
      );
      final details = find.byKey(const ValueKey('admin-details-rule'));
      expect(
        tester.getSize(field('definition')).width,
        greaterThan(tester.getSize(details).width * .9),
      );
      expect(
        tester.getTopLeft(field('effectiveFrom')).dy,
        tester.getTopLeft(field('effectiveTo')).dy,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('mixed layout keeps all fields and validates both panels', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    await showWorkspace(tester, repo, AppRole.superAdmin, '/admin/schools');
    final form = find.descendant(
      of: find.byKey(const ValueKey('admin-registration-department-school-a')),
      matching: find.byType(AdminEditor),
    );
    final list = find.byKey(const ValueKey('admin-section-department'));
    final basic = find.byKey(const ValueKey('admin-basic-department'));
    final details = find.byKey(const ValueKey('admin-details-department'));
    expect(tester.getTopLeft(list).dy, tester.getTopLeft(basic).dy);
    expect(
      tester.getTopLeft(details).dy,
      greaterThan(tester.getBottomLeft(list).dy),
    );
    expect(tester.getTopLeft(details).dx, tester.getTopLeft(list).dx);
    expect(
      tester.getSize(details).width,
      greaterThan(tester.getSize(list).width * 1.9),
    );
    for (final field in repo.fields(AdminKind.department)) {
      expect(
        find.descendant(
          of: form,
          matching: find.byKey(ValueKey('admin-field-${field.key}')),
        ),
        findsOneWidget,
      );
    }
    final name = find.descendant(
      of: basic,
      matching: find.byKey(const ValueKey('admin-field-name')),
    );
    final code = find.descendant(
      of: details,
      matching: find.byKey(const ValueKey('admin-field-code')),
    );
    await tester.ensureVisible(name);
    await tester.enterText(name, '새 학과');
    final save = find.descendant(
      of: form,
      matching: find.widgetWithText(FilledButton, '등록'),
    );
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('코드을 입력하세요.'), findsOneWidget);
    expect(repo.records.any((r) => r.name == '새 학과'), isFalse);
    await tester.ensureVisible(code);
    await tester.enterText(code, 'NEW');
    final cancel = find.descendant(
      of: form,
      matching: find.widgetWithText(TextButton, '취소'),
    );
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.text('작성한 내용을 폐기할까요?'), findsOneWidget);
    await tester.tap(find.text('계속 작성'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(name).controller!.text, '새 학과');
    expect(tester.widget<TextFormField>(code).controller!.text, 'NEW');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repo.records.any((r) => r.name == '새 학과'), isTrue);
    expect(tester.widget<TextFormField>(code).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'read only school list uses full width without registration placeholder',
    (tester) async {
      await showWorkspace(
        tester,
        FakeAdminRepository(),
        AppRole.schoolAdmin,
        '/admin/schools',
      );
      final list = find.byKey(const ValueKey('admin-section-institution'));
      expect(tester.getSize(list).width, greaterThan(1000));
      expect(
        find.byKey(const ValueKey('admin-registration-institution-school-a')),
        findsNothing,
      );
      expect(
        find.descendant(of: list, matching: find.text('학교 목록')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('full width account list keeps scope form available below', (
    tester,
  ) async {
    await showWorkspace(
      tester,
      FakeAdminRepository(),
      AppRole.superAdmin,
      '/admin/accounts',
    );
    final list = find.byKey(const ValueKey('admin-section-account'));
    expect(tester.getSize(list).width, greaterThan(1000));
    expect(
      find.descendant(of: list, matching: find.text('3개')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('admin-registration-scope-school-a')),
        matching: find.byType(AdminEditor),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
