import 'package:flutter/material.dart';

/// Local-only conversation state for the assistant mock until an API contract
/// provides a real conversation repository.
class AssistantConversation extends ChangeNotifier {
  final input = TextEditingController();
  final List<String> messages = [
    '궁금한 점이나 정리할 일을 자연어로 물어보세요. 규정 질문에는 문서 근거를 자동으로 붙입니다.',
  ];

  void send() {
    final text = input.text.trim();
    if (text.isEmpty) return;
    messages.add('나: $text');
    messages.add(
      text.contains('졸업') || text.contains('학점')
          ? '문서 근거 답변: 졸업 충족 여부는 Rule Engine 결과와 공식 문서의 페이지 근거를 함께 확인합니다.'
          : 'AI 답변: 현재 화면의 기록을 문맥으로 사용해 다음 확인 항목을 정리합니다.',
    );
    input.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }
}
