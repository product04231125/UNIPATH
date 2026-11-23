import 'package:flutter/material.dart';

/// Meaning-carrying colors shared by chips, badges and progress so every
/// screen says "ready", "due soon" or "academic" with the same color.
enum AppTone { neutral, accent, info, success, warning, danger }

extension AppToneColors on AppTone {
  /// Foreground color: text, icons and filled bars.
  Color color(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return switch (this) {
      AppTone.neutral => scheme.onSurfaceVariant,
      AppTone.accent => dark ? scheme.primary : _darken(scheme.primary),
      AppTone.info => dark ? const Color(0xff8ec5ff) : const Color(0xff2f5d8a),
      AppTone.success =>
        dark ? const Color(0xff7cdbc5) : const Color(0xff1f7a5c),
      AppTone.warning =>
        dark ? const Color(0xffedcb80) : const Color(0xff9a6412),
      AppTone.danger => scheme.error,
    };
  }

  /// Soft background behind [color].
  Color container(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (this == AppTone.neutral) return scheme.surfaceContainerHighest;
    return Color.alphaBlend(
      color(context)
          .withValues(alpha: scheme.brightness == Brightness.dark ? .18 : .12),
      scheme.surface,
    );
  }
}

/// Accent text on a light surface needs a little more weight than the fill.
Color _darken(Color color) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness - .12).clamp(0, 1)).toColor();
}
