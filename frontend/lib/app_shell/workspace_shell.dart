import 'package:flutter/material.dart';
import 'package:university_path_frontend/app_shell/phone_shell.dart';
import 'package:university_path_frontend/shared/app_typography.dart';

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
    required this.onSignedOut,
    required this.isAssistantOpen,
    required this.isAssistantManuallyOpened,
    required this.assistantWidth,
    required this.assistantTooltip,
    required this.onOpenAssistant,
    required this.onAssistantWidthChanged,
    required this.pageBuilder,
    required this.assistantBuilder,
    this.minimumContentWidth = 0,
    this.sidebarVisible = true,
    this.integratedTitleBar = false,
    this.assistantButtonFocus,
    this.profileSummary = '학업 정보 미설정',
  });

  final int selectedPage;
  final List<WorkspaceNavigationItem> navigationItems;
  final ValueChanged<int> onPageSelected;
  final VoidCallback onSignedOut;
  final bool isAssistantOpen;
  final bool isAssistantManuallyOpened;
  final double assistantWidth;
  final String assistantTooltip;
  final VoidCallback onOpenAssistant;
  final ValueChanged<double> onAssistantWidthChanged;
  final Widget Function(BuildContext context, WorkspaceShellLayout layout)
  pageBuilder;
  final Widget Function(BuildContext context, double width, bool fullScreen)
  assistantBuilder;
  final double minimumContentWidth;
  final bool sidebarVisible, integratedTitleBar;
  final FocusNode? assistantButtonFocus;
  final String profileSummary;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const fallbackWidth = 480.0;
      final phone = isPhonePortraitShell(
        Size(constraints.maxWidth, constraints.maxHeight),
      );
      final usesScrollFallback = !phone && constraints.maxWidth < fallbackWidth;
      final workspaceWidth = usesScrollFallback
          ? fallbackWidth
          : constraints.maxWidth;
      final showDockedAssistant = workspaceWidth >= 1180 && isAssistantOpen;
      final showAssistantOverlay =
          workspaceWidth < 1180 && isAssistantOpen && isAssistantManuallyOpened;
      final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
      final workspace = _buildWorkspace(
        context,
        workspaceWidth,
        phone: phone,
        showDockedAssistant: showDockedAssistant,
        showAssistantOverlay: showAssistantOverlay,
      );
      return PhoneChromeScope(
        active: phone,
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            bottom: !phone,
            child: usesScrollFallback
                ? _WorkspaceScrollFallback(
                    width: fallbackWidth,
                    child: workspace,
                  )
                : workspace,
          ),
          bottomNavigationBar: phone && !showAssistantOverlay && !keyboardOpen
              ? _StudentPhoneNavigationBar(
                  selectedPage: selectedPage,
                  navigationItems: navigationItems,
                  onPageSelected: onPageSelected,
                  onSignedOut: onSignedOut,
                )
              : null,
        ),
      );
    },
  );

  Widget _buildWorkspace(
    BuildContext context,
    double maxWidth, {
    required bool phone,
    required bool showDockedAssistant,
    required bool showAssistantOverlay,
  }) {
    final overlayWidth = maxWidth;
    final dockWidth = showDockedAssistant ? assistantWidth + 6 : 0.0;
    final compactNavigation =
        phone ||
        !sidebarVisible ||
        maxWidth < 900 ||
        MediaQuery.textScalerOf(context).scale(14) > 18 ||
        maxWidth -
                220 -
                56 -
                dockWidth -
                (showAssistantOverlay ? overlayWidth : 0) <
            minimumContentWidth;
    final layout = WorkspaceShellLayout(
      maxWidth: maxWidth,
      showDockedAssistant: showDockedAssistant,
      showAssistantOverlay: showAssistantOverlay,
      assistantOverlayWidth: overlayWidth,
    );
    final mainPane = _workspaceMain(
      context,
      layout,
      compact: compactNavigation,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: showAssistantOverlay,
          child: ExcludeSemantics(
            excluding: showAssistantOverlay,
            child: Offstage(
              offstage: showAssistantOverlay,
              child: phone
                  ? mainPane
                  : Row(
                      children: [
                        _Sidebar(
                          profileSummary: profileSummary,
                          compact: compactNavigation,
                          selectedPage: selectedPage,
                          navigationItems: navigationItems,
                          onPageSelected: onPageSelected,
                          onSignedOut: onSignedOut,
                        ),
                        Expanded(child: mainPane),
                        if (showDockedAssistant)
                          MouseRegion(
                            cursor: SystemMouseCursors.resizeColumn,
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onHorizontalDragUpdate: (details) =>
                                  onAssistantWidthChanged(details.delta.dx),
                              child: SizedBox(
                                width: 8,
                                child: Center(
                                  child: Container(
                                    width: 1,
                                    height: double.infinity,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (showDockedAssistant)
                          SizedBox(width: assistantWidth),
                      ],
                    ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          bottom: 0,
          width: showAssistantOverlay ? overlayWidth : assistantWidth,
          child: Offstage(
            offstage: !showDockedAssistant && !showAssistantOverlay,
            child: ExcludeFocus(
              excluding: !showDockedAssistant && !showAssistantOverlay,
              child: Material(
                child: assistantBuilder(
                  context,
                  showAssistantOverlay ? overlayWidth : assistantWidth,
                  showAssistantOverlay,
                ),
              ),
            ),
          ),
        ),
        if (!showDockedAssistant && !showAssistantOverlay)
          Positioned(
            right: 18,
            bottom: 18,
            child: FloatingActionButton(
              focusNode: assistantButtonFocus,
              tooltip: assistantTooltip,
              onPressed: onOpenAssistant,
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              child: Icon(
                Icons.chat_bubble_outline,
                semanticLabel: assistantTooltip,
              ),
            ),
          ),
      ],
    );
  }

  Widget _workspaceMain(
    BuildContext context,
    WorkspaceShellLayout layout, {
    required bool compact,
  }) => ClipRect(
    child: Column(
      children: [
        if (!integratedTitleBar)
          SizedBox(
            height: 52,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'UniversityPath',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 16 : 28,
              26,
              compact ? 16 : 28,
              30,
            ),
            child: pageBuilder(context, layout),
          ),
        ),
      ],
    ),
  );
}

class _StudentPhoneNavigationBar extends StatelessWidget {
  const _StudentPhoneNavigationBar({
    required this.selectedPage,
    required this.navigationItems,
    required this.onPageSelected,
    required this.onSignedOut,
  });

  final int selectedPage;
  final List<WorkspaceNavigationItem> navigationItems;
  final ValueChanged<int> onPageSelected;
  final VoidCallback onSignedOut;

  int get _selectedBarIndex {
    for (var index = 0; index < studentPhonePrimaryLabels.length; index++) {
      final pageIndex = navigationItems.indexWhere(
        (item) => item.label == studentPhonePrimaryLabels[index],
      );
      if (pageIndex == selectedPage) return index;
    }
    return studentPhonePrimaryLabels.length;
  }

  Future<void> _openMore(BuildContext context) async {
    final moreItems = [
      for (var index = 0; index < navigationItems.length; index++)
        if (!studentPhonePrimaryLabels.contains(navigationItems[index].label))
          (index: index, item: navigationItems[index]),
    ];
    await showPhoneMoreSheet<void>(
      context: context,
      destinations: [
        for (final entry in moreItems)
          PhoneMoreDestination(
            label: entry.item.label,
            icon: entry.item.icon,
            selected: selectedPage == entry.index,
            onTap: () {
              Navigator.pop(context);
              onPageSelected(entry.index);
            },
          ),
      ],
      actions: [
        TextButton.icon(
          key: const Key('logout-button'),
          onPressed: () {
            Navigator.pop(context);
            onSignedOut();
          },
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('로그아웃'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final destinations = [
      for (final label in studentPhonePrimaryLabels)
        NavigationDestination(
          icon: Icon(
            navigationItems.firstWhere((item) => item.label == label).icon,
            key: Key('phone-nav-$label'),
          ),
          label: label,
        ),
      const NavigationDestination(
        icon: Icon(Icons.more_horiz, key: Key('phone-nav-more')),
        label: '더보기',
      ),
    ];
    return NavigationBar(
      key: const Key('phone-nav-bar'),
      selectedIndex: _selectedBarIndex,
      destinations: destinations,
      onDestinationSelected: (index) {
        if (index == studentPhonePrimaryLabels.length) {
          _openMore(context);
          return;
        }
        final label = studentPhonePrimaryLabels[index];
        final pageIndex = navigationItems.indexWhere(
          (item) => item.label == label,
        );
        if (pageIndex >= 0) onPageSelected(pageIndex);
      },
    );
  }
}

class _WorkspaceScrollFallback extends StatefulWidget {
  const _WorkspaceScrollFallback({required this.width, required this.child});
  final double width;
  final Widget child;

  @override
  State<_WorkspaceScrollFallback> createState() =>
      _WorkspaceScrollFallbackState();
}

class _WorkspaceScrollFallbackState extends State<_WorkspaceScrollFallback> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    key: const Key('workspace-horizontal-scrollbar'),
    controller: _controller,
    thumbVisibility: true,
    interactive: true,
    scrollbarOrientation: ScrollbarOrientation.bottom,
    child: SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      child: SizedBox(width: widget.width, child: widget.child),
    ),
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.profileSummary,
    required this.compact,
    required this.selectedPage,
    required this.navigationItems,
    required this.onPageSelected,
    required this.onSignedOut,
  });

  final bool compact;
  final String profileSummary;
  final int selectedPage;
  final List<WorkspaceNavigationItem> navigationItems;
  final ValueChanged<int> onPageSelected;
  final VoidCallback onSignedOut;

  @override
  Widget build(BuildContext context) => Container(
    width: compact ? 72 : 220,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    padding: const EdgeInsets.all(12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final shouldScroll =
            compact ||
            constraints.maxHeight < 660 ||
            MediaQuery.textScalerOf(context).scale(AppTypography.body) >
                AppTypography.body * 1.2;
        return _buildContent(context, scrollable: shouldScroll);
      },
    ),
  );

  Widget _buildContent(BuildContext context, {required bool scrollable}) =>
      Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 6 : 8,
                      10,
                      compact ? 6 : 8,
                      18,
                    ),
                    child: _Brand(compact: compact),
                  ),
                  for (
                    var index = 0;
                    index < navigationItems.length - 1;
                    index++
                  )
                    _NavigationTile(
                      item: navigationItems[index],
                      selected: selectedPage == index,
                      compact: compact,
                      onPressed: () => onPageSelected(index),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
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
            leading: CircleAvatar(
              radius: 15,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Tooltip(
                message: '내 학업 정보 · $profileSummary',
                child: Icon(
                  Icons.person_outline,
                  color: Theme.of(context).colorScheme.onPrimary,
                  size: 20,
                ),
              ),
            ),
            title: compact
                ? null
                : Text(
                    '내 학업 정보',
                    style: TextStyle(
                      fontSize: AppTypography.body,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
            subtitle: compact
                ? null
                : Text(
                    profileSummary,
                    style: TextStyle(fontSize: AppTypography.caption),
                  ),
          ),
          if (!compact)
            TextButton.icon(
              key: const Key('logout-button'),
              onPressed: onSignedOut,
              icon: Icon(Icons.logout, size: 18),
              label: Text('로그아웃'),
            )
          else
            Tooltip(
              message: '로그아웃',
              child: IconButton(
                key: const Key('logout-button'),
                onPressed: onSignedOut,
                icon: Icon(Icons.logout),
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
      CircleAvatar(
        radius: 18,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(
          Icons.route_outlined,
          color: Theme.of(context).colorScheme.onPrimary,
          size: 18,
        ),
      ),
      if (!compact) const SizedBox(width: 9),
      if (!compact)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'UniversityPath',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTypography.section,
                  fontWeight: FontWeight.w700,
                ),
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
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
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
                Icon(
                  item.icon,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                if (!compact) const SizedBox(width: 10),
                if (!compact)
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: AppTypography.body,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
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
