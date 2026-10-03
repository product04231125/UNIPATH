import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/features/assistant/assistant_panel.dart';
import 'package:university_path_frontend/features/planning/planning_dates.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
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
          final scrollbar = find.byKey(
            const Key('weekly-horizontal-scrollbar'),
          );
          await tester.ensureVisible(scrollbar);
          await tester.pumpAndSettle();
          final frame = tester.getRect(scrollbar);
          final panel = tester.getRect(find.byType(AssistantPanel));
          expect(frame.right, lessThanOrEqualTo(panel.left));
          final widget = tester.widget<Scrollbar>(scrollbar);
          final controller = widget.controller!;
          if (size.width < 1180) {
            expect(widget.thumbVisibility, isTrue);
            expect(widget.interactive, isTrue);
            expect(controller.position.maxScrollExtent, greaterThan(0));
            await tester.dragFrom(
              Offset(frame.left + frame.width * .1, frame.bottom - 2),
              Offset(frame.width, 0),
              kind: PointerDeviceKind.mouse,
            );
            await tester.pumpAndSettle();
            expect(
              controller.offset,
              closeTo(controller.position.maxScrollExtent, .01),
              reason: 'frame=$frame panel=$panel',
            );
            controller.jumpTo(0);
            await tester.pump();
            await tester.sendEventToBinding(
              PointerScrollEvent(
                position: frame.center,
                scrollDelta: const Offset(1000, 0),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              controller.offset,
              closeTo(controller.position.maxScrollExtent, .01),
            );
          }
          final last = planningWeek(DateTime.now(), WeekStartDay.sunday).last;
          final day = find.byKey(
            ValueKey('week-day-${last.toIso8601String()}'),
          );
          expect(day.hitTestable(), findsOneWidget);
          final rect = tester.getRect(day);
          expect(rect.right, lessThanOrEqualTo(panel.left));
          await tester.tap(day);
          await tester.pumpAndSettle();
          expect(find.byType(SchedulePage), findsOneWidget);
          expect(find.byType(AssistantPanel), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
