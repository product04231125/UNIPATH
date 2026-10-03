import 'package:flutter/material.dart';

import '../../shared/widgets/anchored_select_field.dart';
import 'chat_preferences.dart';

class ChatSettingsSection extends StatelessWidget {
  const ChatSettingsSection({super.key, required this.preferences});

  final ChatPreferences preferences;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: preferences,
    builder: (context, _) => Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Windows 채팅', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            '열기 버튼의 다음 동작에 적용됩니다. 최대화 중에는 내부 패널을 사용합니다. 현재 열린 창은 이동하지 않습니다.',
          ),
          const SizedBox(height: 12),
          if (preferences.loading)
            const LinearProgressIndicator()
          else if (preferences.loadFailed)
            OutlinedButton(
              onPressed: preferences.retry,
              child: const Text('채팅 설정 다시 읽기'),
            )
          else ...[
            IgnorePointer(
              ignoring: preferences.saving,
              child: AnchoredSelectField<ChatOpeningMode>(
                key: const Key('chat-opening-mode'),
                label: '채팅창 열기 방식',
                value: preferences.mode,
                options: const [
                  SelectOption(ChatOpeningMode.detached, '분리 창 (기본)'),
                  SelectOption(ChatOpeningMode.docked, '내부 패널'),
                ],
                onChanged: preferences.setMode,
              ),
            ),
            TextButton(
              onPressed: preferences.saving
                  ? null
                  : () => preferences.setMode(ChatOpeningMode.detached),
              child: const Text('채팅 열기 방식만 기본값으로 복원'),
            ),
            const Text('현재 기기에만 저장합니다. 학업·일정·개인 기록·대화는 삭제하지 않습니다.'),
          ],
          if (preferences.saving) const Text('저장 중…'),
          if (preferences.error != null)
            Text(
              preferences.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
  );
}
