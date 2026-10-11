import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/assistant/assistant_api.dart';
import 'package:university_path_frontend/features/assistant/assistant_conversation.dart';
import 'package:university_path_frontend/features/assistant/assistant_panel.dart';
import 'package:university_path_frontend/features/assistant/shared_school_context.dart';
import 'package:university_path_frontend/features/assistant/remote_school_profile.dart';
import 'package:university_path_frontend/features/assistant/detached_chat_page.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/features/settings/settings_page.dart';

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

  test('concurrent chat and event saves preserve both in storage', () async {
    final firstWrite = Completer<void>();
    final releaseWrite = Completer<void>();
    final preferences = await SharedPreferences.getInstance();
    var writes = 0;
    final repository = PlanningRepository(
      writer: (key, value) async {
        if (++writes == 1) {
          firstWrite.complete();
          await releaseWrite.future;
        }
        return preferences.setString(key, value);
      },
    );
    await repository.load();
    final schoolSave = repository.saveSchoolContext(school: '공유 학교');
    await firstWrite.future;
    final eventSave = repository.saveEvent(
      PlanningEvent(
        id: 'concurrent-event',
        title: '보존할 일정',
        start: DateTime(2026, 10, 1, 9),
        end: DateTime(2026, 10, 1, 10),
        category: PlanningEventCategory.personal,
      ),
    );
    releaseWrite.complete();
    await Future.wait([schoolSave, eventSave]);
    final restored = PlanningRepository();
    await restored.load();
    expect(restored.profile.school, '공유 학교');
    expect(restored.events.single.title, '보존할 일정');
    final stored = jsonDecode(
      preferences.getString('university_path.personal_planning.v1')!,
    ) as Map;
    expect((stored['profile'] as Map)['school'], '공유 학교');
    repository.dispose();
    restored.dispose();
  });

  test('a rejected queued save leaves later writes usable', () async {
    var writes = 0;
    final preferences = await SharedPreferences.getInstance();
    final repository = PlanningRepository(
      writer: (key, value) async {
        if (++writes == 1) return false;
        return preferences.setString(key, value);
      },
    );
    await repository.load();
    final failure = expectLater(
      repository.saveSchoolContext(school: '거절된 학교'),
      throwsStateError,
    );
    final success = repository.saveSchoolContext(school: '저장된 학교');
    await Future.wait([failure, success]);
    expect(repository.profile.school, '저장된 학교');
    final restored = PlanningRepository();
    await restored.load();
    expect(restored.profile.school, '저장된 학교');
    restored.dispose();
    repository.dispose();
  });

  test(
    'remote profile retries reads and shares confirmed owner values',
    () async {
      final owner = PlanningRepository();
      await owner.load();
      await owner.saveProfile(
        const PlanningProfile(school: '메인 학교', academicYearOverride: 4),
      );
      final changes = StreamController<Map<String, dynamic>>.broadcast(
        sync: true,
      );
      var failRead = true;
      var failSave = false;
      final remote = RemoteSchoolProfile(
        changes: changes.stream,
        request: (update) async {
          if (update == null) {
            if (failRead) throw StateError('synthetic bridge failure');
          } else {
            if (failSave) throw StateError('synthetic save failure');
            await owner.saveSchoolContext(
              school: update['school'] as String?,
              department: update['department'] as String?,
              admissionYear: update['admissionYear'] as int?,
              track: update['track'] as String?,
            );
          }
          return owner.profile.toJson();
        },
      );
      final conversation = AssistantConversation();
      final binding = SharedSchoolContext(remote, conversation);
      await remote.load();
      expect(remote.loadFailed, isTrue);
      expect(conversation.context.institution, isNull);
      failRead = false;
      await remote.load();
      expect(remote.loadFailed, isFalse);
      expect(conversation.context.institution, '메인 학교');
      failSave = true;
      await expectLater(
        binding.save(const SchoolQueryContext(institution: '미저장 학교')),
        throwsStateError,
      );
      expect(conversation.context.institution, '메인 학교');
      failSave = false;
      await binding.save(const SchoolQueryContext(institution: '분리 창 학교'));
      expect(owner.profile.school, '분리 창 학교');
      expect(owner.profile.academicYearOverride, 4);
      await owner.saveSchoolContext(school: '메인 창 변경');
      changes.add(owner.profile.toJson());
      expect(conversation.context.institution, '메인 창 변경');
      binding.dispose();
      remote.dispose();
      changes.add(const {});
      await changes.close();
      conversation.dispose();
      owner.dispose();
    },
  );

  testWidgets('questions wait for saved profile, including keyboard submit', (
    tester,
  ) async {
    final started = Completer<void>();
    final save = Completer<void>();
    final preferences = await SharedPreferences.getInstance();
    final repository = PlanningRepository(
      writer: (key, value) async {
        started.complete();
        await save.future;
        return preferences.setString(key, value);
      },
    );
    await repository.load();
    final requests = <Map<String, dynamic>>[];
    final conversation = AssistantConversation(
      api: AssistantApi(
        client: MockClient((request) async {
          requests.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'query_id': '280b7c97-4827-4b7b-baf8-11359d316b99',
              'status': 'insufficient_evidence',
              'reason': 'no_approved_matching_evidence',
              'answer': null,
              'citations': [],
              'missing_fields': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
    final binding = SharedSchoolContext(repository, conversation);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssistantPanel(
            conversation: conversation,
            width: 480,
            onClose: () {},
            saveContext: binding.save,
          ),
        ),
      ),
    );
    await tester.tap(find.text('테스트용 설정창'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '학교 (선택)'),
      '확인한 학교',
    );
    await tester.ensureVisible(find.text('질의에 사용'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('질의에 사용'));
    await tester.pump();
    expect(started.isCompleted, isTrue);
    final question = find.widgetWithText(TextField, '학교 규정 질문');
    await tester.enterText(question, '규정 질문');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(requests, isEmpty);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '보내기'))
          .onPressed,
      isNull,
    );
    save.complete();
    await tester.pumpAndSettle();
    expect(conversation.input.text, '규정 질문');
    await tester.tap(find.text('보내기'));
    await tester.pumpAndSettle();
    expect((requests.single['context'] as Map)['institution'], '확인한 학교');
    await tester.pumpWidget(const SizedBox());
    binding.dispose();
    conversation.dispose();
    repository.dispose();
  });

  testWidgets('settings refresh saved chat values and retain pending edits', (
    tester,
  ) async {
    final repository = PlanningRepository();
    await repository.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsPage(repository: repository)),
      ),
    );
    await repository.saveSchoolContext(school: '채팅에서 저장한 학교');
    await tester.pumpAndSettle();
    final field = find.byType(TextFormField).first;
    expect(tester.widget<TextFormField>(field).controller!.text, '채팅에서 저장한 학교');
    await tester.enterText(field, '설정에서 작성 중');
    await repository.saveSchoolContext(school: '외부 변경');
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(field).controller!.text, '설정에서 작성 중');
    expect(repository.profile.school, '외부 변경');
    await tester.pumpWidget(const SizedBox());
    repository.dispose();
  });

  testWidgets('detached read failure offers a working retry', (tester) async {
    var fails = true;
    await tester.pumpWidget(
      MaterialApp(
        home: DetachedChatWindow(
          schoolProfileFactory: () => RemoteSchoolProfile(
            request: (_) async {
              if (fails) throw StateError('synthetic bridge failure');
              return const {'school': '복구된 학교'};
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('메인 창의 학교 정보를 읽지 못했습니다.'), findsOneWidget);
    fails = false;
    await tester.tap(find.text('학교 정보 다시 읽기'));
    await tester.pumpAndSettle();
    expect(find.text('학교 정보 다시 읽기'), findsNothing);
    expect(find.textContaining('복구된 학교'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
