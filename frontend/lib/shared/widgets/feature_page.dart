import 'package:flutter/material.dart';

import 'content_scroll_view.dart';
import 'feature_actions.dart';
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
          ),
          ...body,
          if (actions.isNotEmpty) FeatureActions(children: actions),
          ...below,
        ],
      ),
    );
  }
}
