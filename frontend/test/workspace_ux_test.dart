import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';
import 'package:university_path_frontend/features/home/home_page.dart';
import 'package:university_path_frontend/features/planning/planning_dates.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/features/planning/weekly_schedule.dart';
import 'package:university_path_frontend/app_shell/workspace_shell.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  double horizontalExtent(WidgetTester tester, Finder parent) => find
      .descendant(of: parent, matching: find.byType(Scrollable))
      .evaluate()
      .map((element) => (element as StatefulElement).state as ScrollableState)
      .where((state) => state.widget.axisDirection == AxisDirection.right)
      .fold(0.0, (total, state) => total + state.position.maxScrollExtent);

  testWidgets('responsive order collapses navigation before weekly scrolling', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1008, 900));
    await tester.pumpWidget(const UniversityPathApp(startAuthenticated: true));
    await tester.pumpAndSettle();
    expect(find.text('홈'), findsOneWidget);
    expect(
      horizontalExtent(tester, find.byType(WeeklySchedule)),
      closeTo(0, 1e-6),
    );
    for (final width in [1007.0, 950.0, 900.0, 836.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpAndSettle();
      expect(find.byTooltip('홈'), findsOneWidget);
      expect(
        horizontalExtent(tester, find.byType(WeeklySchedule)),
        closeTo(0, 1e-6),
      );
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(const Size(835, 900));
    await tester.pumpAndSettle();
    expect(find.byTooltip('홈'), findsOneWidget);
    expect(
      horizontalExtent(tester, find.byType(WeeklySchedule)),
      greaterThan(0),
    );
    await tester.binding.setSurfaceSize(const Size(1008, 900));
    await tester.pumpAndSettle();
    expect(find.text('홈'), findsOneWidget);
    expect(
      horizontalExtent(tester, find.byType(WeeklySchedule)),
      closeTo(0, 1e-6),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('responsive order includes curriculum tabs and dock width', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(const UniversityPathApp(startAuthenticated: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('졸업 요건').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('내 교육과정'));
    await tester.pumpAndSettle();
    expect(find.text('홈'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pumpAndSettle();
    expect(find.byTooltip('홈'), findsOneWidget);
    expect(horizontalExtent(tester, find.byType(Table)), 0);
    // Inspect the table's ancestor scroll view, not its descendants.
    final matrixScroll = find
        .ancestor(of: find.byType(Table), matching: find.byType(Scrollable))
        .first;
    expect(
      tester.state<ScrollableState>(matrixScroll).position.maxScrollExtent,
      0,
    );
    await tester.tap(find.byTooltip('AI 도우미 닫기'));
    await tester.pumpAndSettle();
    for (final width in [1217.0, 1046.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpAndSettle();
      expect(find.byTooltip('홈'), findsOneWidget);
      expect(
        tester.state<ScrollableState>(matrixScroll).position.maxScrollExtent,
        0,
      );
    }
    await tester.binding.setSurfaceSize(const Size(1045, 900));
    await tester.pumpAndSettle();
    expect(find.byTooltip('홈'), findsOneWidget);
    expect(
      tester.state<ScrollableState>(matrixScroll).position.maxScrollExtent,
      greaterThan(0),
    );
    // Entering/leaving the outer Web fallback must preserve the active tab.
    await tester.binding.setSurfaceSize(const Size(450, 900));
    await tester.pumpAndSettle();
    expect(find.byType(Table), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(1045, 900));
    await tester.pumpAndSettle();
    expect(find.byTooltip('홈'), findsOneWidget);
    expect(
      tester.state<ScrollableState>(matrixScroll).position.maxScrollExtent,
      greaterThan(0),
    );
    await tester.tap(find.text('대학 공통'));
    await tester.pumpAndSettle();
    expect(find.text('홈'), findsOneWidget);
    await tester.tap(find.text('내 교육과정'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('홈'), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(1218, 900));
    await tester.pumpAndSettle();
    expect(find.text('홈'), findsOneWidget);
    expect(
      tester.state<ScrollableState>(matrixScroll).position.maxScrollExtent,
      0,
    );
    await tester.tap(find.text('설정').first);
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(950, 900));
    await tester.pumpAndSettle();
    expect(find.text('홈'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('responsive order exposes an interactive workspace scrollbar', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(320, 900));
    await tester.pumpWidget(const UniversityPathApp(startAuthenticated: true));
    await tester.pumpAndSettle();
    expect(find.byTooltip('홈'), findsOneWidget);
    final scrollbar = find.byKey(const Key('workspace-horizontal-scrollbar'));
    final widget = tester.widget<Scrollbar>(scrollbar);
    expect(widget.thumbVisibility, isTrue);
    expect(widget.interactive, isTrue);
    expect(widget.controller!.position.maxScrollExtent, 160);
    final frame = tester.getRect(scrollbar);
    await tester.dragFrom(
      Offset(frame.left + 90, frame.bottom - 4),
      const Offset(70, 0),
    );
    await tester.pumpAndSettle();
    expect(widget.controller!.offset, greaterThan(0));
    await tester.binding.setSurfaceSize(const Size(480, 900));
    await tester.pumpAndSettle();
    expect(scrollbar, findsNothing);
    expect(find.byType(WorkspaceShell), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final populated in [false, true]) {
    testWidgets(
      'Windows initial client area has no home scroll, populated=$populated',
      (tester) async {
        // 1440x900 native outer window, excluding its title bar and borders.
        await tester.binding.setSurfaceSize(const Size(1424, 861));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        if (populated) {
          final repository = PlanningRepository();
          await repository.load();
          final now = DateTime.now();
          for (var i = 0; i < 3; i++) {
            await repository.saveEvent(
              PlanningEvent(
                id: 'initial-$i',
                title: '개인 프로젝트와 수강 계획을 점검하는 긴 일정 제목 $i',
                start: now.add(Duration(hours: i + 1)),
                end: now.add(Duration(hours: i + 2)),
                category: PlanningEventCategory.personal,
              ),
            );
          }
          repository.dispose();
        }
        await tester.pumpWidget(
          const UniversityPathApp(startAuthenticated: true),
        );
        await tester.pumpAndSettle();
        final scroll = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const Key('home-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(scroll.position.maxScrollExtent, 0);
        expect(find.text('다음에 이어갈 기록').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.binding.setSurfaceSize(const Size(1424, 600));
        await tester.pumpAndSettle();
        expect(scroll.position.maxScrollExtent, greaterThan(0));
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({TargetPlatform.windows}),
    );
  }

  test('seven-day ranges and midnight boundaries are consistent', () {
    for (final start in WeekStartDay.values) {
      final days = planningWeek(DateTime(2027, 1, 1), start);
      expect(days.length, 7);
      expect(days.first.weekday, start.weekday);
      expect(days.contains(DateTime(2027, 1, 1)), isTrue);
    }
    final event = PlanningEvent(
      id: 'boundary',
      title: '밤 일정',
      start: DateTime(2026, 10, 3, 23),
      end: DateTime(2026, 10, 4),
      category: PlanningEventCategory.personal,
    );
    expect(eventsOnDay([event], DateTime(2026, 10, 3)), hasLength(1));
    expect(eventsOnDay([event], DateTime(2026, 10, 4)), isEmpty);
  });

  for (final size in [const Size(480, 520), const Size(1440, 900)]) {
    testWidgets('all menus preserve content with enlarged text at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const UniversityPathApp(startAuthenticated: true),
        ),
      );
      await tester.pumpAndSettle();
      for (final name in [
        '일정',
        '수강 관리',
        '졸업 요건',
        '활동',
        '경험',
        '자격',
        '포트폴리오·성과',
        '설정',
      ]) {
        final navigation = size.width < 900
            ? find.byTooltip(name)
            : find.text(name).first;
        await tester.ensureVisible(navigation);
        await tester.tap(navigation);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: name);
      }
    });
  }

  testWidgets('home uses real upcoming data and opens the selected date', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = PlanningRepository();
    await repository.load();
    final now = DateTime.now();
    await repository.saveProfile(
      const PlanningProfile(
        school: '테스트대학교',
        department: '테스트학과',
        admissionYear: 2024,
        weekStartsOn: WeekStartDay.tuesday,
      ),
    );
    await repository.saveEvent(
      PlanningEvent(
        id: 'next',
        title: '개인 프로젝트 마감',
        start: now.add(const Duration(hours: 1)),
        end: now.add(const Duration(hours: 2)),
        category: PlanningEventCategory.deadline,
      ),
    );
    DateTime? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: universityPathTheme(),
        home: Scaffold(
          body: HomePage(
            repository: repository,
            onOpenPage: (_) {},
            onOpenSettings: () {},
            onOpenSchedule: (day) => selected = day,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('개인 프로젝트 마감'), findsWidgets);
    expect(find.text('기본 준비 2/2'), findsOneWidget);
    final first = planningWeek(now, WeekStartDay.tuesday).first;
    final day = find.byKey(ValueKey('week-day-${first.toIso8601String()}'));
    await tester.tap(day);
    expect(selected, first);
    await tester.tap(find.byTooltip('다음 주'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        ValueKey(
          'week-day-${first.add(const Duration(days: 7)).toIso8601String()}',
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(480, 520),
    const Size(900, 768),
    const Size(1440, 900),
    const Size(1920, 1080),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'home and seven days reflow at $size with text scale $scale',
        (tester) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            MaterialApp(
              theme: universityPathTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const UniversityPathApp(startAuthenticated: true),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(WeeklySchedule), findsOneWidget);
          expect(find.text('일정 없음'), findsNWidgets(7));
          if (size.width >= 1440 && scale == 1.0) {
            for (final element
                in find
                    .descendant(
                      of: find.byType(HomePage),
                      matching: find.byType(Scrollable),
                    )
                    .evaluate()) {
              final scroll =
                  (element as StatefulElement).state as ScrollableState;
              expect(scroll.position.maxScrollExtent, closeTo(0, 0.000001));
            }
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('selection starts below its trigger and restores focus', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    int selected = 2;
    await tester.pumpWidget(
      MaterialApp(
        theme: universityPathTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: SizedBox(
                width: 300,
                child: AnchoredSelectField<int>(
                  key: const Key('select'),
                  value: selected,
                  label: '선택',
                  options: const [
                    SelectOption(1, '첫 번째'),
                    SelectOption(2, '두 번째'),
                  ],
                  onChanged: (value) => selected = value,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final trigger = tester.getRect(find.byKey(const Key('select')));
    await tester.tap(find.byKey(const Key('select')));
    await tester.pumpAndSettle();
    final first = tester.getRect(find.byType(MenuItemButton).first);
    expect(first.left, closeTo(trigger.left, 8));
    expect(first.top, greaterThanOrEqualTo(trigger.bottom));
    await tester.tap(find.text('첫 번째'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(find.byType(MenuItemButton), findsNothing);
    expect(FocusManager.instance.primaryFocus, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNWidgets(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
  });

  testWidgets('selection fits inside the viewport near its lower edge', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(480, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: universityPathTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: SizedBox(
              width: 240,
              child: AnchoredSelectField<int>(
                value: 6,
                label: '선택',
                options: List.generate(7, (i) => SelectOption(i, '$i 항목')),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(AnchoredSelectField<int>));
    await tester.pumpAndSettle();
    for (final element in find.byType(MenuItemButton).evaluate()) {
      final rect = tester.getRect(find.byWidget(element.widget));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(480));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(520));
    }
    expect(tester.takeException(), isNull);
  });
}
