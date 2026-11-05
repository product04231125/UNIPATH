// Run only as a Windows verification target. Uses synthetic data and no HTTP.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/chat_window.dart' as native;
import 'package:university_path_frontend/features/assistant/assistant_api.dart';
import 'package:university_path_frontend/features/assistant/assistant_conversation.dart';
import 'package:university_path_frontend/features/assistant/assistant_panel.dart';
import 'package:university_path_frontend/features/assistant/conversation_bridge.dart';

class SyntheticGateway implements AssistantGateway {
  int calls = 0;
  @override
  Future<AssistantResult> query(
    String question,
    SchoolQueryContext context,
  ) async {
    calls++;
    await Future<void>.delayed(const Duration(seconds: 2));
    return AssistantResult.fromJson({
      'query_id': 'synthetic',
      'status': 'insufficient_evidence',
      'reason': 'no_approved_matching_evidence',
      'answer': null,
      'citations': [],
      'missing_fields': [],
    });
  }

  @override
  void close() {}
}

void check(bool value, String name) {
  if (!value) throw StateError(name);
}

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Native smoke timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final detached = await native.isDetachedChatWindow();
  if (detached) {
    await native.initializeDetachedChatWindow();
    var offline = false;
    var loseAck = true;
    final child = RemoteConversation(
      request: (command) async {
        if (offline) throw StateError('synthetic transport interruption');
        final snapshot = await native.requestConversation(command);
        if (command?['action'] == 'send' && loseAck) {
          loseAck = false;
          throw StateError('synthetic acknowledgement loss');
        }
        return snapshot;
      },
      changes: native.conversationChanges(),
    );
    native.bindConversationClose(child.prepareClose);
    runApp(
      MaterialApp(
        theme: universityPathTheme(),
        home: Scaffold(
          body: AssistantPanel(
            conversation: child,
            width: 360,
            onClose: native.closeDetachedChatWindow,
          ),
        ),
      ),
    );
    await child.load();
    check(child.turns.single.question == '메인 합성 질문', 'initial history');
    check(child.input.text == '메인 작성 초안', 'initial draft');
    check(child.sending, 'request alive during native detach');
    offline = true;
    child.input.text = '분리 창 합성 초안';
    await child.flush();
    check(!await child.prepareClose(), 'offline close guard');
    check(child.input.text == '분리 창 합성 초안', 'offline draft preserved');
    offline = false;
    await child.load();
    await until(() => !child.sending);
    child.input.text = '분리 창 합성 질문';
    await child.flush();
    await child.send();
    check(child.connectionError != null, 'ack loss visible');
    await child.load();
    await until(() => !child.sending);
    check(child.turns.length == 2, 'no duplicate turn');
    child.input.text = '복귀할 합성 초안';
    await child.flush();
    await native.closeDetachedChatWindow();
    return;
  }
  final report = File(
    '${Directory.current.path}/build/chat_handoff_smoke.json',
  );
  try {
    await native.initializeMainWindowCloseBehavior();
    final api = SyntheticGateway();
    final owner = AssistantConversation(api: api);
    final bridge = ConversationBridge(owner, native.publishConversation);
    native.bindConversation(bridge.read, bridge.command);
    runApp(
      MaterialApp(
        theme: universityPathTheme(),
        home: Scaffold(
          body: AssistantPanel(conversation: owner, width: 360, onClose: () {}),
        ),
      ),
    );
    owner.input.text = '메인 합성 질문';
    unawaited(owner.send());
    owner.input.text = '메인 작성 초안';
    await native.openDetachedChatWindow();
    await until(() => owner.turns.length == 2 && !owner.sending);
    await until(() => owner.input.text == '복귀할 합성 초안');
    await until(() => !owner.sending);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    check(!await native.hasDetachedChatWindow(), 'native child closed');
    check(api.calls == 2, 'exactly two owner requests');
    check(owner.turns.every((t) => t.result != null), 'responses preserved');
    await report.writeAsString(
      jsonEncode({
        'passed': true,
        'requests': api.calls,
        'turns': owner.turns.length,
        'draft_preserved': true,
        'native_child_closed': true,
      }),
    );
    await windowManager.setPreventClose(false);
    await windowManager.close();
  } catch (error) {
    await report.writeAsString(
      jsonEncode({'passed': false, 'error': error.toString()}),
    );
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }
}
