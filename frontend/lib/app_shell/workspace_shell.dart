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
          final showDockedAssistant =
              constraints.maxWidth >= 1180 && isAssistantOpen;
          final showAssistantOverlay =
              constraints.maxWidth < 1180 &&
              isAssistantOpen &&
              isAssistantManuallyOpened;
          final overlayWidth = constraints.maxWidth < 480
              ? constraints.maxWidth
              : 360.0;
          final layout = WorkspaceShellLayout(
            maxWidth: constraints.maxWidth,
            showDockedAssistant: showDockedAssistant,
            showAssistantOverlay: showAssistantOverlay,
            assistantOverlayWidth: overlayWidth,
          );
          return Stack(
            children: [
              Row(
                children: [
                  _Sidebar(
                    selectedPage: selectedPage,
                    navigationItems: navigationItems,
                    onPageSelected: onPageSelected,
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
                                constraints.maxWidth < 900 ? 16 : 28,
                                26,
                                constraints.maxWidth < 900 ? 16 : 28,
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
                        child: Container(
                          width: 6,
                          color: const Color(0xffd8e1e7),
                        ),
                      ),
                    ),
                  if (showDockedAssistant)
                    assistantBuilder(context, assistantWidth),
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
        },
      ),
    ),
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selectedPage,
    required this.navigationItems,
    required this.onPageSelected,
  });

  final int selectedPage;
  final List<WorkspaceNavigationItem> navigationItems;
  final ValueChanged<int> onPageSelected;

  @override
  Widget build(BuildContext context) => Container(
    width: 220,
    color: const Color(0xfff2f5f6),
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 10, 8, 18),
          child: _Brand(),
        ),
        for (var index = 0; index < navigationItems.length - 1; index++)
          _NavigationTile(
            item: navigationItems[index],
            selected: selectedPage == index,
            onPressed: () => onPageSelected(index),
          ),
        const Spacer(),
        _NavigationTile(
          item: navigationItems.last,
          selected: selectedPage == navigationItems.length - 1,
          onPressed: () => onPageSelected(navigationItems.length - 1),
        ),
        const Divider(),
        const ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 15,
            backgroundColor: Color(0xff19344d),
            child: Text(
              '정',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          title: Text(
            '정민서',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          subtitle: Text('2024학번 · 컴퓨터공학과', style: TextStyle(fontSize: 10)),
        ),
      ],
    ),
  );
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const CircleAvatar(
        radius: 18,
        backgroundColor: Color(0xff19344d),
        child: Icon(Icons.route_outlined, color: Colors.white, size: 18),
      ),
      const SizedBox(width: 9),
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
    required this.onPressed,
  });

  final WorkspaceNavigationItem item;
  final bool selected;
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(item.icon, size: 18, color: const Color(0xff25465f)),
              const SizedBox(width: 10),
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
  );
}
