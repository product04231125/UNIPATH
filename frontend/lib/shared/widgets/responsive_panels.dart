import 'package:flutter/material.dart';

import 'responsive_columns.dart';

/// Pairs related panels; each column is a complete task before the next one.
class ResponsivePanels extends StatelessWidget {
  const ResponsivePanels({
    super.key,
    required this.children,
    this.enabled = true,
  });
  final List<Widget> children;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i += 2) ...[
        if (i > 0) const SizedBox(height: 24),
        if (i + 1 < children.length)
          ResponsiveColumns(
            enabled: enabled,
            first: children[i],
            second: children[i + 1],
          )
        else
          children[i],
      ],
    ],
  );
}
