import 'package:flutter/material.dart';
import 'package:university_path_frontend/shared/app_typography.dart';

class DetachedChatWindow extends StatefulWidget {
  const DetachedChatWindow({super.key});

  @override
  State<DetachedChatWindow> createState() => _DetachedChatWindowState();
}

class _DetachedChatWindowState extends State<DetachedChatWindow> {
  final input = TextEditingController();
  final messages = <String>['독립 AI 창입니다. 현재 화면 문맥을 바탕으로 질문을 정리해 드립니다.'];

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void send() {
    final text = input.text.trim();
    if (text.isEmpty) return;
    setState(() {
      messages.add('나: $text');
      messages.add('AI 답변: 독립 창에서도 현재 작업 맥락을 기준으로 다음 확인 항목을 정리합니다.');
      input.clear();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: Color(0xff193f59),
                  child: Icon(
                    Icons.chat_bubble_outline,
                    color: Colors.white,
                    size: 17,
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RAG 기반 대화',
                        style: TextStyle(
                          fontSize: AppTypography.caption,
                          color: Color(0xff946c2e),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'AI 도우미 · 독립 창',
                        style: TextStyle(
                          fontSize: AppTypography.section,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '현재 문맥 · 졸업 요건 / 경동대학교 컴퓨터공학과 / 2024학번',
                style: TextStyle(
                  fontSize: AppTypography.caption,
                  color: Color(0xff607386),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(18),
              itemCount: messages.length,
              separatorBuilder: (_, _) => const SizedBox(height: 9),
              itemBuilder: (_, index) {
                final user = messages[index].startsWith('나:');
                return Align(
                  alignment: user
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 440),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: user
                          ? const Color(0xff1c425e)
                          : const Color(0xffeef4f6),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Text(
                      messages[index],
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    onSubmitted: (_) => send(),
                    decoration: const InputDecoration(
                      hintText: '자연어로 질문해 보세요',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: send, child: const Text('보내기')),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
