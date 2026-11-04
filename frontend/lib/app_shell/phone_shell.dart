import 'package:flutter/material.dart';

/// Phone portrait chrome, not the Windows/narrow-desktop 480×520 window.
///
/// Width under 600 alone is not enough: `480×520` (~1.08) and exact `480×768`
/// (1.6) stay a left icon rail. Phone chrome needs ratio strictly above 1.6.
bool isPhonePortraitShell(Size size) =>
    size.width > 0 && size.width < 600 && size.height / size.width > 1.6;

/// Shells publish this so pages hide title chrome and mock/disclaimer copy together.
class PhoneChromeScope extends InheritedWidget {
  const PhoneChromeScope({
    super.key,
    required this.active,
    required super.child,
  });

  final bool active;

  /// Density follows the published [active] flag only. A missing scope is not
  /// inferred from viewport size.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PhoneChromeScope>()?.active ??
      false;

  @override
  bool updateShouldNotify(PhoneChromeScope oldWidget) =>
      active != oldWidget.active;
}

/// Phone-only density. Do not apply through global ThemeData.
const phoneNavigationBarHeight = 56.0;
const phoneNavigationIconSize = 20.0;
const phoneNavigationLabelSize = 11.0;
const phoneMoreChipWidth = 64.0;
const phoneMoreChipPadding = 8.0;
const phonePageTitleSize = 22.0;
const phonePageHeaderBottomGap = 12.0;
const phoneBodyPadding = 12.0;
const phoneCardPadding = 12.0;
const phoneListGap = 8.0;
const phoneMinTapTarget = 48.0;

double phoneAwareGap(
  BuildContext context, {
  required double wide,
  double phone = phoneListGap,
}) => PhoneChromeScope.of(context) ? phone : wide;

EdgeInsets phoneAwarePadding(BuildContext context, {double wide = 18}) =>
    EdgeInsets.all(PhoneChromeScope.of(context) ? phoneCardPadding : wide);

Widget withPhoneListDensity(BuildContext context, Widget child) {
  final theme = Theme.of(context);
  return Theme(
    data: theme.copyWith(
      listTileTheme: theme.listTileTheme.copyWith(
        minVerticalPadding: phoneListGap,
        minTileHeight: phoneMinTapTarget,
        visualDensity: VisualDensity.compact,
      ),
    ),
    child: child,
  );
}

class PhoneNavigationBar extends StatelessWidget {
  const PhoneNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final List<NavigationDestination> destinations;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        navigationBarTheme: NavigationBarThemeData(
          height: phoneNavigationBarHeight,
          iconTheme: WidgetStateProperty.all(
            const IconThemeData(size: phoneNavigationIconSize),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: phoneNavigationLabelSize,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w600,
            ),
          ),
        ),
      ),
      child: NavigationBar(
        height: phoneNavigationBarHeight,
        selectedIndex: selectedIndex,
        destinations: destinations,
        onDestinationSelected: onDestinationSelected,
      ),
    );
  }
}

const studentPhonePrimaryLabels = ['일정', '졸업 요건', '홈', '자료', '채용공고 분석'];

const adminPhonePrimaryPaths = [
  '/admin/overview',
  '/admin/schools',
  '/admin/curricula',
  '/admin/rules',
];

List<MapEntry<String, String>> adminPhonePrimaryMenus(
  Map<String, String> menus,
) => [
  for (final path in adminPhonePrimaryPaths)
    if (menus.containsKey(path)) MapEntry(path, menus[path]!),
];

List<MapEntry<String, String>> adminPhoneMoreMenus(Map<String, String> menus) =>
    [
      for (final entry in menus.entries)
        if (!adminPhonePrimaryPaths.contains(entry.key)) entry,
    ];

class PhoneMoreDestination {
  const PhoneMoreDestination({
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.enabled = true,
    this.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool selected;
  final bool enabled;
  final Key? key;
}

/// Overflow destinations as a horizontal bottom strip (A B C D E), not a vertical list.
Future<T?> showPhoneMoreSheet<T>({
  required BuildContext context,
  required List<PhoneMoreDestination> destinations,
  List<Widget> actions = const [],
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return SafeArea(
        child: Padding(
          key: const Key('phone-nav-more-sheet'),
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final destination in destinations)
                      _PhoneMoreChip(destination: destination, scheme: scheme),
                  ],
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: actions),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _PhoneMoreChip extends StatelessWidget {
  const _PhoneMoreChip({required this.destination, required this.scheme});

  final PhoneMoreDestination destination;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final selected = destination.selected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: destination.key,
          borderRadius: BorderRadius.circular(16),
          onTap: destination.enabled ? destination.onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: phoneMinTapTarget,
              minWidth: phoneMoreChipWidth,
            ),
            child: SizedBox(
              width: phoneMoreChipWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: phoneMoreChipPadding,
                  horizontal: 4,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      destination.icon,
                      size: phoneNavigationIconSize,
                      color: destination.enabled
                          ? scheme.onSurface
                          : scheme.onSurface.withValues(alpha: 0.38),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      destination.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: phoneNavigationLabelSize,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: destination.enabled
                            ? scheme.onSurface
                            : scheme.onSurface.withValues(alpha: 0.38),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
