import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/assistant/assistant_api.dart';
import 'package:university_path_frontend/features/assistant/assistant_conversation.dart';
import 'package:university_path_frontend/features/assistant/conversation_bridge.dart';

class PendingGateway implements AssistantGateway {
  final pending = Completer<AssistantResult>();
  int calls = 0;
  bool closed = false;
  @override
  Future<AssistantResult> query(String question, SchoolQueryContext context) {
    calls++;
    return pending.future;
  }

  @override
  void close() => closed = true;
}

AssistantResult result() => AssistantResult.fromJson({
  'query_id': 'synthetic',
  'status': 'insufficient_evidence',
  'reason': 'no_approved_matching_evidence',
  'answer': null,
  'citations': [],
  'missing_fields': [],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'detach during request keeps history, draft and owner request alive',
    () async {
      final api = PendingGateway();
      final owner = AssistantConversation(api: api);
      final updates = StreamController<Map<String, dynamic>>.broadcast(
        sync: true,
      );
      final bridge = ConversationBridge(
        owner,
        (state) async => updates.add(state),
      );
      owner.input.text = '질문';
      final sending = owner.send();
      owner.input.text = '다음 질문';
      final child = RemoteConversation(
        request: (command) async =>
            command == null ? bridge.read() : bridge.command(command),
        changes: updates.stream,
      );
      await child.load();
      expect(child.turns.single.question, '질문');
      expect(child.sending, isTrue);
      expect(child.input.text, '다음 질문');
      child.input.text = '분리 창에서 이어 작성';
      await child.flush();
      expect(await child.prepareClose(), isTrue);
      child.dispose();
      expect(api.closed, isFalse);
      api.pending.complete(result());
      await sending;
      expect(
        owner.turns.single.result!.status,
        AssistantStatus.insufficientEvidence,
      );
      expect(owner.input.text, '분리 창에서 이어 작성');
      expect(api.calls, 1);
      bridge.dispose();
      owner.dispose();
      await updates.close();
    },
  );

  test(
    'lost acknowledgement retries same command without duplicate HTTP request',
    () async {
      final api = PendingGateway();
      final owner = AssistantConversation(api: api);
      final updates = StreamController<Map<String, dynamic>>.broadcast(
        sync: true,
      );
      final bridge = ConversationBridge(
        owner,
        (state) async => updates.add(state),
      );
      var loseAck = true;
      final child = RemoteConversation(
        request: (command) async {
          if (command == null) return bridge.read();
          final state = bridge.command(command);
          if (command['action'] == 'send' && loseAck) {
            loseAck = false;
            throw StateError('lost acknowledgement');
          }
          return state;
        },
        changes: updates.stream,
      );
      await child.load();
      child.input.text = '질문';
      await child.flush();
      await child.send();
      expect(child.connectionError, isNotNull);
      expect(api.calls, 1);
      await child.load();
      expect(child.connectionError, isNull);
      expect(api.calls, 1);
      api.pending.complete(result());
      await Future<void>.delayed(Duration.zero);
      expect(child.turns.single.result, isNotNull);
      child.dispose();
      bridge.dispose();
      owner.dispose();
      await updates.close();
    },
  );

  test(
    'failed input delivery preserves draft and blocks close until recovery',
    () async {
      final owner = AssistantConversation(api: PendingGateway());
      final bridge = ConversationBridge(owner, (_) async {});
      var fail = false;
      final child = RemoteConversation(
        request: (command) async {
          if (fail) throw StateError('offline');
          return command == null ? bridge.read() : bridge.command(command);
        },
        changes: const Stream.empty(),
      );
      await child.load();
      fail = true;
      child.input.text = '유실되면 안 되는 초안';
      await child.flush();
      expect(await child.prepareClose(), isFalse);
      expect(child.input.text, '유실되면 안 되는 초안');
      fail = false;
      await child.load();
      expect(owner.input.text, '유실되면 안 되는 초안');
      expect(await child.prepareClose(), isTrue);
      child.dispose();
      bridge.dispose();
      owner.dispose();
    },
  );
}
