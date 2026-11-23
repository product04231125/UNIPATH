import 'package:flutter/material.dart';

import 'empty_state.dart';
import 'responsive_grid.dart';
import 'surface_card.dart';

/// Input and its result side by side on wide PC screens: a form column on
/// the left (36% of the body, 420–600 wide) and the result on the right. On
/// narrower screens the result follows the input, and the placeholder is
/// dropped so an empty result takes no space.
class WorkLayout extends StatelessWidget {
  const WorkLayout({
    super.key,
    required this.input,
    this.result,
    this.placeholder,
  });

  final Widget input;
  final Widget? result;

  /// Shown in the result column on wide screens before there is a result.
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final width = constraints.maxWidth;
      if (width < scaler.scale(LayoutWidths.wide)) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            input,
            if (result case final shown?) ...[
              const SizedBox(height: 16),
              shown,
            ],
          ],
        );
      }
      final inputWidth = (width * .36).clamp(
        scaler.scale(420),
        scaler.scale(600),
      );
      return Row(
        key: const ValueKey('work-layout-side'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: inputWidth, child: input),
          const SizedBox(width: 20),
          Expanded(child: result ?? placeholder ?? const SizedBox.shrink()),
        ],
      );
    },
  );
}

/// Empty result column: one icon and a short line.
class ResultPlaceholder extends StatelessWidget {
  const ResultPlaceholder({super.key, required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: EmptyState(icon: icon, title: title),
    ),
  );
}

/// One quiet line (icon + short text); the full explanation is a tooltip.
class NoteLine extends StatelessWidget {
  const NoteLine({
    super.key,
    required this.icon,
    required this.text,
    this.detail,
    this.color,
  });

  final IconData icon;
  final String text;
  final String? detail;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = color ?? theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: muted),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
        if (detail case final message?) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: message,
            triggerMode: TooltipTriggerMode.tap,
            child: Icon(Icons.info_outline, size: 16, color: muted),
          ),
        ],
      ],
    );
  }
}
