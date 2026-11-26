import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/home/home_page.dart';
import 'package:university_path_frontend/features/home/week_progress_card.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/features/schedule/schedule_page.dart';

DateTime at(DateTime day, int hour) =>
    DateTime(day.year, day.month, day.day, hour);

Future<PlanningRepository> seeded() async {
  SharedPreferences.setMockInitialValues({});
  final repo = PlanningRepository();
  await repo.load();
  final today = DateTime.now();
  final later = today.add(const Duration(days: 40));
  await repo.saveEvent(
    PlanningEvent(
      id: 'study',
      title: '합성 자격증 1주차 · 개념 정리',
      start: at(today, 21),
      end: at(today, 22),
      category: PlanningEventCategory.academic,
    ),
  );
  await repo.saveEvent(
    PlanningEvent(
      id: 'done',
      title: '합성 과제 제출',
      start: at(today, 20),
      end: at(today, 21),
      category: PlanningEventCategory.personal,
      completedAt: today,
    ),
  );
  await repo.saveEvent(
    PlanningEvent(
      id: 'deadline',
      title: '합성 자격증 필기 접수 마감',
      start: at(later, 9),
      end: at(later, 10),
      category: PlanningEventCategory.deadline,
    ),
  );
  for (var i = 1; i <= 4; i++) {
    final day = today.add(Duration(days: i));
    await repo.saveEvent(
      PlanningEvent(
        id: 'soon-$i',
        title: '합성 일정 $i',
        start: at(day, 23),
        end: at(day, 23).add(const Duration(minutes: 30)),
        category: PlanningEventCategory.personal,
      ),
    );
  }
  return repo;
}

void main() {
  test('completion survives local storage', () {
    final event = PlanningEvent(
      id: 'a',
      title: '합성',
      start: DateTime(2026, 11, 24, 9),
      end: DateTime(2026, 11, 24, 10),
      category: PlanningEventCategory.academic,
      completedAt: DateTime(2026, 11, 24, 11),
    );
    final back = PlanningEvent.fromJson(event.toJson());
    expect(back.done, isTrue);
    expect(back.completedAt, DateTime(2026, 11, 24, 11));
    expect(back.withCompletion(null).done, isFalse);
    expect(
      PlanningEvent.fromJson(back.withCompletion(null).toJson()).done,
      isFalse,
    );
  });

  testWidgets('this week card counts and checks off events', (tester) async {
    final repo = await seeded();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekProgressCard(
            repository: repo,
            startsOn: WeekStartDay.monday,
            onOpenSchedule: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final count = find.byKey(const ValueKey('home-week-progress-count'));
    final total = WeekProgressCard.thisWeek(
      repo.events,
      DateTime.now(),
      WeekStartDay.monday,
    ).length;
    expect(tester.widget<Text>(count).data, '완료 1 / $total');
    await tester.tap(find.byKey(const ValueKey('home-week-done-study')));
    await tester.pumpAndSettle();
    expect(repo.events.firstWhere((e) => e.id == 'study').done, isTrue);
    expect(tester.widget<Text>(count).data, '완료 2 / $total');
    await tester.tap(find.byKey(const ValueKey('home-week-done-study')));
    await tester.pumpAndSettle();
    expect(repo.events.firstWhere((e) => e.id == 'study').done, isFalse);
    repo.dispose();
  });

  testWidgets('home hides done events and shows the nearest deadline', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = await seeded();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePage(
            repository: repo,
            onOpenPage: (_) {},
            onOpenSettings: () {},
            onOpenSchedule: (_) {},
            onAddSchedule: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final deadline = find.byKey(const ValueKey('home-next-deadline'));
    expect(deadline, findsOneWidget);
    expect(
      find.descendant(of: deadline, matching: find.text('D-40')),
      findsOneWidget,
    );
    final upcoming = find.byKey(const ValueKey('home-card-다가오는 일정'));
    expect(
      find.descendant(of: upcoming, matching: find.text('합성 과제 제출')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('home-week-progress')), findsOneWidget);
    repo.dispose();
  });

  testWidgets('schedule list checks an event off without opening the editor', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = await seeded();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchedulePage(repository: repo, initialDay: DateTime.now()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final box = find.byKey(const ValueKey('schedule-done-study'));
    await tester.ensureVisible(box);
    await tester.tap(box);
    await tester.pumpAndSettle();
    expect(find.text('일정 수정'), findsNothing);
    expect(repo.events.firstWhere((e) => e.id == 'study').done, isTrue);
    repo.dispose();
  });
}
