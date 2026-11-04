import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/planning/planning_profile_cta.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/features/records/course/course_page.dart';
import 'package:university_path_frontend/features/schedule/schedule_page.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('course add is gated until academic profile is configured', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final planning = PlanningRepository();
    await planning.load();
    var openedSettings = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoursePage(
            planning: planning,
            onOpenSettings: () => openedSettings = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('수강 과목 추가'), findsNothing);
    expect(find.byKey(planningProfileSettingsCtaKey), findsOneWidget);
    expect(find.text('설정에서 학업 프로필 등록'), findsOneWidget);
    await tester.tap(find.text('설정에서 학업 프로필 등록'));
    expect(openedSettings, isTrue);

    await planning.saveProfile(
      const PlanningProfile(
        school: '게이트 대학',
        department: '게이트 학과',
        admissionYear: 2024,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(planningProfileSettingsCtaKey), findsNothing);
    expect(find.text('수강 과목 추가'), findsOneWidget);
  });

  testWidgets('schedule add is gated until academic profile is configured', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final planning = PlanningRepository();
    await planning.load();
    var openedSettings = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchedulePage(
            repository: planning,
            onOpenSettings: () => openedSettings = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '일정 추가'), findsNothing);
    expect(find.byKey(planningProfileSettingsCtaKey), findsOneWidget);
    await tester.tap(find.text('설정에서 학업 프로필 등록'));
    expect(openedSettings, isTrue);

    await planning.saveProfile(
      const PlanningProfile(
        school: '게이트 대학',
        department: '게이트 학과',
        admissionYear: 2024,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(planningProfileSettingsCtaKey), findsNothing);
    expect(find.widgetWithText(FilledButton, '일정 추가'), findsOneWidget);
  });
}
