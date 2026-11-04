import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/admin/admin_repository.dart';
import 'package:university_path_frontend/features/admin/admin_workspace.dart';
import 'package:university_path_frontend/features/auth/app_role.dart';
import 'package:university_path_frontend/shared/widgets/feature_actions.dart';

void main() {
  testWidgets('FeatureActions keeps at least 8px between adjacent buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FeatureActions(
            children: [
              FilledButton(onPressed: null, child: Text('저장')),
              OutlinedButton(onPressed: null, child: Text('취소')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final first = tester.getRect(find.widgetWithText(FilledButton, '저장'));
    final second = tester.getRect(find.widgetWithText(OutlinedButton, '취소'));
    expect(second.left - first.right, greaterThanOrEqualTo(8));
  });

  testWidgets('admin rule switcher wrap keeps at least 8px between buttons', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    addTearDown(repo.dispose);
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminWorkspace(
            repository: repo,
            role: AppRole.superAdmin,
            path: '/admin/rules',
            onNavigate: (_) {},
            onSignedOut: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final first = tester.getRect(
      find.byKey(const ValueKey('rule-view-line')),
    );
    final second = tester.getRect(
      find.byKey(const ValueKey('rule-view-grid')),
    );
    expect(second.left - first.right, greaterThanOrEqualTo(8));
    expect(tester.takeException(), isNull);
  });
}
