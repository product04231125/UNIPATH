import 'package:flutter/material.dart';

/// Page-header icon actions (`…` and `+`) share one look: a plain icon in the
/// body text color, so they read as a pair next to the page title.
Color pageActionColor(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface;

/// `+` at the title's right edge. [label] is the tooltip and screen-reader
/// name (e.g. `활동 추가`).
class PageAddButton extends StatelessWidget {
  const PageAddButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onPressed,
    color: pageActionColor(context),
    icon: const Icon(Icons.add),
  );
}

/// `…` menu at the title's right edge, same look as [PageAddButton].
class PageMoreMenu extends StatelessWidget {
  const PageMoreMenu({
    super.key,
    required this.itemBuilder,
    this.enabled = true,
  });

  final PopupMenuItemBuilder<void> itemBuilder;
  final bool enabled;

  @override
  Widget build(BuildContext context) => PopupMenuButton<void>(
    tooltip: '더보기',
    enabled: enabled,
    iconColor: pageActionColor(context),
    icon: const Icon(Icons.more_horiz),
    itemBuilder: itemBuilder,
  );
}
