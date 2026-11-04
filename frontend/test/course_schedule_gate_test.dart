import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/auth/guest_preview_scope.dart';
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

  testWidgets('schedule guest preview blocks add and edit with an explanation', (
    tester,
  ) async {
    final planning = await _configuredPlanning();
    addTearDown(planning.dispose);
    await planning.saveEvent(_event);
    await _showSchedule(tester, planning, guest: true);

    await tester.tap(find.widgetWithText(FilledButton, '일정 추가'));
    await tester.pumpAndSettle();
    expect(find.text(GuestPreviewScope.blockedMessage), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);

    await tester.tap(find.byTooltip('검토 일정 수정'));
    await tester.pumpAndSettle();
    expect(find.text(GuestPreviewScope.blockedMessage), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(planning.events.single.title, '검토 일정');
  });

  testWidgets('schedule blocks saving when guest preview activates in editor', (
    tester,
  ) async {
    final planning = await _configuredPlanning();
    addTearDown(planning.dispose);
    final guest = ValueNotifier(false);
    addTearDown(guest.dispose);
    await _showSchedule(tester, planning, guestState: guest);
    await tester.tap(find.widgetWithText(FilledButton, '일정 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '보존할 입력');

    guest.value = true;
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(planning.events, isEmpty);
    expect(find.text('보존할 입력'), findsOneWidget);
    expect(find.text(GuestPreviewScope.blockedMessage), findsOneWidget);
  });

  testWidgets('schedule failed save preserves input and supports retry', (
    tester,
  ) async {
    var reject = false;
    final planning = await _configuredPlanning(
      writer: (_, _) async => !reject,
    );
    addTearDown(planning.dispose);
    await _showSchedule(tester, planning);
    expect(find.text('등록된 개인 일정이 없습니다.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '일정 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '재시도 일정');
    reject = true;
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(planning.events, isEmpty);
    expect(find.text('재시도 일정'), findsOneWidget);
    expect(find.textContaining('기기에 저장하지 못했습니다.'), findsOneWidget);

    reject = false;
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    expect(planning.events.single.title, '재시도 일정');
  });

  testWidgets('schedule reports repository write blocks before editing', (
    tester,
  ) async {
    final planning = await _configuredPlanning();
    addTearDown(planning.dispose);
    planning.blockWrites(GuestPreviewScope.blockedMessage);
    await _showSchedule(tester, planning);
    await tester.tap(find.widgetWithText(FilledButton, '일정 추가'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text(GuestPreviewScope.blockedMessage), findsOneWidget);
  });

  testWidgets('schedule load failure shows retry and preserves stored events', (
    tester,
  ) async {
    final planning = await _configuredPlanning();
    addTearDown(planning.dispose);
    await planning.saveEvent(_event);
    final preferences = await SharedPreferences.getInstance();
    final key = preferences.getKeys().single;
    final original = preferences.getString(key)!;
    await preferences.setString(key, '{');
    await planning.load();
    expect(planning.loadFailed, isTrue);
    expect(planning.events.single.title, '검토 일정');
    await _showSchedule(tester, planning);
    expect(
      find.text('개인 계획을 읽지 못했습니다. 기존 저장 내용은 덮어쓰지 않습니다.'),
      findsOneWidget,
    );
    expect(find.text('등록된 개인 일정이 없습니다.'), findsNothing);
    expect(find.widgetWithText(FilledButton, '일정 추가'), findsNothing);

    await preferences.setString(key, original);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(planning.loadFailed, isFalse);
    expect(find.text('검토 일정'), findsOneWidget);
  });

  testWidgets('schedule failed deletion keeps the existing event and editor', (
    tester,
  ) async {
    var reject = false;
    final planning = await _configuredPlanning(writer: (_, _) async => !reject);
    addTearDown(planning.dispose);
    await planning.saveEvent(_event);
    await _showSchedule(tester, planning);
    await tester.tap(find.byTooltip('검토 일정 수정'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '삭제'));
    await tester.pumpAndSettle();
    reject = true;
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();
    expect(planning.events.single.title, '검토 일정');
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.textContaining('기기에 저장하지 못했습니다.'), findsOneWidget);
  });

  test('schedule queued local writes stop after repository disposal', () async {
    var writes = 0;
    final planning = await _configuredPlanning(
      writer: (_, _) async {
        writes++;
        return true;
      },
    );
    final before = writes;
    final save = planning.saveEvent(_event);
    final rejected = expectLater(save, throwsStateError);
    planning.dispose();
    await rejected;
    expect(writes, before);
  });
}

final _day = DateTime(2026, 11, 5);
final _event = PlanningEvent(
  id: 'schedule-review-event',
  title: '검토 일정',
  start: DateTime(2026, 11, 5, 9),
  end: DateTime(2026, 11, 5, 10),
  category: PlanningEventCategory.personal,
);

Future<PlanningRepository> _configuredPlanning({
  Future<bool> Function(String, String)? writer,
}) async {
  final planning = PlanningRepository(writer: writer);
  await planning.load();
  await planning.saveProfile(
    const PlanningProfile(
      school: '게이트 대학',
      department: '게이트 학과',
      admissionYear: 2024,
    ),
  );
  return planning;
}

Future<void> _showSchedule(
  WidgetTester tester,
  PlanningRepository planning, {
  bool guest = false,
  ValueNotifier<bool>? guestState,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  Widget page(bool active) => GuestPreviewScope(
    active: active,
    child: SchedulePage(repository: planning, initialDay: _day),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: guestState == null
            ? page(guest)
            : ValueListenableBuilder<bool>(
                valueListenable: guestState,
                builder: (_, active, _) => page(active),
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
