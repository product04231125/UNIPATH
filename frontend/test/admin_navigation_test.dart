import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/app_navigation.dart';
import 'package:university_path_frontend/app_shell/workspace_title_bar.dart';
import 'package:university_path_frontend/features/admin/admin_repository.dart';
import 'package:university_path_frontend/features/admin/admin_workspace.dart';
import 'package:university_path_frontend/features/auth/app_role.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';

void main() {
  testWidgets('title navigation and sidebar toggle preserve settings edits', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const UniversityPathApp(startAuthenticated: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('설정').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '작성 중 프로필');
    await tester.tap(find.byTooltip('사이드바 축소'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('홈'), findsOneWidget);
    expect(find.byTooltip('설정'), findsOneWidget);
    expect(find.byKey(const Key('logout-button')), findsOneWidget);
    expect(find.text('작성 중 프로필'), findsOneWidget);
    await tester.tap(find.byTooltip('사이드바 펼치기'));
    await tester.pumpAndSettle();
    expect(find.text('작성 중 프로필'), findsOneWidget);
    await tester.tap(find.byTooltip('뒤로 가기'));
    await tester.pumpAndSettle();
    expect(find.text('학업과 계획'), findsNothing);
    await tester.tap(find.byTooltip('앞으로 가기'));
    await tester.pumpAndSettle();
    expect(find.text('학업과 계획'), findsOneWidget);
    expect(find.text('작성 중 프로필'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin collapse retains icon destinations and current page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = FakeAdminRepository();
    addTearDown(repo.dispose);
    var path = '/admin/overview';
    var sidebarVisible = true;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Column(
              children: [
                WorkspaceTitleBar(
                  statusLabel: '슈퍼관리자',
                  sidebarVisible: sidebarVisible,
                  onToggleSidebar: () =>
                      setState(() => sidebarVisible = !sidebarVisible),
                ),
                Expanded(
                  child: AdminWorkspace(
                    repository: repo,
                    role: AppRole.superAdmin,
                    path: path,
                    sidebarVisible: sidebarVisible,
                    onNavigate: (next) => setState(() => path = next),
                    onSignedOut: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('사이드바 축소'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('관리 현황'), findsOneWidget);
    await tester.tap(find.byTooltip('졸업요건'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('admin-section-ruleSet')), findsOneWidget);
    await tester.tap(find.byTooltip('사이드바 펼치기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('admin-section-ruleSet')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('admin-menu-/admin/rules')),
      findsOneWidget,
    );
  });

  testWidgets(
    'administrator edits and student records survive remounted admin workspace',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final personal = PersonalRecordRepository(PersonalRecordKind.activity);
      await personal.load();
      await personal.save(
        PersonalRecord(id: 'preserve', values: {'title': '합성 학생 기록'}),
      );
      final repo = FakeAdminRepository();
      addTearDown(repo.dispose);
      var path = '/admin/overview';
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => AdminWorkspace(
              repository: repo,
              role: AppRole.superAdmin,
              path: path,
              onNavigate: (next) => setState(() => path = next),
              onSignedOut: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('학교·학과'));
      await tester.pumpAndSettle();
      final form = find.byKey(
        const ValueKey('admin-registration-institution-'),
      );
      final name = find.descendant(
        of: form,
        matching: find.byKey(const ValueKey('admin-field-name')),
      );
      await tester.ensureVisible(name);
      await tester.pumpAndSettle();
      await tester.enterText(name, '합성 보존 대학');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final save = find.descendant(
        of: form,
        matching: find.widgetWithText(FilledButton, '등록'),
      );
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      await tester.tap(find.text('관리 현황'));
      await tester.pumpAndSettle();
      expect(find.text('최근 변경'), findsOneWidget);

      path = '/admin/overview';
      await tester.pumpWidget(
        MaterialApp(
          home: AdminWorkspace(
            repository: repo,
            role: AppRole.superAdmin,
            path: path,
            onNavigate: (_) {},
            onSignedOut: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('최근 변경'), findsOneWidget);
      final reread = PersonalRecordRepository(PersonalRecordKind.activity);
      await reread.load();
      expect(reread.records.single.value('title'), '합성 학생 기록');
      expect(tester.takeException(), isNull);
    },
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final role in [AppRole.schoolAdmin, AppRole.superAdmin]) {
    testWidgets('${role.name} enters shared admin and signs out', (
      tester,
    ) async {
      final repo = FakeAdminRepository();
      addTearDown(repo.dispose);
      var signedOut = false;
      await tester.pumpWidget(
        MaterialApp(
          home: AdminWorkspace(
            repository: repo,
            role: role,
            path: '/admin/overview',
            onNavigate: (_) {},
            onSignedOut: () => signedOut = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AdminWorkspace), findsOneWidget);
      expect(
        find.text('관리자 관리'),
        role == AppRole.superAdmin ? findsOneWidget : findsNothing,
      );
      await tester.ensureVisible(find.text('로그아웃'));
      await tester.tap(find.text('로그아웃'));
      await tester.pumpAndSettle();
      expect(signedOut, isTrue);
    });
  }

  testWidgets('student direct admin location is denied', (tester) async {
    final delegate = AppNavigation(authenticated: true);
    await tester.pumpWidget(
      MaterialApp.router(
        routerDelegate: delegate,
        routeInformationParser: const AppLocationParser(),
      ),
    );
    await tester.pumpAndSettle();
    await delegate.setNewRoutePath(const AppLocation('/admin/accounts'));
    await tester.pumpAndSettle();
    expect(find.text('접근할 수 없습니다.'), findsOneWidget);
  });
}
