import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/admin/admin_repository.dart';
import 'package:university_path_frontend/features/admin/admin_school_chrome.dart';
import 'package:university_path_frontend/features/admin/admin_workspace.dart';
import 'package:university_path_frontend/features/auth/app_role.dart';
import 'package:university_path_frontend/features/auth/guest_preview_scope.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';

void main() {
  test('planning repository blocks writes in guest preview', () async {
    final repo = PlanningRepository(writer: (key, value) async => true);
    addTearDown(repo.dispose);
    repo.blockWrites(GuestPreviewScope.blockedMessage);
    await expectLater(
      repo.saveProfile(const PlanningProfile(school: 'x')),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          GuestPreviewScope.blockedMessage,
        ),
      ),
    );
  });

  testWidgets('guest preview scope reports active flag and snackbar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GuestPreviewScope(
          active: true,
          institutionId: 'school-a',
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => GuestPreviewScope.showBlockedMessage(context),
                child: const Text('막기'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(GuestPreviewScope.isActive(tester.element(find.text('막기'))), isTrue);
    expect(
      GuestPreviewScope.previewInstitutionId(tester.element(find.text('막기'))),
      'school-a',
    );
    await tester.tap(find.text('막기'));
    await tester.pump();
    expect(find.text(GuestPreviewScope.blockedMessage), findsOneWidget);
  });

  testWidgets('phone chrome keeps school id while title selector stays hidden', (
    tester,
  ) async {
    final chrome = AdminSchoolChrome();
    addTearDown(chrome.dispose);
    final repo = FakeAdminRepository();
    addTearDown(repo.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminWorkspace(
            role: AppRole.superAdmin,
            path: '/admin/overview',
            repository: repo,
            schoolChrome: chrome,
            phoneChrome: true,
            onNavigate: (_) {},
            onSignedOut: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(chrome.visible, isFalse);
    expect(chrome.schoolId, isNotEmpty);
  });

  testWidgets('initialSchoolId restores preferred school after preview exit', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    addTearDown(repo.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminWorkspace(
            role: AppRole.superAdmin,
            path: '/admin/overview',
            repository: repo,
            initialSchoolId: 'school-b',
            onNavigate: (_) {},
            onSignedOut: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final selector = find.byKey(const ValueKey('admin-school-selector'));
    expect(selector, findsOneWidget);
    expect(
      tester.widget<AnchoredSelectField<String>>(selector).value,
      'school-b',
    );
  });
}
