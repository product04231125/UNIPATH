import 'package:flutter/material.dart';

import 'content_scroll_view.dart';
import 'feature_actions.dart';
import 'feature_line.dart';
import 'page_header.dart';

/// Shared feature frame: title + one line, body rows, then primary actions.
class FeaturePage extends StatelessWidget {
  const FeaturePage({
    super.key,
    required this.title,
    this.description,
    this.contextLabel,
    this.eyebrow,
    this.body = const [],
    this.actions = const [],
    this.headerActions = const [],
    this.trailing = const [],
    this.below = const [],
    this.padding = EdgeInsets.zero,
    this.scrollKey,
  });

  final String title;
  final String? description;
  final String? contextLabel;
  final String? eyebrow;
  final List<Widget> body;
  final List<Widget> actions;
  final List<Widget> headerActions;

  /// Page-level actions on the title's right edge (add, settings, more).
  final List<Widget> trailing;
  final List<Widget> below;
  final EdgeInsetsGeometry padding;
  final Key? scrollKey;

  @override
  Widget build(BuildContext context) {
    return ContentScrollView(
      key: scrollKey,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (eyebrow != null && eyebrow!.trim().isNotEmpty) ...[
            Text(eyebrow!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
          ],
          PageHeader(
            title: title,
            contextLabel: contextLabel,
            description: description,
            actions: trailing,
          ),
          if (headerActions.isNotEmpty) ...[
            Wrap(spacing: 8, runSpacing: 8, children: headerActions),
            const SizedBox(height: 16),
          ],
          ...body,
          if (actions.isNotEmpty) FeatureActions(children: actions),
          if (below.isNotEmpty) SizedBox(height: FeatureLine.slotGap(context)),
          ...below,
        ],
      ),
    );
  }
}
