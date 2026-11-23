import 'package:flutter/material.dart';

import 'equal_height_row.dart';

/// Page-body widths (sidebar excluded) where layouts change. Designed for
/// real PC screens: FHD at 125% gives ~1200, FHD ~1570, QHD ~2200.
abstract final class LayoutWidths {
  /// Two columns of cards side by side.
  static const medium = 820.0;

  /// Dashboard rows of three (FHD at 125% and larger).
  static const wide = 1180.0;

  /// Narrowest comfortable record card before the grid drops a column.
  static const recordCard = 540.0;
}

/// Equal-height rows of cards whose column count follows the available
/// width, so wide screens gain columns instead of stretching each card.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = LayoutWidths.recordCard,
    this.maxColumns = 3,
    this.gap = 12,
  });

  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;
  final double gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Larger text needs wider cards, so it gives up columns first.
      final itemWidth = MediaQuery.textScalerOf(context).scale(minItemWidth);
      final columns = ((constraints.maxWidth + gap) / (itemWidth + gap))
          .floor()
          .clamp(1, maxColumns);
      if (columns == 1) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              children[i],
            ],
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var start = 0; start < children.length; start += columns) ...[
            if (start > 0) SizedBox(height: gap),
            EqualHeightRow(
              children: [
                for (var c = 0; c < columns; c++) ...[
                  if (c > 0) SizedBox(width: gap),
                  Expanded(
                    child: start + c < children.length
                        ? children[start + c]
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ],
        ],
      );
    },
  );
}
