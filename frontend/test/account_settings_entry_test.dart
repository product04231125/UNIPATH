import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/app_shell/workspace_title_bar.dart';
import 'package:university_path_frontend/features/admin/admin_repository.dart';
import 'package:university_path_frontend/features/admin/admin_workspace.dart';
import 'package:university_path_frontend/features/auth/app_role.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/features/settings/account_settings_section.dart';
import 'package:university_path_frontend/features/settings/settings_page.dart';

Finder titleBarIcon(IconData icon) => find.descendant(
  of: find.byType(WorkspaceTitleBar),
  matching: find.byIcon(icon),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [
    const Size(1440, 900),
    const Size(480, 520),
    const Size(390, 844),
  ]) {
    testWidgets('title bar omits account and application icons at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceTitleBar(
              phoneChrome: size.width < 600 && size.height / size.width > 1.6,
              onToggleSidebar: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('계정 보안'), findsNothing);
      expect(find.byTooltip('학교 관리 권한·신청 이력'), findsNothing);
      expect(find.byTooltip('학교관리자 신청 접수'), findsNothing);
      expect(titleBarIcon(Icons.manage_accounts_outlined), findsNothing);
      expect(titleBarIcon(Icons.school_outlined), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('settings hides account rows without callbacks', (tester) async {
    final repository = PlanningRepository();
    addTearDown(repository.dispose);
    await repository.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsPage(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('계정·정보'), findsNothing);
    expect(find.byKey(const Key('settings-account-security')), findsNothing);
    expect(find.byKey(const Key('settings-school-applications')), findsNothing);
  });

  testWidgets('settings opens account security and applications callbacks', (
    tester,
  ) async {
    final repository = PlanningRepository();
    addTearDown(repository.dispose);
    await repository.load();
    var security = 0;
    var applications = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountSettingsActions(
          onAccountSecurity: () => security++,
          onApplications: () => applications++,
          child: Scaffold(body: SettingsPage(repository: repository)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('계정·정보'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-account-security')));
    await tester.tap(find.byKey(const Key('settings-school-applications')));
    expect(security, 1);
    expect(applications, 1);
    expect(find.text('학교 관리 권한·신청 이력'), findsOneWidget);
  });

  testWidgets('settings shows applications only when that callback exists', (
    tester,
  ) async {
    final repository = PlanningRepository();
    addTearDown(repository.dispose);
    await repository.load();
    await tester.pumpWidget(
      MaterialApp(
        home: AccountSettingsActions(
          onAccountSecurity: () {},
          child: Scaffold(body: SettingsPage(repository: repository)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-account-security')), findsOneWidget);
    expect(find.byKey(const Key('settings-school-applications')), findsNothing);
  });

  testWidgets('admin settings uses the same account entries', (tester) async {
    final repo = FakeAdminRepository();
    addTearDown(repo.dispose);
    var security = 0;
    var applications = 0;
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AccountSettingsActions(
          onAccountSecurity: () => security++,
          onApplications: () => applications++,
          applicationLabel: '학교관리자 신청 접수',
          child: AdminWorkspace(
            repository: repo,
            role: AppRole.superAdmin,
            path: '/admin/settings',
            onNavigate: (_) {},
            onSignedOut: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('계정·정보'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('settings-account-security')),
    );
    await tester.tap(find.byKey(const Key('settings-account-security')));
    await tester.tap(find.byKey(const Key('settings-school-applications')));
    expect(security, 1);
    expect(applications, 1);
    expect(find.text('학교관리자 신청 접수'), findsWidgets);
  });

  testWidgets('sample login does not expose account security in settings', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const UniversityPathApp(startAuthenticated: true));
    await tester.pumpAndSettle();
    expect(find.byTooltip('계정 보안'), findsNothing);
    await tester.ensureVisible(find.text('설정'));
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-account-security')), findsNothing);
    expect(find.byKey(const Key('settings-school-applications')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
