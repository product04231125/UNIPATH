import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/app_shell/phone_shell.dart';
import 'package:university_path_frontend/app_shell/workspace_shell.dart';
import 'package:university_path_frontend/features/admin/admin_repository.dart';
import 'package:university_path_frontend/features/admin/admin_workspace.dart';
import 'package:university_path_frontend/features/auth/app_role.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';

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
    testWidgets('student phone $size uses a 5+more bottom bar', (tester) async {
      await pumpApp(tester, size);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        tester.getSize(find.byType(NavigationBar)).height,
        phoneNavigationBarHeight,
      );
      expect(
        find.byKey(const Key('workspace-horizontal-scrollbar')),
        findsNothing,
      );
      expect(find.byTooltip('사이드바 축소'), findsNothing);
      expect(find.byTooltip('뒤로 가기'), findsNothing);
      expect(find.textContaining('기기 로컬 저장'), findsNothing);
      expect(find.byKey(const Key('mock-data-toggle')), findsNothing);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(
        [
          for (final destination in bar.destinations)
            (destination as NavigationDestination).label,
        ],
        ['일정', '졸업 요건', '홈', '자료', '채용공고 분석', '더보기'],
      );
      for (final label in ['일정', '졸업 요건', '홈', '자료', '채용공고 분석', '더보기']) {
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
    final sheet = find.byKey(const Key('phone-nav-more-sheet'));
    expect(sheet, findsOneWidget);
    const moreLabels = ['수강 관리', '활동', '자격', '설정'];
    for (final label in moreLabels) {
      expect(
        find.descendant(of: sheet, matching: find.text(label)),
        findsOneWidget,
      );
    }
    final moreXs = [
      for (final label in moreLabels)
        tester
            .getTopLeft(find.descendant(of: sheet, matching: find.text(label)))
            .dx,
    ];
    expect(moreXs, [...moreXs]..sort());
    final moreChip = tester.getSize(
      find
          .ancestor(
            of: find.descendant(of: sheet, matching: find.text('수강 관리')),
            matching: find.byType(InkWell),
          )
          .first,
    );
    expect(moreChip.width, phoneMoreChipWidth);
    expect(moreChip.height, greaterThanOrEqualTo(phoneMinTapTarget));
    expect(
      find.descendant(of: sheet, matching: find.text('계정 보안')),
      findsNothing,
    );
    for (final label in ['일정', '졸업 요건', '홈', '자료', '채용공고 분석']) {
      expect(
        find.descendant(of: sheet, matching: find.text(label)),
        findsNothing,
      );
    }
    expect(find.byKey(const Key('mock-data-toggle')), findsNothing);
    expect(find.byKey(const Key('logout-button')), findsOneWidget);

    await tester.tap(find.descendant(of: sheet, matching: find.text('수강 관리')));
    await tester.pumpAndSettle();
    expect(find.text('수강 과목 추가'), findsOneWidget);
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
    final curriculum = PersonalRecordRepository(
      PersonalRecordKind.personalCurriculumCourse,
    );
    await curriculum.load();
    await curriculum.save(
      PersonalRecord(
        id: PersonalRecord.newId(),
        values: {
          'title': '운영체제',
          'courseCode': 'CS300',
          'credits': '3',
          'category': '전공선택',
          'requiredCourse': '필수',
        },
      ),
    );
    await pumpApp(tester, const Size(390, 844));
    await tester.tap(find.byKey(const Key('phone-nav-more')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('phone-nav-more-sheet')),
        matching: find.text('수강 관리'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('수강 과목 추가'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('record-field-title')), findsNothing);
    expect(find.byKey(const ValueKey('record-field-detail')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('record-select-course')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('운영체제').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('record-field-term')),
      '2학기',
    );
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
      expect(
        tester.getSize(find.byType(NavigationBar)).height,
        phoneNavigationBarHeight,
      );
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
    await pumpAdmin(tester, const Size(390, 844), role: AppRole.schoolAdmin);
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

  testWidgets(
    'phone size without PhoneChromeScope does not activate chrome',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late bool phone;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              phone = PhoneChromeScope.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(phone, isFalse);
    },
  );

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
