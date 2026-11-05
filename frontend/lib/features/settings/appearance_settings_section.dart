import 'package:flutter/material.dart';

import '../../shared/app_style.dart';
import '../../shared/widgets/anchored_select_field.dart';

class AppearanceSettingsSection extends StatelessWidget {
  const AppearanceSettingsSection({super.key});
  @override
  Widget build(BuildContext context) {
    final appearance = AppearanceScope.maybeOf(context);
    if (appearance == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('화면 테마', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 18),
            if (appearance.loading)
              const LinearProgressIndicator()
            else if (appearance.error != null) ...[
              Text(
                appearance.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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
                      for (final p in AppPalette.values)
                        SelectOption(p, p.label),
                    ],
                    onChanged: appearance.saving ? (_) {} : appearance.select,
                  ),
                ),
              ),
            if (appearance.saving) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            const Text('선택한 테마는 이 기기에 저장됩니다. 기본값은 크림·브라운입니다.'),
          ],
        ),
      ),
    );
  }
}
