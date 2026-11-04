import 'package:flutter/material.dart';

import '../../app_shell/phone_shell.dart';
import '../../shared/widgets/feature_line.dart';
import '../../shared/widgets/surface_card.dart';

/// Provides account-security and school-application callbacks to settings pages.
class AccountSettingsActions extends InheritedWidget {
  const AccountSettingsActions({
    super.key,
    required super.child,
    this.onAccountSecurity,
    this.onApplications,
    this.applicationLabel = '학교 관리 권한·신청 이력',
  });

  final VoidCallback? onAccountSecurity;
  final VoidCallback? onApplications;
  final String applicationLabel;

  static AccountSettingsActions? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountSettingsActions>();

  @override
  bool updateShouldNotify(AccountSettingsActions oldWidget) =>
      onAccountSecurity != oldWidget.onAccountSecurity ||
      onApplications != oldWidget.onApplications ||
      applicationLabel != oldWidget.applicationLabel;
}

/// Settings 계정·정보 rows that open the existing security and application dialogs.
class AccountSettingsSection extends StatelessWidget {
  const AccountSettingsSection({
    super.key,
    this.onAccountSecurity,
    this.onApplications,
    this.applicationLabel,
  });

  final VoidCallback? onAccountSecurity;
  final VoidCallback? onApplications;
  final String? applicationLabel;

  @override
  Widget build(BuildContext context) {
    final inherited = AccountSettingsActions.maybeOf(context);
    final security = onAccountSecurity ?? inherited?.onAccountSecurity;
    final applications = onApplications ?? inherited?.onApplications;
    final label =
        applicationLabel ?? inherited?.applicationLabel ?? '학교 관리 권한·신청 이력';
    if (security == null && applications == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(top: phoneAwareGap(context, wide: 24)),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FeatureLine.section(text: '계정·정보'),
            if (security != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('settings-account-security'),
                  onPressed: security,
                  icon: const Icon(Icons.manage_accounts_outlined, size: 18),
                  label: const Text('계정 보안'),
                ),
              ),
            ],
            if (applications != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('settings-school-applications'),
                  onPressed: applications,
                  icon: const Icon(Icons.school_outlined, size: 18),
                  label: Text(label),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
