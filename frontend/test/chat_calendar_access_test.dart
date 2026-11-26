import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/features/assistant/assistant_panel.dart';
import 'package:university_path_frontend/features/planning/planning_dates.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/features/planning/weekly_schedule.dart';
import 'package:university_path_frontend/features/schedule/schedule_page.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final size in [
    const Size(1440, 900),
    const Size(900, 768),
    const Size(480, 520),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'last weekly day stays reachable with chat $size scale=$scale',
        (tester) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
              ),
              child: const UniversityPathApp(startAuthenticated: true),
            ),
          );
          // MaterialApp owns MediaQuery; apply the test scale through view settings.
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpAndSettle();
          await tester.tap(find.byIcon(Icons.chat_bubble_outline));
          await tester.pumpAndSettle();
          final panel = tester.getRect(find.byType(AssistantPanel));
          if (size.width < 1180) {
            expect(panel.width, size.width);
            expect(
              find.byKey(const Key('weekly-horizontal-scrollbar')),
              findsNothing,
            );
            await tester.tap(find.byTooltip('작업 화면으로 돌아가기'));
            await tester.pumpAndSettle();
          }
          final rightEdge = size.width < 1180 ? size.width : panel.left;
          // The week strip fits its card (detailed or dots), never scrolls.
          await tester.ensureVisible(find.byType(WeeklySchedule));
          await tester.pumpAndSettle();
          final strip = tester.getRect(find.byType(WeeklySchedule));
          expect(strip.right, lessThanOrEqualTo(rightEdge));
          final last = planningWeek(DateTime.now(), WeekStartDay.sunday).last;
          final day = find.byKey(
            ValueKey('week-day-${last.toIso8601String()}'),
          );
          expect(day.hitTestable(), findsOneWidget);
          final rect = tester.getRect(day);
          expect(rect.right, lessThanOrEqualTo(rightEdge));
          await tester.tap(day);
          await tester.pumpAndSettle();
          expect(find.byType(SchedulePage), findsOneWidget);
          expect(
            find.byType(AssistantPanel),
            size.width < 1180 ? findsNothing : findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
