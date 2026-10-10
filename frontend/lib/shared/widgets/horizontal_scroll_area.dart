import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A comparison axis with a dedicated bottom gutter and a usable thumb after
/// fitting-to-overflowing viewport transitions. The feature owns the controller.
class HorizontalScrollArea extends StatefulWidget {
  const HorizontalScrollArea({
    super.key,
    required this.controller,
    required this.child,
    this.scrollbarKey,
  });
  final ScrollController controller;
  final Widget child;
  final Key? scrollbarKey;

  @override
  State<HorizontalScrollArea> createState() => _HorizontalScrollAreaState();
}

class _HorizontalScrollAreaState extends State<HorizontalScrollArea> {
  bool _overflow = false;
  bool _refreshScheduled = false;

  bool _metricsChanged(ScrollMetricsNotification notification) {
    if (notification.metrics.axis != Axis.horizontal ||
        notification.depth != 0) {
      return false;
    }
    if (!_refreshScheduled &&
        _overflow != (notification.metrics.maxScrollExtent > 1e-6)) {
      _refreshScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshScheduled = false;
        if (!mounted || !widget.controller.hasClients) return;
        final overflow = widget.controller.position.maxScrollExtent > 1e-6;
        if (overflow != _overflow) setState(() => _overflow = overflow);
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(
      scrollbars: false,
      dragDevices: {
        ...ScrollConfiguration.of(context).dragDevices,
        PointerDeviceKind.mouse,
      },
    ),
    child: NotificationListener<ScrollMetricsNotification>(
      onNotification: _metricsChanged,
      child: Scrollbar(
        key: widget.scrollbarKey,
        controller: widget.controller,
        thumbVisibility: _overflow,
        interactive: true,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        child: SingleChildScrollView(
          controller: widget.controller,
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.only(bottom: _overflow ? 14 : 0),
          child: widget.child,
        ),
      ),
    ),
  );
}
