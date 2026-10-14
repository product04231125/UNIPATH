import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/app_navigation.dart';
import 'package:university_path_frontend/features/admin/admin_workspace.dart';
import 'package:university_path_frontend/features/auth/app_role.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final role in [AppRole.schoolAdmin, AppRole.superAdmin]) {
    testWidgets('sample ${role.name} enters shared admin and signs out', (
      tester,
    ) async {
      await tester.pumpWidget(const UniversityPathApp());
      await tester.pumpAndSettle();
      final entry = find.byKey(
        Key(
          role == AppRole.schoolAdmin
              ? 'sample-school-admin-entry'
              : 'sample-super-admin-entry',
        ),
      );
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(AdminWorkspace), findsOneWidget);
      expect(
        find.text('관리자 관리'),
        role == AppRole.superAdmin ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.text('로그아웃'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminWorkspace), findsNothing);
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
  testWidgets(
    'sample buttons retain left student right admins at narrow enlarged size',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 520));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const UniversityPathApp());
      await tester.pumpAndSettle();
      final student = find.byKey(const Key('sample-student-entry'));
      final admin = find.byKey(const Key('sample-school-admin-entry'));
      await tester.ensureVisible(admin);
      expect(
        tester.getRect(student).left,
        lessThan(tester.getRect(admin).left),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
