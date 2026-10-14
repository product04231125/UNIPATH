import 'package:flutter/material.dart';

import '../../shared/widgets/content_scroll_view.dart';

/// Shared navigation for both administrator roles; authorization stays in the
/// workspace/repository. Menu entries are already filtered by the caller.
class AdminShell extends StatelessWidget {
  const AdminShell({
    super.key,
    required this.menus,
    required this.section,
    required this.busy,
    required this.onNavigate,
    required this.onSignedOut,
    required this.child,
  });
  final Map<String, String> menus;
  final String section;
  final bool busy;
  final ValueChanged<String> onNavigate;
  final VoidCallback onSignedOut;
  final Widget child;

  Widget _navigation(BuildContext context) => ContentScrollView(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'UniversityPath',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (final entry in menus.entries)
          Semantics(
            selected: entry.key == section,
            child: ListTile(
              key: ValueKey('admin-menu-${entry.key}'),
              selected: entry.key == section,
              selectedTileColor: Theme.of(context)
                  .colorScheme
                  .secondaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              title: Text(entry.value),
              onTap: busy
                  ? null
                  : () {
                      if (Scaffold.of(context).isDrawerOpen) {
                        Navigator.of(context).pop();
                      }
                      onNavigate(entry.key);
                    },
            ),
          ),
        const Divider(height: 24),
        TextButton.icon(
          onPressed: busy ? null : onSignedOut,
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('로그아웃'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final expanded =
          constraints.maxWidth >= 760 &&
          MediaQuery.textScalerOf(context).scale(14) < 21;
      return Scaffold(
        drawer: expanded
            ? null
            : Drawer(
                child: SafeArea(child: Builder(builder: _navigation)),
              ),
        body: SafeArea(
          child: expanded
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 196,
                      child: Material(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLow,
                        child: Builder(builder: _navigation),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: child),
                  ],
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Builder(
                            builder: (context) => IconButton(
                              tooltip: '관리자 메뉴 열기',
                              icon: const Icon(Icons.menu),
                              onPressed: busy
                                  ? null
                                  : () => Scaffold.of(context).openDrawer(),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              menus[section] ?? '관리자 작업 공간',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: '로그아웃',
                            icon: const Icon(Icons.logout),
                            onPressed: busy ? null : onSignedOut,
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: child),
                  ],
                ),
        ),
      );
    },
  );
}
