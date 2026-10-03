import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/home/home_page.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/features/schedule/schedule_page.dart';
import 'package:university_path_frontend/features/settings/settings_page.dart';

const storageKey = 'university_path.personal_planning.v1';
PlanningEvent event(String title) => PlanningEvent(
  id: 'synthetic-event',
  title: title,
  start: DateTime(2026, 10, 3, 9),
  end: DateTime(2026, 10, 3, 10),
  category: PlanningEventCategory.personal,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('planning writes commit state only after successful storage', () async {
    final original = PlanningRepository();
    await original.load();
    await original.saveProfile(const PlanningProfile(school: '합성 학교'));
    await original.saveEvent(event('원본 일정'));
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    final failed = PlanningRepository(writer: (_, _) async => false);
    await failed.load();
    await expectLater(
      failed.saveProfile(const PlanningProfile(school: '변경')),
      throwsStateError,
    );
    await expectLater(failed.saveEvent(event('변경 일정')), throwsStateError);
    await expectLater(failed.deleteEvent('synthetic-event'), throwsStateError);
    expect(failed.profile.school, '합성 학교');
    expect(failed.events.single.title, '원본 일정');
    expect(prefs.getString(storageKey), raw);
    final throws = PlanningRepository(
      writer: (_, _) async => throw StateError('synthetic failure'),
    );
    await throws.load();
    await expectLater(throws.saveEvent(event('변경')), throwsStateError);
    expect(throws.events.single.title, '원본 일정');
  });

  test(
    'malformed planning blocks writes, preserves raw data and can retry',
    () async {
      final prefs = await SharedPreferences.getInstance();
      for (final raw in [
        'invalid',
        '{"profile":{"school":"부분 변경"},"events":[42]}',
        '{"profile":{},"events":[{"id":"bad","start":"bad","end":"bad"}]}',
      ]) {
        await prefs.setString(storageKey, raw);
        final repo = PlanningRepository();
        await repo.load();
        expect(repo.loadFailed, isTrue);
        expect(repo.isLoading, isFalse);
        expect(repo.profile.school, isEmpty);
        await expectLater(repo.saveEvent(event('새 일정')), throwsStateError);
        expect(prefs.getString(storageKey), raw);
        await prefs.setString(
          storageKey,
          jsonEncode({
            'profile': {'school': '복구된 합성 학교'},
            'events': [],
          }),
        );
        await repo.load();
        expect(repo.loadFailed, isFalse);
        expect(repo.profile.school, '복구된 합성 학교');
        await repo.saveEvent(event('새 일정'));
      }
    },
  );

  testWidgets(
    'settings retains failed input, retries and clears saved indicator on edits',
    (tester) async {
      var fail = true;
      final prefs = await SharedPreferences.getInstance();
      final repo = PlanningRepository(
        writer: (key, value) async =>
            fail ? false : prefs.setString(key, value),
      );
      await repo.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SettingsPage(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '새 합성 학교');
      await tester.ensureVisible(find.text('기기에 저장'));
      await tester.tap(find.text('기기에 저장'));
      await tester.pumpAndSettle();
      expect(find.textContaining('기기에 저장하지 못했습니다.'), findsOneWidget);
      expect(find.text('저장되었습니다.'), findsNothing);
      expect(repo.profile.school, isEmpty);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        '새 합성 학교',
      );
      fail = false;
      await tester.tap(find.text('기기에 저장'));
      await tester.pumpAndSettle();
      expect(find.text('저장되었습니다.'), findsOneWidget);
      expect(repo.profile.school, '새 합성 학교');
      await tester.ensureVisible(find.byType(TextFormField).first);
      await tester.enterText(find.byType(TextFormField).first, '아직 저장 안 한 수정');
      await tester.pumpAndSettle();
      expect(find.text('저장되었습니다.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'schedule retains editor on save/delete failure and confirms deletion',
    (tester) async {
      var fail = false;
      final prefs = await SharedPreferences.getInstance();
      final repo = PlanningRepository(
        writer: (key, value) async =>
            fail ? false : prefs.setString(key, value),
      );
      await repo.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SchedulePage(
              repository: repo,
              initialDay: DateTime(2026, 10, 3),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('일정 추가'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '합성 일정');
      fail = true;
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(repo.events, isEmpty);
      expect(find.textContaining('입력과 기존 일정을 유지'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        '합성 일정',
      );
      fail = false;
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(repo.events.single.title, '합성 일정');
      await tester.ensureVisible(find.byTooltip('합성 일정 수정').first);
      await tester.tap(find.byTooltip('합성 일정 수정').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(find.text('개인 일정 삭제'), findsOneWidget);
      await tester.tap(find.text('취소').last);
      await tester.pumpAndSettle();
      expect(repo.events, hasLength(1));
      fail = true;
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제').last);
      await tester.pumpAndSettle();
      expect(repo.events, hasLength(1));
      expect(find.textContaining('입력과 기존 일정을 유지'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제').last);
      await tester.pumpAndSettle();
      expect(repo.events, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final name in ['home', 'schedule', 'settings']) {
    testWidgets(
      '$name exposes read failure and retry without enabling destructive writes',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(480, 520));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(storageKey, 'invalid');
        final repo = PlanningRepository();
        await repo.load();
        final page = switch (name) {
          'home' => HomePage(
            repository: repo,
            onOpenPage: (_) {},
            onOpenSettings: () {},
            onOpenSchedule: (_) {},
          ),
          'schedule' => SchedulePage(repository: repo),
          _ => SettingsPage(repository: repo),
        };
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: page)));
        await tester.pumpAndSettle();
        expect(find.textContaining('기존 저장 내용은 덮어쓰지 않습니다.'), findsOneWidget);
        expect(prefs.getString(storageKey), 'invalid');
        await prefs.setString(
          storageKey,
          jsonEncode({
            'profile': {'school': '복구된 합성 학교'},
            'events': [],
          }),
        );
        await tester.tap(find.text('다시 시도'));
        await tester.pumpAndSettle();
        expect(find.text('다시 시도'), findsNothing);
        expect(repo.loadFailed, isFalse);
        if (name == 'settings') {
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).first)
                .controller!
                .text,
            '복구된 합성 학교',
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
