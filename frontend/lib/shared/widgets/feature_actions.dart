import 'package:flutter/material.dart';

import 'feature_line.dart';

/// Primary actions under a card or form. Left-aligned filled buttons only.
class FeatureActions extends StatelessWidget {
  const FeatureActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: FeatureLine.slotGap(context)),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(spacing: 8, runSpacing: 8, children: children),
      ),
    );
  }
}
