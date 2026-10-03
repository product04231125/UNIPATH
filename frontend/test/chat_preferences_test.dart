import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/assistant/assistant_panel.dart';
import 'package:university_path_frontend/features/assistant/assistant_window_host.dart';
import 'package:university_path_frontend/features/settings/chat_preferences.dart';
import 'package:university_path_frontend/features/settings/chat_settings_section.dart';
import 'package:university_path_frontend/workspace.dart';

class FakeWindowHost extends AssistantWindowHost {
  bool maximized = false;
  bool open = false;
  bool fail = false;
  int creates = 0;
  int focuses = 0;
  bool supported = true;
  Completer<void>? opening;
  final maximize = StreamController<bool>.broadcast();
  final detached = StreamController<bool>.broadcast();

  @override
  bool get supportsDetached => supported;
  @override
  Future<bool> isMaximized() async => maximized;
  @override
  Stream<bool> get maximizeChanges => maximize.stream;
  @override
  Stream<bool> get detachedChanges => detached.stream;
  @override
  Future<void> openDetached(double width) async {
    if (opening != null) await opening!.future;
    if (fail) throw StateError('Window unavailable');
    if (open) {
      focuses++;
    } else {
      creates++;
      open = true;
    }
    detached.add(true);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('default, restart and reset affect only chat opening mode', () async {
    SharedPreferences.setMockInitialValues({'unrelated': 'preserve'});
    final preferences = ChatPreferences();
    await preferences.load();
    expect(preferences.mode, ChatOpeningMode.detached);
    await preferences.setMode(ChatOpeningMode.docked);
    final restarted = ChatPreferences();
    await restarted.load();
    expect(restarted.mode, ChatOpeningMode.docked);
    await restarted.setMode(ChatOpeningMode.detached);
    expect(
      (await SharedPreferences.getInstance()).getString('unrelated'),
      'preserve',
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        ChatPreferences.storageKey,
      ),
      'detached',
    );
    preferences.dispose();
    restarted.dispose();
  });

  test(
    'invalid read blocks writes and retry recovers preserved preference',
    () async {
      SharedPreferences.setMockInitialValues({
        ChatPreferences.storageKey: 'unknown',
      });
      final preferences = ChatPreferences();
      await preferences.load();
      expect(preferences.loadFailed, isTrue);
      await preferences.setMode(ChatOpeningMode.docked);
      final storage = await SharedPreferences.getInstance();
      expect(storage.getString(ChatPreferences.storageKey), 'unknown');
      await storage.setString(ChatPreferences.storageKey, 'docked');
      await preferences.retry();
      expect(preferences.loadFailed, isFalse);
      expect(preferences.mode, ChatOpeningMode.docked);
      preferences.dispose();
    },
  );

  test(
    'write failure preserves previous mode and later retry succeeds',
    () async {
      bool fail = true;
      final preferences = ChatPreferences(writer: (key, value) async => !fail);
      await preferences.load();
      await preferences.setMode(ChatOpeningMode.docked);
      expect(preferences.mode, ChatOpeningMode.detached);
      expect(preferences.error, isNotNull);
      fail = false;
      await preferences.setMode(ChatOpeningMode.docked);
      expect(preferences.mode, ChatOpeningMode.docked);
      expect(preferences.error, isNull);
      preferences.dispose();
    },
  );

  for (final mode in ChatOpeningMode.values) {
    testWidgets(
      'Windows opens in ${mode.name} mode and reuses detached window',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final preferences = ChatPreferences();
        await preferences.load();
        await preferences.setMode(mode);
        final host = FakeWindowHost();
        await tester.pumpWidget(
          MaterialApp(
            home: Workspace(
              onSignedOut: () {},
              windowHost: host,
              chatPreferences: preferences,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('AI 도우미 열기'));
        await tester.pumpAndSettle();
        if (mode == ChatOpeningMode.detached) {
          expect(host.creates, 1);
          expect(find.byType(AssistantPanel), findsNothing);
          await tester.tap(find.byTooltip('분리된 AI 도우미 앞으로'));
          await tester.pumpAndSettle();
          expect(host.creates, 1);
          expect(host.focuses, 1);
          host.maximized = true;
          host.maximize.add(true);
          host.open = false;
          host.detached.add(false);
          await tester.pumpAndSettle();
          expect(find.byType(AssistantPanel), findsOneWidget);
          expect(find.byTooltip('새 창으로 분리'), findsNothing);
        } else {
          expect(host.creates, 0);
          expect(find.byType(AssistantPanel), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        preferences.dispose();
        await host.maximize.close();
        await host.detached.close();
      },
    );
  }

  testWidgets('open failure falls back and closed window can reopen', (
    tester,
  ) async {
    final host = FakeWindowHost()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Workspace(onSignedOut: () {}, windowHost: host),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('AI 도우미 열기'));
    await tester.pumpAndSettle();
    expect(find.byType(AssistantPanel), findsOneWidget);
    expect(find.textContaining('분리 창을 열지 못해'), findsOneWidget);
    host.fail = false;
    await tester.tap(find.byTooltip('새 창으로 분리'));
    await tester.pumpAndSettle();
    expect(host.creates, 1);
    host.open = false;
    host.detached.add(false);
    await tester.pumpAndSettle();
    expect(find.byType(AssistantPanel), findsNothing);
    await tester.tap(find.byTooltip('AI 도우미 열기'));
    await tester.pumpAndSettle();
    expect(host.creates, 2);
    await tester.pumpWidget(const SizedBox());
    await host.maximize.close();
    await host.detached.close();
  });

  testWidgets(
    'settings control and reset remain usable at 200 percent in narrow viewport',
    (tester) async {
      final preferences = ChatPreferences();
      await preferences.load();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SizedBox(
                width: 320,
                child: SingleChildScrollView(
                  child: ChatSettingsSection(preferences: preferences),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('chat-opening-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('내부 패널').last);
      await tester.pumpAndSettle();
      expect(preferences.mode, ChatOpeningMode.docked);
      await tester.ensureVisible(find.text('채팅 열기 방식만 기본값으로 복원'));
      await tester.tap(find.text('채팅 열기 방식만 기본값으로 복원'));
      await tester.pumpAndSettle();
      expect(preferences.mode, ChatOpeningMode.detached);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      preferences.dispose();
    },
  );

  testWidgets(
    'maximized initial state uses dock and Web omits native setting',
    (tester) async {
      final host = FakeWindowHost()..maximized = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Workspace(onSignedOut: () {}, windowHost: host),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('AI 도우미 열기'));
      await tester.pumpAndSettle();
      expect(host.creates, 0);
      expect(find.byType(AssistantPanel), findsOneWidget);
      expect(find.byTooltip('새 창으로 분리'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      host.supported = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Workspace(onSignedOut: () {}, windowHost: host),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('설정'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatSettingsSection), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await host.maximize.close();
      await host.detached.close();
    },
  );

  testWidgets('rapid open clicks create one detached window', (tester) async {
    final host = FakeWindowHost()..opening = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Workspace(onSignedOut: () {}, windowHost: host),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('AI 도우미 열기'));
    await tester.pump();
    await tester.tap(find.byTooltip('AI 도우미 열기'));
    host.opening!.complete();
    await tester.pumpAndSettle();
    expect(host.creates, 1);
    await tester.pumpWidget(const SizedBox());
    await host.maximize.close();
    await host.detached.close();
  });
}
