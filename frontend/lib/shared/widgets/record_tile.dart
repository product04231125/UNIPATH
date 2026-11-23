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

/// One labelled fact on a record card, shown on its own line with an icon.
class RecordFact {
  const RecordFact(this.icon, this.text);
  final IconData icon;
  final String text;
}

/// Near-square record card for grids: kind icon with badges and ⋮ menu on
/// top, the title, one fact per line, then a short summary. Tapping the card
/// runs [onTap] (usually edit) so the menu stays secondary.
class RecordTile extends StatelessWidget {
  const RecordTile({
    super.key,
    required this.icon,
    required this.title,
    this.tone = AppTone.accent,
    this.badges = const [],
    this.facts = const [],
    this.lines = const [],
    this.onTap,
    this.actions = const [],
    this.footer = const [],
  });

  final IconData icon;
  final AppTone tone;
  final String title;

  /// Short status or type chips beside the kind icon.
  final List<Widget> badges;
  final List<RecordFact> facts;

  /// Summary lines, each cut to two lines.
  final List<String> lines;
  final VoidCallback? onTap;
  final List<RecordAction> actions;

  /// Extra compact widgets at the bottom, such as an evidence link.
  final List<Widget> footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconBadge(icon: icon, tone: tone, size: 36),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(spacing: 6, runSpacing: 6, children: badges),
                  ),
                  if (actions.isNotEmpty)
                    _menu(colors)
                  else
                    const SizedBox(width: 12),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (facts.isNotEmpty) const SizedBox(height: 10),
                    for (final fact in facts)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Icon(
                              fact.icon,
                              size: 16,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                fact.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (lines.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Divider(height: 1, color: colors.outlineVariant),
                    ],
                    for (final line in lines) ...[
                      const SizedBox(height: 8),
                      Text(
                        line,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ],
                    if (footer.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(spacing: 6, runSpacing: 6, children: footer),
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
