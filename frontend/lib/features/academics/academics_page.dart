import 'package:flutter/material.dart';

import '../../shared/widgets/page_tabs.dart';

/// 학사: 수강 관리와 졸업 요건. Kept for students who use them, below the career pages.
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
  Widget build(BuildContext context) => PageTabs(
    tabsKey: const ValueKey('academics-tabs'),
    labels: const ['수강 관리', '졸업 요건'],
    tab: tab,
    onTabChanged: onTabChanged,
    children: [courses, graduation],
  );
}
