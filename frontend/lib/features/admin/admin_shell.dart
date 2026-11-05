import 'package:flutter/material.dart';

import '../../app_shell/phone_shell.dart';
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
    '/admin/applications' => Icons.how_to_reg_outlined,
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
      final phone = isPhonePortraitShell(
        Size(constraints.maxWidth, constraints.maxHeight),
      );
      final compact =
          !phone &&
          (!sidebarVisible ||
              constraints.maxWidth < 760 ||
              MediaQuery.textScalerOf(context).scale(14) >= 21);
      final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
      return PhoneChromeScope(
        active: phone,
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            bottom: !phone,
            child: phone
                ? child
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: compact ? 72 : 196,
                        child: Material(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerLow,
                          child: _navigation(context, compact),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: child),
                    ],
                  ),
          ),
          bottomNavigationBar: phone && !keyboardOpen
              ? _AdminPhoneNavigationBar(
                  menus: menus,
                  section: section,
                  busy: busy,
                  onNavigate: onNavigate,
                  onSignedOut: onSignedOut,
                  iconFor: _icon,
                )
              : null,
        ),
      );
    },
  );
}

class _AdminPhoneNavigationBar extends StatelessWidget {
  const _AdminPhoneNavigationBar({
    required this.menus,
    required this.section,
    required this.busy,
    required this.onNavigate,
    required this.onSignedOut,
    required this.iconFor,
  });

  final Map<String, String> menus;
  final String section;
  final bool busy;
  final ValueChanged<String> onNavigate;
  final VoidCallback onSignedOut;
  final IconData Function(String path) iconFor;

  int get _selectedBarIndex {
    final primary = adminPhonePrimaryMenus(menus);
    for (var index = 0; index < primary.length; index++) {
      if (primary[index].key == section) return index;
    }
    return primary.length;
  }

  Future<void> _openMore(BuildContext context) async {
    final more = adminPhoneMoreMenus(menus);
    await showPhoneMoreSheet<void>(
      context: context,
      destinations: [
        for (final entry in more)
          PhoneMoreDestination(
            key: ValueKey('admin-menu-${entry.key}'),
            label: entry.value,
            icon: iconFor(entry.key),
            selected: entry.key == section,
            enabled: !busy,
            onTap: busy
                ? null
                : () {
                    Navigator.pop(context);
                    onNavigate(entry.key);
                  },
          ),
      ],
      actions: [
        TextButton.icon(
          onPressed: busy
              ? null
              : () {
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
    final primary = adminPhonePrimaryMenus(menus);
    return NavigationBar(
      key: const Key('phone-nav-bar'),
      selectedIndex: _selectedBarIndex,
      destinations: [
        for (final entry in primary)
          NavigationDestination(
            icon: Icon(
              iconFor(entry.key),
              key: ValueKey('admin-menu-${entry.key}'),
            ),
            label: entry.value,
          ),
        const NavigationDestination(
          icon: Icon(Icons.more_horiz, key: Key('phone-nav-more')),
          label: '더보기',
        ),
      ],
      onDestinationSelected: (index) {
        if (busy) return;
        if (index == primary.length) {
          _openMore(context);
          return;
        }
        onNavigate(primary[index].key);
      },
    );
  }
}
