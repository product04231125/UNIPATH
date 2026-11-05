import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'task_focus_group.dart';

/// Reparents the same subtrees so resizing does not reset field focus or edits.
class ResponsiveColumns extends StatefulWidget {
  const ResponsiveColumns({
    super.key,
    required this.first,
    required this.second,
    required this.enabled,
    this.stretch = false,
  });
  final Widget first, second;
  final bool enabled;

  /// When the wide row is used, both columns share the taller height.
  final bool stretch;
  @override
  State<ResponsiveColumns> createState() => _ResponsiveColumnsState();
}

class _ResponsiveColumnsState extends State<ResponsiveColumns> {
  final _first = GlobalKey(), _second = GlobalKey();
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          widget.enabled &&
          constraints.maxWidth >= 760 &&
          MediaQuery.textScalerOf(context).scale(14) <= 18;
      final first = KeyedSubtree(
        key: _first,
        child: TaskFocusGroup(child: widget.first),
      );
      final second = KeyedSubtree(
        key: _second,
        child: TaskFocusGroup(child: widget.second),
      );
      return columns
          ? widget.stretch
                ? _MatchedColumns(
                    key: const ValueKey('responsive-two-columns'),
                    gap: 24,
                    children: [first, second],
                  )
                : Row(
                    key: const ValueKey('responsive-two-columns'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: first),
                      const SizedBox(width: 24),
                      Expanded(child: second),
                    ],
                  )
          : Column(
              key: const ValueKey('responsive-one-column'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [first, const SizedBox(height: 24), second],
            );
    },
  );
}

class _MatchedColumns extends MultiChildRenderObjectWidget {
  const _MatchedColumns({
    super.key,
    required this.gap,
    required super.children,
  });

  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMatchedColumns(gap);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMatchedColumns renderObject,
  ) {
    renderObject.gap = gap;
  }
}

class _MatchedColumnsParentData extends ContainerBoxParentData<RenderBox> {}

/// Gives both columns the taller content height without clipping either.
class _RenderMatchedColumns extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _MatchedColumnsParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _MatchedColumnsParentData> {
  _RenderMatchedColumns(this._gap);

  double _gap;
  double get gap => _gap;
  set gap(double value) {
    if (_gap == value) return;
    _gap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _MatchedColumnsParentData) {
      child.parentData = _MatchedColumnsParentData();
    }
  }

  @override
  void performLayout() {
    final children = getChildrenAsList();
    final width = ((constraints.maxWidth - _gap) / 2).clamp(
      0.0,
      double.infinity,
    );
    // Outline fields report a shorter height on the first layout. A later
    // pass uses that height as a minimum so the card can still grow, and
    // both columns meet the taller result. A tight height clips the form.
    var minHeight = 0.0;
    for (var pass = 0; pass < 3; pass++) {
      final slot = BoxConstraints(
        minWidth: width,
        maxWidth: width,
        minHeight: minHeight,
      );
      var measured = 0.0;
      for (final child in children) {
        child.layout(slot, parentUsesSize: true);
        if (child.size.height > measured) measured = child.size.height;
      }
      if (pass > 0 && (measured - minHeight).abs() < 0.5) break;
      minHeight = measured;
    }
    size = constraints.constrain(Size(constraints.maxWidth, minHeight));
    var x = 0.0;
    for (var index = 0; index < children.length; index++) {
      final child = children[index];
      final data = child.parentData! as _MatchedColumnsParentData;
      data.offset = Offset(x, 0);
      x += width + (index == 0 ? _gap : 0);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
