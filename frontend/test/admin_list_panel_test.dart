import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/admin/admin_editor.dart';
import 'package:university_path_frontend/features/admin/admin_repository.dart';
import 'package:university_path_frontend/features/admin/admin_workspace.dart';
import 'package:university_path_frontend/features/auth/app_role.dart';

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
        expect(tester.getTopLeft(list).dy, tester.getTopLeft(form).dy);
        expect(
          tester.getTopLeft(list).dx,
          lessThan(tester.getTopLeft(form).dx),
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
