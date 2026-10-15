import 'package:flutter/material.dart';

import '../../shared/widgets/content_scroll_view.dart';

/// Caller supplies role-filtered destinations; collapsing never removes access.
class AdminShell extends StatelessWidget {
  const AdminShell({
    super.key,
    required this.menus,
    required this.section,
    required this.busy,
    required this.onNavigate,
    required this.onSignedOut,
    required this.child,
    this.sidebarVisible = true,
  });
  final Map<String, String> menus;
  final String section;
  final bool busy, sidebarVisible;
  final ValueChanged<String> onNavigate;
  final VoidCallback onSignedOut;
  final Widget child;
  IconData _icon(String path) => switch (path) {
    '/admin/overview' => Icons.dashboard_outlined,
    '/admin/schools' => Icons.school_outlined,
    '/admin/curricula' => Icons.menu_book_outlined,
    '/admin/rules' => Icons.checklist_outlined,
    '/admin/documents' => Icons.description_outlined,
    '/admin/history' => Icons.history,
    '/admin/accounts' => Icons.manage_accounts_outlined,
    '/admin/settings' => Icons.settings_outlined,
    _ => Icons.folder_outlined,
  };
  Widget _navigation(BuildContext context, bool compact) => ContentScrollView(
    padding: EdgeInsets.all(compact ? 4 : 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: compact
              ? const Icon(
                  Icons.school_outlined,
                  semanticLabel: 'UniversityPath',
                )
              : Text(
                  'UniversityPath',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
        ),
        for (final entry in menus.entries)
          if (compact)
            Semantics(
              selected: entry.key == section,
              child: IconButton(
                key: ValueKey('admin-menu-${entry.key}'),
                tooltip: entry.value,
                style: IconButton.styleFrom(
                  backgroundColor: entry.key == section
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : null,
                ),
                onPressed: busy ? null : () => onNavigate(entry.key),
                icon: Icon(_icon(entry.key)),
              ),
            )
          else
            Semantics(
              selected: entry.key == section,
              child: ListTile(
                key: ValueKey('admin-menu-${entry.key}'),
                selected: entry.key == section,
                selectedTileColor: Theme.of(context)
                    .colorScheme
                    .secondaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: Text(entry.value),
                onTap: busy ? null : () => onNavigate(entry.key),
              ),
            ),
        const Divider(height: 24),
        if (compact)
          IconButton(
            tooltip: '로그아웃',
            onPressed: busy ? null : onSignedOut,
            icon: const Icon(Icons.logout),
          )
        else
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
      final compact =
          !sidebarVisible ||
          constraints.maxWidth < 760 ||
          MediaQuery.textScalerOf(context).scale(14) >= 21;
      return Scaffold(
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: compact ? 72 : 196,
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: _navigation(context, compact),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: child),
            ],
          ),
        ),
      );
    },
  );
}
