import 'package:flutter/material.dart';

import '../app_tones.dart';
import '../app_typography.dart';

/// Small read-only label: a category, a period, a count or a state.
class ToneChip extends StatelessWidget {
  const ToneChip({
    super.key,
    required this.label,
    this.tone = AppTone.neutral,
    this.icon,
    this.dot = false,
  });

  final String label;
  final AppTone tone;
  final IconData? icon;

  /// Leading colored dot instead of an icon (event categories).
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final color = tone.color(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tone.container(context),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ] else if (dot) ...[
            DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: const SizedBox(width: 6, height: 6),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppTypography.caption - 1,
                height: 1.3,
                fontWeight: FontWeight.w700,
                color: tone == AppTone.neutral
                    ? Theme.of(context).colorScheme.onSurface
                    : color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon on a soft rounded tile: list leading icons and shortcuts.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    this.tone = AppTone.accent,
    this.size = 40,
  });

  final IconData icon;
  final AppTone tone;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: tone.container(context),
      borderRadius: BorderRadius.circular(size * .3),
    ),
    child: Icon(icon, size: size * .5, color: tone.color(context)),
  );
}
