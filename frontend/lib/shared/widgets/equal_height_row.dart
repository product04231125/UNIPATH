import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A bounded-width row of related cards, stretched to the tallest wrapped child.
/// Callers stack cards naturally at their feature's narrow-width breakpoint.
/// Actual layout is measured rather than intrinsic estimates (notably ListTile).
class EqualHeightRow extends MultiChildRenderObjectWidget {
  const EqualHeightRow({super.key, required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEqualHeightRow(textDirection: Directionality.of(context));

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderEqualHeightRow renderObject,
  ) {
    renderObject.textDirection = Directionality.of(context);
  }
}

class _RenderEqualHeightRow extends RenderFlex {
  _RenderEqualHeightRow({required TextDirection textDirection})
    : super(
        direction: Axis.horizontal,
        crossAxisAlignment: CrossAxisAlignment.start,
        textDirection: textDirection,
      );

  @override
  void performLayout() {
    super.performLayout();
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as FlexParentData;
      child.layout(
        // Keep height unbounded above: content changes must invalidate this
        // measured row, not become an independent tight-height layout boundary.
        BoxConstraints(
          minWidth: child.size.width,
          maxWidth: child.size.width,
          minHeight: size.height,
        ),
        parentUsesSize: true,
      );
      child = data.nextSibling;
    }
  }
}
