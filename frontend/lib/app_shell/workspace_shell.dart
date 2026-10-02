import 'package:flutter/material.dart';

class WorkspaceNavigationItem {
  const WorkspaceNavigationItem({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class WorkspaceShellLayout {
  const WorkspaceShellLayout({
    required this.maxWidth,
    required this.showDockedAssistant,
    required this.showAssistantOverlay,
    required this.assistantOverlayWidth,
  });

  final double maxWidth;
  final bool showDockedAssistant;
  final bool showAssistantOverlay;
  final double assistantOverlayWidth;
}

/// Owns the common workspace frame. Feature pages and the assistant are supplied
/// by their modules so navigation and responsive layout do not live in a page.
class WorkspaceShell extends StatelessWidget {
  const WorkspaceShell({
    super.key,
    required this.selectedPage,
    required this.navigationItems,
    required this.onPageSelected,
    required this.showMockData,
    required this.onMockDataChanged,
    required this.onSignedOut,
    required this.isAssistantOpen,
    required this.isAssistantManuallyOpened,
    required this.assistantWidth,
    required this.assistantTooltip,
    required this.onOpenAssistant,
    required this.onAssistantWidthChanged,
    required this.pageBuilder,
    required this.assistantBuilder,
  });

  final int selectedPage;
  final List<WorkspaceNavigationItem> navigationItems;
  final ValueChanged<int> onPageSelected;
  final bool showMockData;
  final ValueChanged<bool> onMockDataChanged;
  final VoidCallback onSignedOut;
  final bool isAssistantOpen;
  final bool isAssistantManuallyOpened;
  final double assistantWidth;
  final String assistantTooltip;
  final VoidCallback onOpenAssistant;
  final ValueChanged<double> onAssistantWidthChanged;
  final Widget Function(BuildContext context, WorkspaceShellLayout layout)
  pageBuilder;
  final Widget Function(BuildContext context, double width) assistantBuilder;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          const fallbackWidth = 480.0;
          final usesScrollFallback = constraints.maxWidth < fallbackWidth;
          final workspaceWidth = usesScrollFallback
              ? fallbackWidth
              : constraints.maxWidth;
          final workspace = _buildWorkspace(context, workspaceWidth);
          return usesScrollFallback
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(width: fallbackWidth, child: workspace),
                )
              : workspace;
        },
      ),
    ),
  );

  Widget _buildWorkspace(BuildContext context, double maxWidth) {
    final showDockedAssistant = maxWidth >= 1180 && isAssistantOpen;
    final showAssistantOverlay =
        maxWidth < 1180 && isAssistantOpen && isAssistantManuallyOpened;
    final overlayWidth = maxWidth < 480 ? maxWidth : 360.0;
    final layout = WorkspaceShellLayout(
      maxWidth: maxWidth,
      showDockedAssistant: showDockedAssistant,
      showAssistantOverlay: showAssistantOverlay,
      assistantOverlayWidth: overlayWidth,
    );
    return Stack(
      children: [
        Row(
          children: [
            _Sidebar(
              compact: maxWidth < 900,
              selectedPage: selectedPage,
              navigationItems: navigationItems,
              onPageSelected: onPageSelected,
              showMockData: showMockData,
              onMockDataChanged: onMockDataChanged,
              onSignedOut: onSignedOut,
            ),
            Expanded(
              child: ClipRect(
                child: Column(
                  children: [
                    const SizedBox(
                      height: 52,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'UniversityPath  화면 목업',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xff27445d),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          maxWidth < 900 ? 16 : 28,
                          26,
                          maxWidth < 900 ? 16 : 28,
                          30,
                        ),
                        child: pageBuilder(context, layout),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (showDockedAssistant)
              MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: (details) =>
                      onAssistantWidthChanged(details.delta.dx),
                  child: Container(width: 6, color: const Color(0xffd8e1e7)),
                ),
              ),
            if (showDockedAssistant) assistantBuilder(context, assistantWidth),
          ],
        ),
        if (showAssistantOverlay)
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: overlayWidth,
            child: Material(
              elevation: 18,
              child: assistantBuilder(context, overlayWidth),
            ),
          ),
        if (!showDockedAssistant && !showAssistantOverlay)
          Positioned(
            right: 18,
            bottom: 18,
            child: Tooltip(
              message: assistantTooltip,
              child: FloatingActionButton(
                onPressed: onOpenAssistant,
                backgroundColor: const Color(0xff193f59),
                foregroundColor: Colors.white,
                child: const Icon(Icons.chat_bubble_outline),
              ),
            ),
          ),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.compact,
    required this.selectedPage,
    required this.navigationItems,
    required this.onPageSelected,
    required this.showMockData,
    required this.onMockDataChanged,
    required this.onSignedOut,
  });

  final bool compact;
  final int selectedPage;
  final List<WorkspaceNavigationItem> navigationItems;
  final ValueChanged<int> onPageSelected;
  final bool showMockData;
  final ValueChanged<bool> onMockDataChanged;
  final VoidCallback onSignedOut;

  @override
  Widget build(BuildContext context) => Container(
    width: compact ? 72 : 220,
    color: const Color(0xfff2f5f6),
    padding: const EdgeInsets.all(12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final shouldScroll = compact || constraints.maxHeight < 660;
        final content = _buildContent(scrollable: shouldScroll);
        return shouldScroll ? SingleChildScrollView(child: content) : content;
      },
    ),
  );

  Widget _buildContent({required bool scrollable}) => Column(
    mainAxisSize: scrollable ? MainAxisSize.min : MainAxisSize.max,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: EdgeInsets.fromLTRB(compact ? 6 : 8, 10, compact ? 6 : 8, 18),
        child: _Brand(compact: compact),
      ),
      for (var index = 0; index < navigationItems.length - 1; index++)
        _NavigationTile(
          item: navigationItems[index],
          selected: selectedPage == index,
          compact: compact,
          onPressed: () => onPageSelected(index),
        ),
      if (scrollable) const SizedBox(height: 24) else const Spacer(),
      if (!compact)
        Material(
          color: Colors.transparent,
          child: SwitchListTile.adaptive(
            key: const Key('mock-data-toggle'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            dense: true,
            title: const Text(
              '목업용',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            subtitle: const Text('예시 데이터 표시', style: TextStyle(fontSize: 10)),
            value: showMockData,
            onChanged: onMockDataChanged,
          ),
        ),
      if (!compact) const SizedBox(height: 4),
      _NavigationTile(
        item: navigationItems.last,
        selected: selectedPage == navigationItems.length - 1,
        compact: compact,
        onPressed: () => onPageSelected(navigationItems.length - 1),
      ),
      const Divider(),
      ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8),
        dense: true,
        leading: const CircleAvatar(
          radius: 15,
          backgroundColor: Color(0xff19344d),
          child: Text('정', style: TextStyle(color: Colors.white, fontSize: 12)),
        ),
        title: compact
            ? null
            : const Text(
                '정민서',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
        subtitle: compact
            ? null
            : const Text('2024학번 · 컴퓨터공학과', style: TextStyle(fontSize: 10)),
      ),
      if (!compact)
        TextButton.icon(
          key: const Key('logout-button'),
          onPressed: onSignedOut,
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('로그아웃'),
        )
      else
        Tooltip(
          message: '로그아웃',
          child: IconButton(
            key: const Key('logout-button'),
            onPressed: onSignedOut,
            icon: const Icon(Icons.logout),
          ),
        ),
    ],
  );
}

class _Brand extends StatelessWidget {
  const _Brand({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const CircleAvatar(
        radius: 18,
        backgroundColor: Color(0xff19344d),
        child: Icon(Icons.route_outlined, color: Colors.white, size: 18),
      ),
      if (!compact) const SizedBox(width: 9),
      if (!compact)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'UniversityPath',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '화면 목업',
                style: TextStyle(fontSize: 11, color: Color(0xff708192)),
              ),
            ],
          ),
        ),
    ],
  );
}

class _NavigationTile extends StatelessWidget {
  const _NavigationTile({
    required this.item,
    required this.selected,
    required this.compact,
    required this.onPressed,
  });

  final WorkspaceNavigationItem item;
  final bool selected;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Material(
      color: selected ? const Color(0xffdcebf1) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Tooltip(
          message: compact ? item.label : '',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(item.icon, size: 18, color: const Color(0xff25465f)),
                if (!compact) const SizedBox(width: 10),
                if (!compact)
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
