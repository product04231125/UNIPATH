import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/features/schedule/schedule_page.dart';
import 'package:university_path_frontend/shared/app_style.dart';

void main() {
  for (final palette in AppPalette.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'upcoming events remain accessible in ${palette.name} at $scale',
        (tester) async {
          SharedPreferences.setMockInitialValues({
            AppAppearance.storageKey: palette.name,
          });
          await tester.binding.setSurfaceSize(const Size(1424, 861));
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(() => tester.binding.setSurfaceSize(null));
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await (FontLoader('Pretendard')..addFont(
                rootBundle.load(
                  'assets/fonts/pretendard/Pretendard-Regular.otf',
                ),
              ))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
          final repository = PlanningRepository();
          await repository.load();
          final start = DateTime(2099, 12, 15, 22);
          const title = '개인 프로젝트와 수강 계획을 점검하는 긴 일정 제목';
          for (var i = 0; i < 3; i++) {
            await repository.saveEvent(
              PlanningEvent(
                id: 'issue-66-$i',
                title: '$title $i',
                start: start.add(Duration(minutes: i * 10)),
                end: start.add(Duration(minutes: i * 10 + 5)),
                category: PlanningEventCategory.personal,
              ),
            );
          }
          repository.dispose();
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: const UniversityPathApp(startAuthenticated: true),
            ),
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
          expect(
            scroll.position.maxScrollExtent,
            scale == 1 ? 0 : greaterThan(0),
          );
          final rowTitle = tester.widget<Text>(find.text('$title 0'));
          expect(rowTitle.maxLines, scale == 1 ? 1 : isNull);
          expect(
            find.byTooltip('$title 0\n12.15 · 22:00 · 개인'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('HOME_CAPTURE')) {
            await tester.runAsync(() async {
              final output = Directory('../output/issue-66-home');
              await output.create(recursive: true);
              final frame =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 1);
              final bytes = await frame.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File('${output.path}/${palette.name}_$scale.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              frame.dispose();
            });
          }
          await tester.ensureVisible(find.text('$title 0'));
          await tester.tap(find.text('$title 0'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<SchedulePage>(find.byType(SchedulePage)).initialDay,
            start,
          );
          expect(find.text('$title 0'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
        variant: TargetPlatformVariant({TargetPlatform.windows}),
      );
    }
  }
}
