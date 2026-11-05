import 'dart:async';

import 'package:flutter/material.dart';

import 'assistant_api.dart';
import 'assistant_conversation.dart';

Map<String, dynamic> conversationSnapshot(
  AssistantConversation conversation,
  int revision,
) => {
  'revision': revision,
  'input': conversation.input.text,
  'selection_base': conversation.input.selection.baseOffset,
  'selection_extent': conversation.input.selection.extentOffset,
  'context': conversation.context.toJson(),
  'sending': conversation.sending,
  'turns': [
    for (final t in conversation.turns)
      {
        'id': t.id,
        'question': t.question,
        'loading': t.loading,
        'result': t.result?.toJson(),
        'error': t.error == null
            ? null
            : {
                'message': t.error!.message,
                'request_id': t.error!.requestId,
                'fields': t.error!.fields,
              },
      },
  ],
};

/// The main window remains the only owner of HTTP requests and conversation.
class ConversationBridge {
  ConversationBridge(this.conversation, this.publish) {
    conversation.addListener(_changed);
    conversation.input.addListener(_changed);
  }
  final AssistantConversation conversation;
  final Future<void> Function(Map<String, dynamic>) publish;
  final Map<String, Map<String, dynamic>> _commands = {};
  int _revision = 0;
  Map<String, dynamic> read() => conversationSnapshot(conversation, _revision);
  void _changed() {
    _revision++;
    unawaited(publish(read()).catchError((Object _) {}));
  }

  Map<String, dynamic> command(Map<String, dynamic> command) {
    final id = command['command_id'] as String;
    if (_commands.containsKey(id)) return read();
    final action = command['action'] as String;
    if (!['input', 'send', 'retry'].contains(action)) {
      throw const FormatException('Unknown conversation command');
    }
    // Remember before starting async work: a lost acknowledgement cannot replay it.
    _commands[id] = command;
    if (command['input'] != null) {
      final text = command['input'] as String;
      conversation.input.value = TextEditingValue(
        text: text,
        selection: TextSelection(
          baseOffset: (command['selection_base'] as int).clamp(-1, text.length),
          extentOffset: (command['selection_extent'] as int).clamp(
            -1,
            text.length,
          ),
        ),
      );
    }
    if (action == 'send') unawaited(conversation.send());
    if (action == 'retry') {
      final turns = conversation.turns.where((t) => t.id == command['turn_id']);
      if (turns.isNotEmpty) unawaited(conversation.retry(turns.first));
    }
    return read();
  }

  void dispose() {
    conversation.removeListener(_changed);
    conversation.input.removeListener(_changed);
  }
}

/// A child renders snapshots; it never owns or cancels the owner's HTTP client.
class RemoteConversation extends AssistantConversation {
  RemoteConversation({
    required this.request,
    required Stream<Map<String, dynamic>> changes,
  }) {
    _subscription = changes.listen(_receive);
    input.addListener(_inputChanged);
  }
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>?) request;
  late final StreamSubscription<Map<String, dynamic>> _subscription;
  final List<AssistantTurn> _remoteTurns = [];
  final List<Map<String, dynamic>> _pending = [];
  final String _clientId = DateTime.now().microsecondsSinceEpoch.toString();
  int _sequence = 0;
  int _revision = -1;
  bool _applying = false;
  bool _closed = false;
  bool _ready = false;
  String? _error;
  Future<void>? _flushing;
  @override
  List<AssistantTurn> get turns => List.unmodifiable(_remoteTurns);
  @override
  bool get ready => _ready;
  @override
  String? get connectionError => _error;

  Future<void> load() async {
    try {
      await flush();
      if (_pending.isNotEmpty) return;
      _receive(await request(null));
    } catch (_) {
      _failed();
    }
  }

  void _failed() {
    if (_closed) return;
    _error = '메인 창과 연결하지 못했습니다. 작성 내용을 유지하고 다시 연결해 주세요.';
    notifyListeners();
  }

  void _receive(Map<String, dynamic> value) {
    if (_closed || (value['revision'] as int) < _revision) return;
    final rawTurns = value['turns'] as List;
    final parsed = [
      for (final raw in rawTurns)
        _parseTurn(Map<String, dynamic>.from(raw as Map)),
    ];
    final ctx = Map<String, dynamic>.from(value['context'] as Map);
    _revision = value['revision'] as int;
    _remoteTurns
      ..clear()
      ..addAll(parsed);
    context = SchoolQueryContext(
      institution: ctx['institution'] as String?,
      department: ctx['department'] as String?,
      admissionYear: ctx['admission_year'] as int?,
      track: ctx['track'] as String?,
    );
    sending = value['sending'] as bool;
    // Keep edits whose IPC acknowledgement has not arrived yet.
    if (_pending.isEmpty) {
      _applying = true;
      final text = value['input'] as String;
      input.value = TextEditingValue(
        text: text,
        selection: TextSelection(
          baseOffset: (value['selection_base'] as int).clamp(-1, text.length),
          extentOffset: (value['selection_extent'] as int).clamp(
            -1,
            text.length,
          ),
        ),
      );
      _applying = false;
    }
    _ready = true;
    _error = null;
    notifyListeners();
  }

  AssistantTurn _parseTurn(Map<String, dynamic> raw) {
    final turn = AssistantTurn(
      raw['question'] as String,
      id: raw['id'] as String,
    );
    turn.loading = raw['loading'] as bool;
    if (raw['result'] != null) {
      turn.result = AssistantResult.fromJson(
        Map<String, dynamic>.from(raw['result'] as Map),
      );
    }
    if (raw['error'] != null) {
      final error = Map<String, dynamic>.from(raw['error'] as Map);
      turn.error = AssistantApiException(
        error['message'] as String,
        requestId: error['request_id'] as String?,
        fields: List<String>.from(error['fields'] as List),
      );
    }
    return turn;
  }

  void _inputChanged() {
    if (!_applying && _ready && !_closed) _enqueue('input');
  }

  void _enqueue(String action, [String? turnId]) {
    _pending.add({
      'command_id': '$_clientId-${++_sequence}',
      'action': action,
      'input': input.text,
      'selection_base': input.selection.baseOffset,
      'selection_extent': input.selection.extentOffset,
      'turn_id': turnId,
    });
    unawaited(flush());
  }

  Future<void> flush() =>
      _flushing ??= _drain().whenComplete(() => _flushing = null);
  Future<void> _drain() async {
    while (_pending.isNotEmpty && !_closed) {
      try {
        final snapshot = await request(_pending.first);
        if (_closed) return;
        _pending.removeAt(0);
        _receive(snapshot);
      } catch (_) {
        _failed();
        return;
      }
    }
  }

  @override
  Future<void> send() async {
    if (!_ready || sending) return;
    _enqueue('send');
    await flush();
  }

  @override
  Future<void> retry(AssistantTurn turn) async {
    if (!_ready || sending) return;
    _enqueue('retry', turn.id);
    await flush();
  }

  Future<bool> prepareClose() async {
    await flush();
    return _pending.isEmpty;
  }

  @override
  void dispose() {
    _closed = true;
    _subscription.cancel();
    input.removeListener(_inputChanged);
    super.dispose();
  }
}
