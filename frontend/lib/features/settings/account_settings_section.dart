import 'package:flutter/material.dart';

import '../../app_shell/phone_shell.dart';

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
      child: Card(
        child: Padding(
          padding: phoneAwarePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('계정·정보', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                '비밀번호 변경과 모든 기기 로그아웃은 별도 보안 화면에서만 입력합니다. 제목표시줄에는 두지 않습니다.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              if (security != null) ...[
                const SizedBox(height: 14),
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
      ),
    );
  }
}
