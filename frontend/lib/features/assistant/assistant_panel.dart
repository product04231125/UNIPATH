import 'package:flutter/material.dart';
import 'package:university_path_frontend/shared/app_typography.dart';

import 'assistant_conversation.dart';

class AssistantPanel extends StatelessWidget {
  const AssistantPanel({
    super.key,
    required this.conversation,
    required this.onClose,
    required this.width,
    this.onDetach,
  });

  final AssistantConversation conversation;
  final VoidCallback onClose;
  final VoidCallback? onDetach;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    color: Colors.white,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '대화 목업',
                      style: TextStyle(
                        fontSize: AppTypography.caption,
                        color: Color(0xff946c2e),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'AI 도우미',
                      style: TextStyle(
                        fontSize: AppTypography.section,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (onDetach != null)
                Tooltip(
                  message: '새 창으로 분리',
                  child: IconButton(
                    onPressed: onDetach,
                    icon: const Icon(Icons.open_in_new),
                  ),
                ),
              Tooltip(
                message: 'AI 도우미 닫기',
                child: IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            width < 300 || MediaQuery.textScalerOf(context).scale(14) > 16.8
                ? '화면 목업 · 서버 미연결'
                : '화면 설명용 대화입니다. 실제 RAG·공식 문서 근거·서버 대화 이력은 아직 연결되지 않았습니다.',
            style: TextStyle(
              fontSize: AppTypography.caption,
              color: Color(0xff607386),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: AnimatedBuilder(
            animation: conversation,
            builder: (context, _) => ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: conversation.messages.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final message = conversation.messages[index];
                final user = message.startsWith('나:');
                return Align(
                  alignment: user
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 285),
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: user
                          ? const Color(0xff1c425e)
                          : const Color(0xffeef4f6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      message,
                      style: TextStyle(
                        fontSize: AppTypography.body,
                        height: 1.45,
                        color: user ? Colors.white : const Color(0xff243d52),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: conversation.input,
                  onSubmitted: (_) => conversation.send(),
                  decoration: const InputDecoration(
                    hintText: '자연어로 질문해 보세요',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (width < 300)
                IconButton.filled(
                  tooltip: '보내기',
                  onPressed: conversation.send,
                  icon: const Icon(Icons.send),
                )
              else
                FilledButton(
                  onPressed: conversation.send,
                  child: const Text('보내기'),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
