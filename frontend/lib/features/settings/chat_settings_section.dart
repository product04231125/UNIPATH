import 'package:flutter/material.dart';

import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/feature_line.dart';
import '../../shared/widgets/surface_card.dart';
import 'chat_preferences.dart';

class ChatSettingsSection extends StatelessWidget {
  const ChatSettingsSection({super.key, required this.preferences});

  final ChatPreferences preferences;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: preferences,
    builder: (context, _) => Padding(
      padding: EdgeInsets.only(top: FeatureLine.slotGap(context)),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FeatureLine.section(
              text: '채팅',
              padTop: false,
              padBottom: false,
            ),
            const FeatureLine.one(text: '다음 열기부터 적용합니다.'),
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
                    SelectOption(ChatOpeningMode.detached, '분리 창'),
                    SelectOption(ChatOpeningMode.docked, '내부 패널'),
                  ],
                  onChanged: preferences.setMode,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: preferences.saving
                    ? null
                    : () => preferences.setMode(ChatOpeningMode.docked),
                icon: const Icon(Icons.restore, size: 18),
                label: const Text('채팅 열기 방식만 기본값으로 복원'),
              ),
              const FeatureLine.one(text: '이 기기의 채팅 열기만 바꿉니다.'),
            ],
            if (preferences.saving) const FeatureLine.one(text: '저장 중…'),
            if (preferences.error != null)
              Text(
                preferences.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
  );
}
