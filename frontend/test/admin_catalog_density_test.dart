import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/admin/admin_models.dart';
import 'package:university_path_frontend/features/admin/admin_repository.dart';
import 'package:university_path_frontend/features/admin/admin_workspace.dart';
import 'package:university_path_frontend/features/auth/app_role.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('catalog rows use compact actions, separators, and 64 extent', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    final repo = FakeAdminRepository();
    addTearDown(repo.dispose);
    await tester.pumpWidget(
      host(
        AdminWorkspace(
          repository: repo,
          role: AppRole.superAdmin,
          path: '/admin/schools',
          onNavigate: (_) {},
          onSignedOut: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('admin-row-school-a'));
    expect(row, findsOneWidget);
    expect(tester.getSize(row).height, closeTo(64, 1));

    final edit = find.descendant(
      of: row,
      matching: find.widgetWithText(OutlinedButton, '수정'),
    );
    final delete = find.descendant(
      of: row,
      matching: find.widgetWithText(FilledButton, '삭제'),
    );
    expect(edit, findsOneWidget);
    expect(delete, findsOneWidget);
    expect(
      tester.getTopLeft(delete).dx - tester.getBottomRight(edit).dx,
      closeTo(8, 1),
    );
    final editButton = tester.widget<OutlinedButton>(edit);
    expect(editButton.style?.minimumSize?.resolve({}), const Size(0, 36));
    expect(tester.takeException(), isNull);
  });

  testWidgets('overview keeps tonal create separate from outlined navigate', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    final repo = FakeAdminRepository();
    addTearDown(repo.dispose);
    await tester.pumpWidget(
      host(
        AdminWorkspace(
          repository: repo,
          role: AppRole.superAdmin,
          path: '/admin/overview',
          onNavigate: (_) {},
          onSignedOut: () {},
          onEnterStudentPreview: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('학과 등록'), findsOneWidget);
    expect(find.text('졸업요건 확인'), findsOneWidget);
    expect(find.text('관리자 범위 관리'), findsOneWidget);
    expect(find.text('학생 화면 미리보기'), findsOneWidget);

    final create = find.widgetWithText(FilledButton, '학과 등록');
    expect(create, findsOneWidget);
    expect(
      find.descendant(of: create, matching: find.byIcon(Icons.add)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(OutlinedButton, '졸업요건 확인'),
        matching: find.byIcon(Icons.arrow_forward),
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, '관리자 범위 관리'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history supports local search and kind/action filters', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    final repo = FakeAdminRepository();
    addTearDown(repo.dispose);
    await repo.save(
      'super-admin',
      AdminRecord(
        id: 'dept-history-filter',
        kind: AdminKind.department,
        values: {
          'name': '이력필터학과',
          'institutionId': 'school-a',
          'code': 'HIST',
        },
      ),
    );
    expect(repo.history, isNotEmpty);

    await tester.pumpWidget(
      host(
        AdminWorkspace(
          repository: repo,
          role: AppRole.superAdmin,
          path: '/admin/history',
          onNavigate: (_) {},
          onSignedOut: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('admin-history-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-history-kind')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-history-action')), findsOneWidget);
    expect(find.text('관리 이력이 없습니다. 등록·수정 후 확인하세요.'), findsNothing);

    final search = find.byKey(const ValueKey('admin-history-search'));
    await tester.ensureVisible(search);
    await tester.enterText(search, '없는검색어zzzz');
    await tester.pumpAndSettle();
    expect(find.text('검색·필터에 맞는 이력이 없습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
