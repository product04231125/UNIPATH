import 'package:flutter/material.dart';

import 'task_focus_group.dart';

/// Reparents the same subtrees so resizing does not reset field focus or edits.
class ResponsiveColumns extends StatefulWidget {
  const ResponsiveColumns({
    super.key,
    required this.first,
    required this.second,
    required this.enabled,
  });
  final Widget first, second;
  final bool enabled;
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
          ? Row(
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
