// Isolated Windows session verification. Synthetic data, no HTTP or preferences.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import 'package:university_path_frontend/chat_window.dart' as native;
import 'package:university_path_frontend/features/assistant/assistant_api.dart';
import 'package:university_path_frontend/features/assistant/assistant_conversation.dart';
import 'package:university_path_frontend/features/assistant/conversation_bridge.dart';

class SyntheticGateway implements AssistantGateway {
  @override
  Future<AssistantResult> query(
    String question,
    SchoolQueryContext context,
  ) async => throw StateError('Session smoke must not send HTTP');
  @override
  void close() {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (await native.isDetachedChatWindow()) {
    await native.initializeDetachedChatWindow();
    final remote = RemoteConversation(
      request: native.requestConversation,
      changes: native.conversationChanges(),
    );
    // Logout must close even when ordinary close is vetoed by pending input.
    native.bindConversationClose(() async => false);
    runApp(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('합성 AI 세션 종료 검사'))),
      ),
    );
    await remote.load();
    return;
  }
  final report = File(
    '${Directory.current.path}/build/chat_session_smoke.json',
  );
  await report.writeAsString(jsonEncode({'passed': false, 'phase': 'started'}));
  await windowManager.ensureInitialized();
  await windowManager.hide();
  runApp(const MaterialApp(home: Scaffold(body: SizedBox())));
  AssistantConversation? owner;
  ConversationBridge? bridge;
  try {
    final received = <String>[];
    var childReady = Completer<void>();
    final main = await WindowController.fromCurrentEngine();
    await main.setWindowMethodHandler((call) async {
      if (call.method == 'read_conversation') {
        received.add(owner!.input.text);
        return bridge!.read();
      }
      if (call.method == 'conversation_ready') {
        if (!childReady.isCompleted) childReady.complete();
        return null;
      }
      throw StateError('Unexpected smoke command');
    });
    final displays = await screenRetriever.getAllDisplays();
    final origin = displays.first.visiblePosition ?? Offset.zero;
    for (final draft in ['이전 세션 합성 입력', '새 세션 합성 입력']) {
      owner = AssistantConversation(api: SyntheticGateway())
        ..input.text = draft;
      bridge = ConversationBridge(owner, (_) async {});
      childReady = Completer<void>();
      await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: true,
          arguments:
              'university_path_ai_detached_chat:${jsonEncode({'width': 360, 'height': 520, 'left': origin.dx + 20, 'top': origin.dy + 20})}',
        ),
      );
      await childReady.future.timeout(const Duration(seconds: 12));
      if (!await native.hasDetachedChatWindow()) {
        throw StateError('Child did not open');
      }
      await native.endDetachedChatSession();
      if (await native.hasDetachedChatWindow()) {
        throw StateError('Child survived session end');
      }
      bridge.dispose();
      owner.dispose();
      bridge = null;
      owner = null;
    }
    if (received.length != 2 ||
        received[0] != '이전 세션 합성 입력' ||
        received[1] != '새 세션 합성 입력') {
      throw StateError('Session input leaked across native child restart');
    }
    await report.writeAsString(
      jsonEncode({
        'passed': true,
        'sessions': 2,
        'native_children_closed': true,
        'new_session_input_only': true,
        'ordinary_close_guard_bypassed_on_logout': true,
      }),
    );
  } catch (error) {
    await report.writeAsString(
      jsonEncode({'passed': false, 'error': error.toString()}),
    );
  } finally {
    bridge?.dispose();
    owner?.dispose();
    try {
      await native.endDetachedChatSession();
    } catch (_) {}
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }
}
