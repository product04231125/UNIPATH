import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/admin/admin_models.dart';
import 'package:university_path_frontend/features/admin/admin_repository.dart';
import 'package:university_path_frontend/features/admin/admin_workspace.dart';
import 'package:university_path_frontend/features/auth/app_role.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('all schools keeps student preview visible and asks for a school', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = FakeAdminRepository();
    addTearDown(repo.dispose);
    var entered = 0;
    await tester.pumpWidget(host(AdminWorkspace(
      repository: repo, role: AppRole.superAdmin, path: '/admin/overview',
      onNavigate: (_) {}, onSignedOut: () {}, onEnterStudentPreview: () => entered++,
    )));
    await tester.pumpAndSettle();
    final preview = find.byKey(const ValueKey('admin-student-preview'));
    await tester.ensureVisible(preview);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.text('미리 볼 학교 선택'), findsOneWidget);
    expect(entered, 0);
    Navigator.of(tester.element(find.byType(SimpleDialog))).pop();
    await tester.pumpAndSettle();
    expect(entered, 0);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(SimpleDialog), matching: find.text('합성 대학 A')));
    await tester.pumpAndSettle();
    expect(entered, 1);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsNothing);
    expect(entered, 2);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('overview uses filled create with shared min size', (
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

    expect(find.text('확인할 초안'), findsNothing);
    expect(find.textContaining('확인할 초안'), findsNothing);
    expect(find.text('바로가기'), findsOneWidget);
    expect(find.text('자료 등록'), findsOneWidget);
    expect(find.text('학과 등록'), findsOneWidget);
    expect(find.text('졸업요건 확인'), findsOneWidget);
    expect(find.text('관리자 범위 관리'), findsOneWidget);
    expect(find.text('학생 화면 미리보기'), findsOneWidget);

    final create = find.widgetWithText(FilledButton, '학과 등록');
    expect(create, findsOneWidget);
    expect(find.byType(FilledButton), findsWidgets);
    expect(
      find.descendant(of: create, matching: find.byIcon(Icons.add)),
      findsOneWidget,
    );
    final createStyle = tester.widget<FilledButton>(create).style;
    expect(createStyle?.minimumSize?.resolve({}), const Size(148, 40));
    final navigate = find.widgetWithText(OutlinedButton, '졸업요건 확인');
    expect(
      find.descendant(of: navigate, matching: find.byIcon(Icons.arrow_forward)),
      findsOneWidget,
    );
    expect(
      tester.widget<OutlinedButton>(navigate).style?.minimumSize?.resolve({}),
      const Size(148, 40),
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
        values: {'name': '이력필터학과', 'institutionId': 'school-a', 'code': 'HIST'},
      ),
    );
    expect(repo.history, isNotEmpty);
    await repo.save(
      'super-admin',
      AdminRecord(
        id: 'document-history-filter',
        kind: AdminKind.document,
        values: {
          'name': '이력필터문서',
          'institutionId': 'school-a',
          'sourceUrl': 'https://example.org/history',
          'documentType': 'academic',
        },
      ),
    );

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
    final identifiers = find.widgetWithText(ExpansionTile, '기술 식별자');
    await tester.ensureVisible(identifiers.first);
    await tester.tap(identifiers.first);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('대상 ID: document-history-filter'),
      findsOneWidget,
    );

    await tester.ensureVisible(search);
    await tester.enterText(search, '이력필터학과');
    await tester.pumpAndSettle();
    expect(find.textContaining('요청 ID:'), findsNothing);

    await tester.ensureVisible(search);
    await tester.enterText(search, '없는검색어zzzz');
    await tester.pumpAndSettle();
    expect(find.text('검색·필터에 맞는 이력이 없습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
