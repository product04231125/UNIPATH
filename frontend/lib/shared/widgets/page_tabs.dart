import 'package:flutter/material.dart';

import '../../app_shell/phone_shell.dart';
import '../app_typography.dart';

/// Sibling pages of one menu (학사, 자료, 채용공고 분석). The page header of
/// the shown page draws them as large text tabs in place of its title, so the
/// tabs and the title are one row instead of a small switch above a heading.
class PageTabsScope extends InheritedWidget {
  const PageTabsScope({super.key, required this.data, required super.child});

  /// Clears the tabs for nested pages inside a tab's body.
  const PageTabsScope.cleared({super.key, required super.child}) : data = null;

  final PageTabsData? data;

  static PageTabsData? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageTabsScope>()?.data;

  @override
  bool updateShouldNotify(PageTabsScope oldWidget) => oldWidget.data != data;
}

@immutable
class PageTabsData {
  const PageTabsData({
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    this.groupKey,
    this.tabKeys,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  final bool enabled;
  final Key? groupKey;
  final List<Key>? tabKeys;

  @override
  bool operator ==(Object other) =>
      other is PageTabsData &&
      other.selected == selected &&
      other.enabled == enabled &&
      other.groupKey == groupKey &&
      identical(other.onSelected, onSelected) &&
      _same(other.labels, labels) &&
      _same(other.tabKeys, tabKeys);

  @override
  int get hashCode => Object.hash(selected, enabled, groupKey, labels.length);

  static bool _same<T>(List<T>? a, List<T>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Large text tabs drawn by [PageHeader] when a [PageTabsScope] is above it.
class PageTabTitles extends StatelessWidget {
  const PageTabTitles({super.key, required this.data});

  final PageTabsData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final phone = PhoneChromeScope.of(context);
    final base = theme.textTheme.headlineMedium?.merge(
      phone
          ? AppTypography.pageStyle.copyWith(fontSize: phonePageTitleSize)
          : AppTypography.pageStyle,
    );
    return SingleChildScrollView(
      key: data.groupKey,
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < data.labels.length; i++) ...[
            if (i > 0) SizedBox(width: phone ? 16 : 28),
            _tab(context, i, base, colors),
          ],
        ],
      ),
    );
  }

  Widget _tab(
    BuildContext context,
    int i,
    TextStyle? base,
    ColorScheme colors,
  ) {
    final selected = i == data.selected;
    return Semantics(
      header: selected,
      selected: selected,
      button: true,
      child: InkWell(
        key: data.tabKeys?[i],
        borderRadius: BorderRadius.circular(8),
        onTap: selected || !data.enabled ? null : () => data.onSelected(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.labels[i],
                style: base?.copyWith(
                  color: selected
                      ? colors.onSurface
                      : colors.onSurfaceVariant.withValues(
                          alpha: data.enabled ? .62 : .38,
                        ),
                ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 3,
                width: selected ? 28 : 0,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tabs of one menu page (학사, 자료). The selected tab lives in the workspace
/// so a layout change (desktop ↔ phone) that rebuilds the page keeps it.
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
    return PageTabsScope(
      data: PageTabsData(
        labels: labels,
        selected: selected,
        onSelected: onTabChanged,
        groupKey: tabsKey,
      ),
      child: IndexedStack(
        index: selected,
        children: [
          for (var i = 0; i < children.length; i++)
            ExcludeFocus(excluding: selected != i, child: children[i]),
        ],
      ),
    );
  }
}
