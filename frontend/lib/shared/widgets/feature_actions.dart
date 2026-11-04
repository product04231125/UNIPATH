import 'package:flutter/material.dart';

import '../../app_shell/phone_shell.dart';

/// Primary actions under a card or form. Left-aligned filled buttons only.
class FeatureActions extends StatelessWidget {
  const FeatureActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(
        top: phoneAwareGap(context, wide: 16, phone: 12),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(spacing: 8, runSpacing: 8, children: children),
      ),
    );
  }
}
