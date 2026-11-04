import 'package:flutter/material.dart';

import '../../app_shell/phone_shell.dart';
import '../app_typography.dart';

enum FeatureLineVariant { one, two, section }

/// Shared body row: one line, two lines, or a section title.
class FeatureLine extends StatelessWidget {
  const FeatureLine.one({
    super.key,
    required String text,
    this.leading,
    this.trailing,
    this.divided = false,
  }) : variant = FeatureLineVariant.one,
       primary = text,
       secondary = null;

  const FeatureLine.two({
    super.key,
    required this.primary,
    required this.secondary,
    this.leading,
    this.trailing,
    this.divided = true,
  }) : variant = FeatureLineVariant.two;

  const FeatureLine.section({
    super.key,
    required String text,
    this.trailing,
    this.divided = false,
  }) : variant = FeatureLineVariant.section,
       primary = text,
       secondary = null,
       leading = null;

  final FeatureLineVariant variant;
  final String primary;
  final String? secondary;
  final Widget? leading;
  final Widget? trailing;
  final bool divided;

  static Widget reload({
    Key? key,
    required VoidCallback? onPressed,
    String label = '다시 읽기',
  }) => OutlinedButton.icon(
    key: key,
    onPressed: onPressed,
    icon: const Icon(Icons.refresh),
    label: Text(label),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = PhoneChromeScope.of(context);
    final colors = theme.colorScheme;
    final title = switch (variant) {
      FeatureLineVariant.section => Semantics(
        header: true,
        child: Text(
          primary,
          style: theme.textTheme.titleLarge?.merge(AppTypography.sectionStyle),
        ),
      ),
      FeatureLineVariant.two => Text(
        primary,
        style: theme.textTheme.titleSmall,
      ),
      FeatureLineVariant.one => Text(
        primary,
        style: theme.textTheme.bodyMedium,
      ),
    };
    final text = variant == FeatureLineVariant.two
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 2),
              Text(
                secondary!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          )
        : title;
    return Container(
      constraints: BoxConstraints(
        minHeight: phone || variant == FeatureLineVariant.section
            ? 0
            : phoneMinTapTarget,
      ),
      padding: EdgeInsets.symmetric(vertical: phone ? phoneListGap : 0),
      decoration: BoxDecoration(
        border: divided
            ? Border(bottom: BorderSide(color: colors.outlineVariant))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          Expanded(child: text),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Align(alignment: Alignment.centerRight, child: trailing!),
            ),
          ],
        ],
      ),
    );
  }
}
