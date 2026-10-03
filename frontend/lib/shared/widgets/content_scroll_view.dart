import 'package:flutter/material.dart';

/// Owns its scrollbar and reserves a separate gutter outside the content.
/// Vertical page/form bodies should use this instead of overlaying auto bars.
class ContentScrollView extends StatefulWidget {
  const ContentScrollView({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  State<ContentScrollView> createState() => _ContentScrollViewState();
}

class _ContentScrollViewState extends State<ContentScrollView> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
    child: Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      interactive: true,
      child: SingleChildScrollView(
        controller: _controller,
        padding: const EdgeInsetsDirectional.only(end: 16).add(widget.padding),
        child: widget.child,
      ),
    ),
  );
}
