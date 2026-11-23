import 'package:flutter/material.dart';

import '../../app_shell/phone_shell.dart';

class SurfaceCard extends StatelessWidget {
  static const horizontalInsets = 38.0;

  const SurfaceCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = colors.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: padding ?? phoneAwarePadding(context),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: dark
              ? colors.outlineVariant
              : colors.outlineVariant.withValues(alpha: .55),
        ),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: colors.onSurface.withValues(alpha: .05),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      // List tiles and ink inside the card paint on this layer, not behind
      // the card's background.
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}
