import 'package:flutter/material.dart';

import 'assistant_api.dart';

class AssistantTurn {
  AssistantTurn(this.question);
  final String question;
  AssistantResult? result;
  AssistantApiException? error;
  bool loading = true;
}

/// Session-only messages. Only the question and explicitly chosen school context
/// are sent; local records and mock authentication are not API credentials.
class AssistantConversation extends ChangeNotifier {
  AssistantConversation({AssistantGateway? api}) : _api = api ?? AssistantApi();
  final AssistantGateway _api;
  final input = TextEditingController();
  final List<AssistantTurn> _turns = [];
  List<AssistantTurn> get turns => List.unmodifiable(_turns);
  SchoolQueryContext context = const SchoolQueryContext();
  bool sending = false;
  bool _disposed = false;

  void setContext(SchoolQueryContext value) {
    context = value;
    notifyListeners();
  }

  Future<void> send() async {
    final question = input.text.trim();
    if (question.isEmpty || sending) return;
    final turn = AssistantTurn(question);
    _turns.add(turn);
    await _query(turn);
  }

  Future<void> retry(AssistantTurn turn) async {
    if (sending || !_turns.contains(turn)) return;
    await _query(turn);
  }

  Future<void> _query(AssistantTurn turn) async {
    sending = true;
    turn.loading = true;
    turn.result = null;
    turn.error = null;
    notifyListeners();
    try {
      final result = await _api.query(turn.question, context);
      if (_disposed) return;
      turn.result = result;
      if (result.status == AssistantStatus.grounded ||
          result.status == AssistantStatus.insufficientEvidence) {
        if (input.text.trim() == turn.question) input.clear();
      }
    } on AssistantApiException catch (error) {
      if (_disposed) return;
      turn.error = error;
    } catch (_) {
      if (_disposed) return;
      turn.error = const AssistantApiException('질의를 처리하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (!_disposed) {
        sending = false;
        turn.loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _api.close();
    input.dispose();
    super.dispose();
  }
}
