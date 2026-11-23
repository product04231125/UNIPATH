import 'package:flutter/material.dart';

import '../app_tones.dart';
import 'tone_chip.dart';

/// One action in a record row's ⋮ menu.
class RecordAction {
  const RecordAction(
    this.label,
    this.icon,
    this.onSelected, {
    this.destructive = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onSelected;
  final bool destructive;
}

/// Saved record row: kind icon, title, chips, short summary, and a ⋮ menu.
/// Tapping the row runs [onTap] (usually edit) so the menu stays secondary.
class RecordTile extends StatelessWidget {
  const RecordTile({
    super.key,
    required this.icon,
    required this.title,
    this.tone = AppTone.accent,
    this.chips = const [],
    this.lines = const [],
    this.onTap,
    this.actions = const [],
    this.trailing = const [],
  });

  final IconData icon;
  final AppTone tone;
  final String title;
  final List<Widget> chips;

  /// Summary lines, each cut to two lines.
  final List<String> lines;
  final VoidCallback? onTap;
  final List<RecordAction> actions;

  /// Extra compact widgets before the menu, such as an evidence link.
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconBadge(icon: icon, tone: tone, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  ...trailing,
                  if (actions.isNotEmpty)
                    _menu(colors)
                  else
                    const SizedBox(width: 10),
                ],
              ),
              // Details use the card's full width under the title row.
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(spacing: 6, runSpacing: 6, children: chips),
                    ],
                    for (final line in lines) ...[
                      const SizedBox(height: 8),
                      Text(
                        line,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menu(ColorScheme colors) => PopupMenuButton<int>(
    tooltip: '$title 메뉴',
    icon: const Icon(Icons.more_vert),
    onSelected: (index) => actions[index].onSelected(),
    itemBuilder: (context) => [
      for (var i = 0; i < actions.length; i++)
        PopupMenuItem<int>(
          value: i,
          child: Row(
            children: [
              Icon(
                actions[i].icon,
                size: 20,
                color: actions[i].destructive ? colors.error : null,
              ),
              const SizedBox(width: 12),
              Text(
                actions[i].label,
                style: actions[i].destructive
                    ? TextStyle(color: colors.error)
                    : null,
              ),
            ],
          ),
        ),
    ],
  );
}

/// Row of headline numbers above a list (hours, credits, counts).
class StatStrip extends StatelessWidget {
  const StatStrip({super.key, required this.items});

  /// (label, value) pairs; each value is shown large.
  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 32,
      runSpacing: 12,
      children: [
        for (final (label, value) in items)
          Column(
            key: ValueKey('stat-$label'),
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(fontSize: 22),
              ),
            ],
          ),
      ],
    );
  }
}

/// Compact one-line notice with an optional action, for context the user
/// can act on (e.g. register a profile to unlock catalog suggestions).
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.icon,
    required this.message,
    this.action,
    this.tone = AppTone.info,
  });

  final IconData icon;
  final String message;
  final Widget? action;
  final AppTone tone;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
    decoration: BoxDecoration(
      color: tone.container(context),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(icon, size: 20, color: tone.color(context)),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
        if (action case final child?) ...[const SizedBox(width: 8), child],
      ],
    ),
  );
}
