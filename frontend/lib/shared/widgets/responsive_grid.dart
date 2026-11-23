import 'package:flutter/material.dart';

import 'equal_height_row.dart';

/// Page-body widths (sidebar excluded) where layouts change. Designed for
/// real PC screens: FHD at 125% gives ~1200, FHD ~1570, QHD ~2200.
abstract final class LayoutWidths {
  /// Two columns of cards side by side.
  static const medium = 820.0;

  /// Dashboard rows of three (FHD at 125% and larger).
  static const wide = 1180.0;

  /// Record cards aim for this width (QHD 5, FHD 3, FHD 125% 3 columns)
  /// so chips and summaries wrap instead of running across the screen.
  static const recordCard = 440.0;

  /// A card never gets narrower than this; the grid drops a column first.
  static const recordCardMin = 340.0;
}

/// Equal-height rows of cards whose column count follows the available
/// width, so wide screens gain columns instead of stretching each card.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.targetItemWidth = LayoutWidths.recordCard,
    this.minItemWidth = LayoutWidths.recordCardMin,
    this.maxColumns = 5,
    this.gap = 12,
  });

  final List<Widget> children;

  /// Columns are chosen so each card lands near this width.
  final double targetItemWidth;
  final double minItemWidth;
  final int maxColumns;
  final double gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Larger text needs wider cards, so it gives up columns first.
      final scaler = MediaQuery.textScalerOf(context);
      final width = constraints.maxWidth;
      var columns = ((width + gap) / (scaler.scale(targetItemWidth) + gap))
          .round()
          .clamp(1, maxColumns);
      while (columns > 1 &&
          (width - gap * (columns - 1)) / columns <
              scaler.scale(minItemWidth)) {
        columns--;
      }
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
