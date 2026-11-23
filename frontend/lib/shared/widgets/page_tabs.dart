import 'package:flutter/material.dart';

/// Tabs at the top of one menu page (학사, 자료). The selected tab lives in the workspace so a
/// layout change (desktop ↔ phone) that rebuilds the page keeps the student's choice.
class PageTabs extends StatelessWidget {
  const PageTabs({
    super.key,
    required this.tabsKey,
    required this.labels,
    required this.children,
    required this.tab,
    required this.onTabChanged,
  }) : assert(labels.length == children.length);

  final Key tabsKey;
  final List<String> labels;
  final List<Widget> children;
  final int tab;
  final ValueChanged<int> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final selected = tab.clamp(0, children.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          // Same start line as the page title below; the shell already pads the page.
          padding: const EdgeInsets.only(top: 8, bottom: 12),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: SegmentedButton<int>(
              key: tabsKey,
              showSelectedIcon: false,
              segments: [
                for (var i = 0; i < labels.length; i++)
                  ButtonSegment(value: i, label: Text(labels[i])),
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
              for (var i = 0; i < children.length; i++)
                ExcludeFocus(excluding: selected != i, child: children[i]),
            ],
          ),
        ),
      ],
    );
  }
}
