import 'package:flutter/material.dart';

import '../../shared/app_tones.dart';
import '../api/job_recommendation_api.dart';

/// 전국 or one or more work regions as chips; 전국 and single regions exclude each other.
class RegionChips extends StatelessWidget {
  const RegionChips({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    this.keyPrefix = 'recommend-region',
  });

  /// The chosen names; empty means nothing chosen yet.
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool enabled;
  final String keyPrefix;

  /// The chosen regions in display order, without 전국.
  static List<String> ordered(Set<String> selected) => [
    for (final name in recommendationRegions)
      if (selected.contains(name)) name,
  ];

  /// `전국`, `서울·경기`, or empty when nothing is chosen.
  static String label(Set<String> selected) =>
      selected.contains(nationwideRegion)
      ? nationwideRegion
      : ordered(selected).join('·');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final name in [nationwideRegion, ...recommendationRegions])
          FilterChip(
            key: ValueKey('$keyPrefix-$name'),
            label: Text(
              name,
              style: selected.contains(name)
                  ? TextStyle(
                      color: AppTone.accent.color(context),
                      fontWeight: FontWeight.w700,
                    )
                  : null,
            ),
            selected: selected.contains(name),
            // A check and the accent fill make the chosen regions obvious.
            showCheckmark: true,
            checkmarkColor: AppTone.accent.color(context),
            selectedColor: AppTone.accent.container(context),
            side: BorderSide(
              color: selected.contains(name)
                  ? AppTone.accent.color(context)
                  : theme.colorScheme.outlineVariant,
            ),
            visualDensity: VisualDensity.compact,
            onSelected: enabled
                ? (on) {
                    final next = {...selected};
                    if (name == nationwideRegion) {
                      next.clear();
                    } else {
                      next.remove(nationwideRegion);
                    }
                    on ? next.add(name) : next.remove(name);
                    onChanged(next);
                  }
                : null,
          ),
      ],
    );
  }
}
