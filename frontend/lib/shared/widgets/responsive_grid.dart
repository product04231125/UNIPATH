import 'package:flutter/material.dart';

import 'equal_height_row.dart';

/// Page-body widths (sidebar excluded) where layouts change. Designed for
/// real PC screens: FHD at 125% gives ~1200, FHD ~1570, QHD ~2200.
abstract final class LayoutWidths {
  /// Two columns of cards side by side.
  static const medium = 820.0;

  /// Dashboard rows of three (FHD at 125% and larger).
  static const wide = 1180.0;

  /// Record cards aim for this width (QHD 6, FHD 5, FHD 125% 4 columns)
  /// so each card reads as a near-square tile, not a long strip.
  static const recordCard = 300.0;

  /// A card never gets narrower than this; the grid drops a column first.
  static const recordCardMin = 260.0;

  /// Record cards are at least this tall relative to their width.
  static const recordCardMinAspect = .8;
}

/// Equal-height rows of cards whose column count follows the available
/// width, so wide screens gain columns instead of stretching each card.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.targetItemWidth = LayoutWidths.recordCard,
    this.minItemWidth = LayoutWidths.recordCardMin,
    this.maxColumns = 6,
    this.gap = 12,
    this.minHeightFactor = LayoutWidths.recordCardMinAspect,
  });

  final List<Widget> children;

  /// Columns are chosen so each card lands near this width.
  final double targetItemWidth;
  final double minItemWidth;
  final int maxColumns;
  final double gap;

  /// In multi-column rows, cards are at least this × their width tall so
  /// sparse records still read as tiles. A single column ignores it.
  final double minHeightFactor;

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
      final itemWidth = (width - gap * (columns - 1)) / columns;
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
                        ? ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: itemWidth * minHeightFactor,
                            ),
                            child: children[start + c],
                          )
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
