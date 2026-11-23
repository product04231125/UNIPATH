import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/features/records/activity/activity_page.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/schedule/schedule_page.dart';

/// Real PC screens: QHD and FHD at 100%, FHD at 125% (1536 logical).
const _qhd = Size(2560, 1440),
    _fhd = Size(1920, 1080),
    _fhd125 = Size(1536, 864);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [_qhd, _fhd, _fhd125]) {
    testWidgets(
      'home uses dashboard columns instead of stretched cards at $size',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          const UniversityPathApp(startAuthenticated: true),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('home-dashboard-columns')),
          findsOneWidget,
        );
        Rect card(String title) =>
            tester.getRect(find.byKey(ValueKey('home-card-$title')));
        final upcoming = card('다가오는 일정');
        final prepare = card('준비 목록');
        final next = card('다음에 이어갈 기록');
        // Upcoming and setup sit side by side; shortcuts stack under setup;
        // no card spans the whole page width.
        expect(upcoming.top, closeTo(prepare.top, 0.5));
        expect(prepare.left, greaterThan(upcoming.right));
        expect(next.left, closeTo(prepare.left, 0.5));
        expect(next.top, greaterThan(prepare.bottom));
        expect(upcoming.width, lessThan(size.width * .5));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final (size, columns) in [(_qhd, 3), (_fhd, 2), (_fhd125, 2)]) {
    testWidgets('activity cards fill $columns columns at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = PersonalRecordRepository(PersonalRecordKind.activity);
      await repo.load();
      for (var i = 0; i < 3; i++) {
        await repo.save(
          PersonalRecord(
            id: 'wide-$i',
            values: {'title': '합성 활동 $i', 'reportedHours': '4'},
          ),
        );
      }
      // Inside the real shell so the sidebar takes its share of the width.
      await tester.pumpWidget(
        const UniversityPathApp(startAuthenticated: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('활동').first);
      await tester.pumpAndSettle();
      expect(find.byType(ActivityPage), findsOneWidget);
      final tops = [
        for (var i = 0; i < 3; i++)
          tester.getRect(find.byKey(ValueKey('record-activity-wide-$i'))).top,
      ];
      expect(
        tops.where((t) => (t - tops.first).abs() < .5),
        hasLength(columns),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('FHD month cells list event titles, not just dots', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(_fhd);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final planning = PlanningRepository();
    await planning.load();
    final day = DateTime(2026, 11, 27, 19);
    await planning.saveEvent(
      PlanningEvent(
        id: 'fhd-event',
        title: '포트폴리오 업데이트',
        start: day,
        end: day.add(const Duration(hours: 2)),
        category: PlanningEventCategory.personal,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchedulePage(
            repository: planning,
            initialDay: DateTime(2026, 11, 2),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(GridView),
        matching: find.textContaining('19:00 포트폴리오 업데이트'),
      ),
      findsOneWidget,
    );
    // The selected day's panel lists the month's other events.
    expect(
      find.byKey(const ValueKey('month-agenda-fhd-event')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
