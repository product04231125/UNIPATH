import 'package:flutter/material.dart';

import '../../shared/app_style.dart';
import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/feature_line.dart';
import '../../shared/widgets/surface_card.dart';

class AppearanceSettingsSection extends StatelessWidget {
  const AppearanceSettingsSection({super.key});
  @override
  Widget build(BuildContext context) {
    final appearance = AppearanceScope.maybeOf(context);
    if (appearance == null) return const SizedBox.shrink();
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FeatureLine.section(text: '화면'),
          if (appearance.loading)
            const LinearProgressIndicator()
          else if (appearance.error != null) ...[
            FeatureLine.one(text: appearance.error!),
            TextButton(
              onPressed: appearance.load,
              child: const Text('화면 설정 다시 읽기'),
            ),
          ] else
            ExcludeFocus(
              excluding: appearance.saving,
              child: IgnorePointer(
                ignoring: appearance.saving,
                child: AnchoredSelectField<AppPalette>(
                  key: const Key('appearance-palette'),
                  label: '테마 선택',
                  value: appearance.palette,
                  options: [
                    for (final p in AppPalette.values) SelectOption(p, p.label),
                  ],
                  onChanged: appearance.saving ? (_) {} : appearance.select,
                ),
              ),
            ),
          if (appearance.saving) const LinearProgressIndicator(),
          const FeatureLine.one(text: '이 기기에 저장됩니다.'),
        ],
      ),
    );
  }
}
