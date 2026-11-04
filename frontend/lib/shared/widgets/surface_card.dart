import 'package:flutter/material.dart';

import '../../app_shell/phone_shell.dart';

class SurfaceCard extends StatelessWidget {
  static const horizontalInsets = 38.0;

  const SurfaceCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: phoneAwarePadding(context),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: child,
  );
}
