import 'package:flutter/material.dart';

/// UI-only student guest preview while an admin AuthIdentity stays active.
class GuestPreviewScope extends InheritedWidget {
  const GuestPreviewScope({
    super.key,
    required this.active,
    this.institutionId,
    required super.child,
  });

  final bool active;
  final String? institutionId;

  static const blockedMessage = '학생 미리보기에서는 개인 자료를 저장하거나 가져올 수 없습니다.';

  static GuestPreviewScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GuestPreviewScope>();

  static bool isActive(BuildContext context) => maybeOf(context)?.active ?? false;

  static String? previewInstitutionId(BuildContext context) =>
      maybeOf(context)?.institutionId;

  static void showBlockedMessage(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(blockedMessage)));
  }

  @override
  bool updateShouldNotify(GuestPreviewScope oldWidget) =>
      active != oldWidget.active || institutionId != oldWidget.institutionId;
}
