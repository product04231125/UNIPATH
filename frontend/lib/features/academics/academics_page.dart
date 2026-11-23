import 'package:flutter/material.dart';

/// 학사: 수강 관리와 졸업 요건. Kept for students who use them, below the career pages.
///
/// The tab lives in the workspace so a layout change (desktop ↔ phone) that rebuilds this page
/// keeps the tab the student chose.
class AcademicsPage extends StatelessWidget {
  const AcademicsPage({
    super.key,
    required this.courses,
    required this.graduation,
    required this.tab,
    required this.onTabChanged,
  });

  final Widget courses, graduation;

  /// 0: 수강 관리, 1: 졸업 요건.
  final int tab;
  final ValueChanged<int> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final selected = tab.clamp(0, 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: SegmentedButton<int>(
              key: const ValueKey('academics-tabs'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('수강 관리')),
                ButtonSegment(value: 1, label: Text('졸업 요건')),
              ],
              selected: {selected},
              onSelectionChanged: (value) => onTabChanged(value.first),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: selected,
            children: [
              ExcludeFocus(excluding: selected != 0, child: courses),
              ExcludeFocus(excluding: selected != 1, child: graduation),
            ],
          ),
        ),
      ],
    );
  }
}
