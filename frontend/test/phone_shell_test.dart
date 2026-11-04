import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/app_shell/workspace_shell.dart';
import 'package:university_path_frontend/features/admin/admin_repository.dart';
import 'package:university_path_frontend/features/admin/admin_workspace.dart';
import 'package:university_path_frontend/features/auth/app_role.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpApp(
    WidgetTester tester,
    Size size, {
    bool authenticated = true,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UniversityPathApp(startAuthenticated: authenticated),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpAdmin(
    WidgetTester tester,
    Size size, {
    AppRole role = AppRole.superAdmin,
    String path = '/admin/overview',
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = FakeAdminRepository();
    addTearDown(repo.dispose);
    var current = path;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => AdminWorkspace(
            repository: repo,
            role: role,
            path: current,
            onNavigate: (next) => setState(() => current = next),
            onSignedOut: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder barLabel(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  for (final size in [
    const Size(360, 800),
    const Size(390, 844),
    const Size(430, 932),
  ]) {
    testWidgets('student phone $size uses a 4+more bottom bar', (tester) async {
      await pumpApp(tester, size);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        find.byKey(const Key('workspace-horizontal-scrollbar')),
        findsNothing,
      );
      expect(find.byTooltip('사이드바 축소'), findsNothing);
      expect(find.byTooltip('뒤로 가기'), findsNothing);
      expect(find.textContaining('기기 로컬 저장'), findsNothing);
      expect(find.byKey(const Key('mock-data-toggle')), findsNothing);
      for (final label in ['홈', '일정', '수강 관리', '활동', '더보기']) {
        expect(barLabel(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('student phone more sheet holds remaining destinations', (
    tester,
  ) async {
    await pumpApp(tester, const Size(390, 844));
    await tester.tap(find.byKey(const Key('phone-nav-일정')));
    await tester.pumpAndSettle();
    expect(find.text('일정'), findsWidgets);

    await tester.tap(find.byKey(const Key('phone-nav-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('phone-nav-more-sheet')), findsOneWidget);
    for (final label in ['졸업 요건', '경험', '자격', '포트폴리오·성과', '설정']) {
      expect(
        find.descendant(
          of: find.byKey(const Key('phone-nav-more-sheet')),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
    expect(find.byKey(const Key('mock-data-toggle')), findsNothing);
    expect(find.byKey(const Key('logout-button')), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('phone-nav-more-sheet')),
        matching: find.text('졸업 요건'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('기준 선택'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('student phone overlay hides the bottom bar', (tester) async {
    await pumpApp(tester, const Size(390, 844));
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pumpAndSettle();
    expect(find.text('AI 도우미'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop 1440 keeps the student left sidebar', (tester) async {
    await pumpApp(tester, const Size(1440, 900));
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('수강 관리'), findsWidgets);
    expect(find.byType(WorkspaceShell), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('480x520 keeps the student left icon rail', (tester) async {
    await pumpApp(tester, const Size(480, 520));
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byTooltip('홈'), findsOneWidget);
    expect(
      find.byKey(const Key('workspace-horizontal-scrollbar')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone ratio skips the 480 horizontal fallback', (tester) async {
    await pumpApp(tester, const Size(320, 900));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      find.byKey(const Key('workspace-horizontal-scrollbar')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('student phone can add a course record', (tester) async {
    await pumpApp(tester, const Size(390, 844));
    await tester.tap(find.byKey(const Key('phone-nav-수강 관리')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('수강 과목 직접 입력'));
    await tester.pumpAndSettle();
    for (final entry in {
      'title': '운영체제',
      'term': '2026-2',
      'category': '전공선택',
      'credits': '3',
    }.entries) {
      final field = find.byKey(ValueKey('record-field-${entry.key}'));
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.value);
    }
    await tester.tap(find.text('내 기록에 저장'));
    await tester.pumpAndSettle();
    expect(find.text('운영체제'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(360, 800),
    const Size(390, 844),
    const Size(430, 932),
  ]) {
    testWidgets('admin phone $size uses a 4+more bottom bar', (tester) async {
      await pumpAdmin(tester, size);
      expect(find.byType(NavigationBar), findsOneWidget);
      for (final label in ['관리 현황', '학교·학과', '교육과정·과목', '졸업요건', '더보기']) {
        expect(barLabel(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('admin phone more sheet keeps role-filtered destinations', (
    tester,
  ) async {
    await pumpAdmin(tester, const Size(390, 844));
    await tester.tap(find.byKey(const Key('phone-nav-more')));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const Key('phone-nav-more-sheet'));
    expect(sheet, findsOneWidget);
    for (final label in ['공식 문서', '관리 이력', '설정', '관리자 관리', '학교관리자 신청 접수']) {
      expect(
        find.descendant(of: sheet, matching: find.text(label)),
        findsOneWidget,
      );
    }
    await tester.tap(find.descendant(of: sheet, matching: find.text('공식 문서')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('admin-section-document')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('school admin phone more sheet omits super-only menus', (
    tester,
  ) async {
    await pumpAdmin(
      tester,
      const Size(390, 844),
      role: AppRole.schoolAdmin,
    );
    await tester.tap(find.byKey(const Key('phone-nav-more')));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const Key('phone-nav-more-sheet'));
    expect(
      find.descendant(of: sheet, matching: find.text('설정')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('관리자 관리')),
      findsNothing,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('학교관리자 신청 접수')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin 1440 and 480x520 keep the left rail', (tester) async {
    await pumpAdmin(tester, const Size(1440, 900));
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      find.byKey(const ValueKey('admin-menu-/admin/overview')),
      findsOneWidget,
    );

    await tester.binding.setSurfaceSize(const Size(480, 520));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byTooltip('관리 현황'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
