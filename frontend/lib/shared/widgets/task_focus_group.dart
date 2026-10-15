import 'package:flutter/material.dart';

/// Task order follows widget order rather than jumping across aligned rows.
class TaskFocusGroup extends StatelessWidget {
  const TaskFocusGroup({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      FocusTraversalGroup(policy: WidgetOrderTraversalPolicy(), child: child);
}
