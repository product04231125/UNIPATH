import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/widgets/horizontal_scroll_area.dart';
import 'graduation_credit_grid.dart';

class _Header {
  const _Header(this.id, this.parent, this.label, this.position);
  final String id, label;
  final String? parent;
  final int position;
}

class AcademicCreditDisplayRow {
  const AcademicCreditDisplayRow({
    required this.label,
    required this.values,
    this.note = '',
    this.emphasized = false,
  });
  final String label, note;
  final Map<String, String> values;
  final bool emphasized;
}

/// One aligned scroll surface with derived horizontal and vertical header spans.
class AcademicCreditPreview extends StatefulWidget {
  const AcademicCreditPreview({
    super.key,
    required this.grid,
    this.cellText,
    this.displayRows,
  });
  final GraduationCreditGrid grid;
  final List<AcademicCreditDisplayRow>? displayRows;
  final String Function(String rowId, String columnId, String original)?
  cellText;
  @override
  State<AcademicCreditPreview> createState() => _AcademicCreditPreviewState();
}

class _AcademicCreditPreviewState extends State<AcademicCreditPreview> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grid = widget.grid;
    final nodes = <String, _Header>{
      for (final g in grid.groups)
        g.id: _Header(g.id, g.parentId, g.label, g.position),
      for (final c in grid.columns)
        c.id: _Header(c.id, c.groupId, c.label, c.position),
    };
    List<_Header> children(String? parent) =>
        nodes.values.where((h) => h.parent == parent).toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    final leaves = <_Header>[];
    final layout = <({_Header node, int start, int span, int depth})>[];
    final seen = <String>{};
    int visit(_Header node, int depth) {
      if (!seen.add(node.id)) return 0;
      final start = leaves.length, descendants = children(node.id);
      if (descendants.isEmpty) {
        leaves.add(node);
      } else {
        for (final child in descendants) {
          visit(child, depth + 1);
        }
      }
      final span = leaves.length - start;
      if (span > 0) {
        layout.add((node: node, start: start, span: span, depth: depth));
      }
      return span;
    }

    for (final root in children(null)) {
      visit(root, 0);
    }
    if (leaves.isEmpty) return const Text('미리볼 열이 없습니다. 열 묶음과 학점 열을 작성하세요.');
    const cellWidth = 104.0, labelWidth = 150.0, noteWidth = 180.0;
    final maxDepth = layout.fold<int>(0, (v, h) => math.max(v, h.depth)) + 1;
    final bands = List<double>.filled(maxDepth, 44);
    final textStyle = Theme.of(context).textTheme.bodySmall!;
    for (final h in layout) {
      final painter = TextPainter(
        text: TextSpan(text: h.node.label, style: textStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: h.span * cellWidth - 16);
      bands[h.depth] = math.max(bands[h.depth], painter.height + 16);
      painter.dispose();
    }
    double before(int depth) =>
        bands.take(depth).fold<double>(0, (a, b) => a + b);
    final headerHeight = before(maxDepth),
        dataWidth = leaves.length * cellWidth;
    final border = Theme.of(context).colorScheme.outlineVariant;
    Widget box(
      String text,
      double width, {
      bool header = false,
      bool emphasized = false,
      double? height,
    }) => Container(
      width: width,
      height: height,
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.all(8),
      alignment: header || widget.displayRows != null
          ? Alignment.center
          : Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border.all(color: border, width: 0.5),
        color: header
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : emphasized
            ? Theme.of(context).colorScheme.primaryContainer
                  .withValues(alpha: .35)
            : null,
      ),
      child: Text(
        text,
        textAlign: widget.displayRows == null ? null : TextAlign.center,
        style: header || emphasized
            ? textStyle.copyWith(fontWeight: FontWeight.w600)
            : textStyle,
      ),
    );
    final showNotes =
        widget.displayRows == null ||
        widget.displayRows!.any((row) => row.note.isNotEmpty);
    final totalWidth = labelWidth + dataWidth + (showNotes ? noteWidth : 0);
    return HorizontalScrollArea(
      controller: _scroll,
      child: SizedBox(
        width: totalWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                box(
                  widget.displayRows == null ? '이수 경로' : '이수 경로 · 구분',
                  labelWidth,
                  header: true,
                  height: headerHeight,
                ),
                SizedBox(
                  width: dataWidth,
                  height: headerHeight,
                  child: Stack(
                    children: [
                      for (final h in layout)
                        Positioned(
                          left: h.start * cellWidth,
                          top: before(h.depth),
                          width: h.span * cellWidth,
                          height: children(h.node.id).isEmpty
                              ? headerHeight - before(h.depth)
                              : bands[h.depth],
                          child: box(
                            h.node.label,
                            h.span * cellWidth,
                            header: true,
                            height: children(h.node.id).isEmpty
                                ? headerHeight - before(h.depth)
                                : bands[h.depth],
                          ),
                        ),
                    ],
                  ),
                ),
                if (showNotes)
                  box('비고', noteWidth, header: true, height: headerHeight),
              ],
            ),
            if (widget.displayRows != null)
              for (final row in widget.displayRows!)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      box(row.label, labelWidth, emphasized: row.emphasized),
                      for (final leaf in leaves)
                        box(
                          row.values[leaf.id] ?? '',
                          cellWidth,
                          emphasized: row.emphasized,
                        ),
                      if (showNotes) box(row.note, noteWidth),
                    ],
                  ),
                ),
            if (widget.displayRows == null)
              for (final row in grid.rows)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      box(row.label, labelWidth),
                      for (final leaf in leaves)
                        box(_text(grid, row.id, leaf.id), cellWidth),
                      box(row.note, noteWidth),
                    ],
                  ),
                ),
            if (grid.rows.isEmpty) box('이수 경로 행을 추가하세요.', totalWidth),
          ],
        ),
      ),
    );
  }

  String _text(GraduationCreditGrid grid, String row, String column) {
    if (!grid.columns.any((c) => c.id == column)) return '';
    final cell = grid.cellFor(row, column);
    final original = switch (cell.kind) {
      GraduationCreditCellKind.empty => '',
      GraduationCreditCellKind.notApplicable => '-',
      GraduationCreditCellKind.number => cell.value ?? '',
    };
    return widget.cellText?.call(row, column, original) ?? original;
  }
}
