import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/app_navigation.dart';
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
    expect(find.text('학업 프로필'), findsNothing);
    await tester.tap(find.byTooltip('앞으로 가기'));
    await tester.pumpAndSettle();
    expect(find.text('학업 프로필'), findsOneWidget);
    expect(find.text('작성 중 프로필'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('admin collapse retains icon destinations and current page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const UniversityPathApp());
    await tester.pumpAndSettle();
    final entry = find.byKey(const Key('sample-super-admin-entry'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
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
    'administrator navigation and relogin preserve mock changes and student records',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final personal = PersonalRecordRepository(PersonalRecordKind.activity);
      await personal.load();
      await personal.save(
        PersonalRecord(id: 'preserve', values: {'title': '합성 학생 기록'}),
      );
      await tester.pumpWidget(const UniversityPathApp());
      await tester.pumpAndSettle();
      final entry = find.byKey(const Key('sample-super-admin-entry'));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      await tester.tap(find.text('학교·학과'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('학교 등록'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('admin-field-name')),
        '합성 보존 대학',
      );
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('관리 현황'));
      await tester.pumpAndSettle();
      expect(find.text('관리 가능한 학교 3개'), findsOneWidget);
      await tester.ensureVisible(find.text('로그아웃'));
      await tester.tap(find.text('로그아웃'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.text('관리 가능한 학교 3개'), findsOneWidget);
      final reread = PersonalRecordRepository(PersonalRecordKind.activity);
      await reread.load();
      expect(reread.records.single.value('title'), '합성 학생 기록');
      expect(tester.takeException(), isNull);
    },
  );
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
      await tester.ensureVisible(find.text('로그아웃'));
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
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
