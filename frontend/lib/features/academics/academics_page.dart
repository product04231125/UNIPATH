import 'package:flutter/material.dart';

/// 학사: 수강 관리와 졸업 요건. Kept for students who use them, below the career pages.
class AcademicsPage extends StatefulWidget {
  const AcademicsPage({
    super.key,
    required this.courses,
    required this.graduation,
    this.initialTab = 0,
  });

  final Widget courses, graduation;

  /// 0: 수강 관리, 1: 졸업 요건.
  final int initialTab;

  @override
  State<AcademicsPage> createState() => _AcademicsPageState();
}

class _AcademicsPageState extends State<AcademicsPage> {
  late var _tab = widget.initialTab.clamp(0, 1);

  @override
  void didUpdateWidget(covariant AcademicsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab) {
      _tab = widget.initialTab.clamp(0, 1);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
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
            selected: {_tab},
            onSelectionChanged: (value) => setState(() => _tab = value.first),
          ),
        ),
      ),
      Expanded(
        child: IndexedStack(
          index: _tab,
          children: [
            ExcludeFocus(excluding: _tab != 0, child: widget.courses),
            ExcludeFocus(excluding: _tab != 1, child: widget.graduation),
          ],
        ),
      ),
    ],
  );
}
