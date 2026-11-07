import 'package:flutter/material.dart';

import 'planning_repository.dart';

/// What a screen needs from the saved academic [PlanningProfile].
enum PlanningProfileNeed {
  /// School name, department, and admission year ([PlanningProfile.isConfigured]).
  configured,

  /// Catalog school UUID ([PlanningProfile.hasCatalogSchool]).
  catalogSchool,
}

/// Whether [profile] satisfies [need]. A missing profile is never ready.
bool isPlanningProfileReady(
  PlanningProfile? profile,
  PlanningProfileNeed need,
) {
  if (profile == null) return false;
  return switch (need) {
    PlanningProfileNeed.configured => profile.isConfigured,
    PlanningProfileNeed.catalogSchool => profile.hasCatalogSchool,
  };
}

/// Shared Settings CTA copy. Incomplete profiles register; ready ones edit.
String planningProfileSettingsCtaLabel({required bool ready}) =>
    ready ? '설정에서 학업 프로필 수정' : '설정에서 학업 프로필 등록';

String planningProfileSettingsMessage({required bool ready}) => ready
    ? '학업 프로필 변경은 설정에서만 할 수 있습니다.'
    : '설정에서 학업 프로필을 등록하면 이 화면에 자동으로 사용합니다.';

final planningProfileSettingsCtaKey = const Key(
  'planning-profile-settings-cta',
);

/// Consistent CTA that sends the user to Settings to register or edit the
/// academic profile. Document search, issued PDF, official audit, and chat
/// reuse this instead of each inventing copy or navigation.
class PlanningProfileSettingsCta extends StatelessWidget {
  const PlanningProfileSettingsCta({
    super.key,
    required this.onOpenSettings,
    required this.need,
    this.profile,
  });

  /// Open the existing settings tab. Wire with
  /// `() => AppLocation.openSettings(onPageChanged)` from Workspace /
  /// AppNavigation, or HomePage's existing `onOpenSettings`.
  final VoidCallback onOpenSettings;
  final PlanningProfileNeed need;
  final PlanningProfile? profile;

  @override
  Widget build(BuildContext context) {
    final ready = isPlanningProfileReady(profile, need);
    final label = planningProfileSettingsCtaLabel(ready: ready);
    final message = planningProfileSettingsMessage(ready: ready);
    final icon = Icon(Icons.settings_outlined, size: 18);
    final child = Text(label);
    return Column(
      key: planningProfileSettingsCtaKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        const SizedBox(height: 12),
        ready
            ? OutlinedButton.icon(
                onPressed: onOpenSettings,
                icon: icon,
                label: child,
              )
            : FilledButton.icon(
                onPressed: onOpenSettings,
                icon: icon,
                label: child,
              ),
      ],
    );
  }
}
