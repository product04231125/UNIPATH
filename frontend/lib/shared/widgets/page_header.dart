import 'package:flutter/material.dart';

import '../../app_shell/phone_shell.dart';
import '../app_typography.dart';

/// Presentation only: the feature supplies its title and any real context.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.contextLabel,
    this.description,
    this.actions = const [],
  });

  final String title;
  final String? contextLabel;
  final String? description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = PhoneChromeScope.of(context);
    final titleStyle = phone
        ? AppTypography.pageStyle.copyWith(fontSize: phonePageTitleSize)
        : AppTypography.pageStyle;
    final heading = Semantics(
      header: true,
      child: Text(
        title,
        style: theme.textTheme.headlineMedium?.merge(titleStyle),
      ),
    );
    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(AppTypography.body) >
                  AppTypography.body * 1.2;
          final controls = Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (actions.isEmpty)
                heading
              else if (stacked) ...[
                heading,
                const SizedBox(height: 8),
                controls,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: 12),
                    // Actions keep their own width at the right edge and
                    // wrap only when they would take most of the row.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * .7,
                      ),
                      child: controls,
                    ),
                  ],
                ),
              if (contextLabel?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: 8),
                Text(
                  contextLabel!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (description?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: 8),
                Text(
                  description!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              SizedBox(height: phone ? phonePageHeaderBottomGap : 16),
            ],
          );
        },
      ),
    );
  }
}
