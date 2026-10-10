import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/assistant/assistant_api.dart';
import 'package:university_path_frontend/features/assistant/assistant_conversation.dart';
import 'package:university_path_frontend/features/assistant/assistant_panel.dart';
import 'package:university_path_frontend/features/assistant/shared_school_context.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in [220.0, 360.0, 480.0]) {
    testWidgets('inline settings remain scrollable at $width and scale 2', (
      tester,
    ) async {
      final conversation = AssistantConversation();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: AssistantPanel(
                  conversation: conversation,
                  onClose: () {},
                  width: width,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('테스트용 설정창'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('질의에 사용'));
      await tester.pumpAndSettle();
      expect(find.text('질의에 사용').hitTestable(), findsOneWidget);
      expect(
        find.widgetWithText(TextField, '학교 규정 질문').hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.text('질의에 사용'));
      await tester.pumpAndSettle();
      expect(find.text('질의에 사용'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      conversation.dispose();
    });
  }

  test(
    'settings and chat share saved school fields without losing planning',
    () async {
      final repository = PlanningRepository();
      await repository.load();
      final conversation = AssistantConversation();
      final binding = SharedSchoolContext(repository, conversation);
      await repository.saveProfile(
        const PlanningProfile(
          school: '합성학교',
          track: 'double_major',
          academicYearOverride: 3,
          weekStartsOn: WeekStartDay.monday,
        ),
      );
      await repository.saveEvent(
        PlanningEvent(
          id: 'test',
          title: '합성일정',
          start: DateTime(2026, 10, 1),
          end: DateTime(2026, 10, 2),
          category: PlanningEventCategory.personal,
        ),
      );
      expect(conversation.context.institution, '합성학교');
      expect(conversation.context.track, 'double_major');
      await binding.save(
        const SchoolQueryContext(
          institution: '변경학교',
          department: '합성학과',
          admissionYear: 2026,
          track: 'single_major',
        ),
      );
      expect(repository.profile.school, '변경학교');
      expect(repository.profile.academicYearOverride, 3);
      expect(repository.profile.weekStartsOn, WeekStartDay.monday);
      expect(repository.events.single.title, '합성일정');
      final reloaded = PlanningRepository();
      await reloaded.load();
      expect(reloaded.profile.track, 'single_major');
      expect(conversation.context.department, '합성학과');
      binding.dispose();
      conversation.dispose();
      repository.dispose();
      reloaded.dispose();
    },
  );

  test('failed chat save does not publish unsaved context', () async {
    final repository = PlanningRepository(writer: (_, _) async => false);
    await repository.load();
    final conversation = AssistantConversation();
    final binding = SharedSchoolContext(repository, conversation);
    await expectLater(
      binding.save(const SchoolQueryContext(institution: '미저장')),
      throwsStateError,
    );
    expect(conversation.context.institution, isNull);
    expect(repository.profile.school, isEmpty);
    binding.dispose();
    conversation.dispose();
    repository.dispose();
  });
}
