import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_typography.dart';

enum AppPalette {
  cream(
    '크림·브라운',
    false,
    0xfff9f4ef,
    0xff020826,
    0xff716040,
    0xff8c7851,
    0xffeaddcf,
  ),
  blue(
    '밝은 파랑',
    false,
    0xfffffffe,
    0xff094067,
    0xff5f6c7b,
    0xff3da9fc,
    0xff90b4ce,
  ),
  purple(
    '다크 퍼플',
    true,
    0xff16161a,
    0xfffffffe,
    0xff94a1b2,
    0xff7f5af0,
    0xff72757e,
  ),
  orange(
    '다크 오렌지',
    true,
    0xff0f0e17,
    0xfffffffe,
    0xffa7a9be,
    0xffff8906,
    0xfff25f4c,
  );

  const AppPalette(
    this.label,
    this.dark,
    this.background,
    this.foreground,
    this.muted,
    this.accent,
    this.secondary,
  );
  final String label;
  final bool dark;
  final int background, foreground, muted, accent, secondary;
}

const appCornerRadius = 20.0;

ThemeData buildAppTheme(AppPalette palette) {
  final bg = Color(palette.background);
  final fg = Color(palette.foreground);
  final accent = Color(palette.accent);
  final surface = palette.dark
      ? Color.alphaBlend(Colors.white.withValues(alpha: .045), bg)
      : const Color(0xfffffffe);
  final luminance = accent.computeLuminance();
  final primaryText = (luminance + .05) / .05 >= 1.05 / (luminance + .05)
      ? Colors.black
      : Colors.white;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: accent,
        brightness: palette.dark ? Brightness.dark : Brightness.light,
      ).copyWith(
        primary: accent,
        onPrimary: primaryText,
        primaryContainer: Color.alphaBlend(
          accent.withValues(alpha: .15),
          surface,
        ),
        onPrimaryContainer: fg,
        secondary: accent,
        secondaryContainer: Color.alphaBlend(
          accent.withValues(alpha: .12),
          surface,
        ),
        onSecondaryContainer: fg,
        surface: surface,
        onSurface: fg,
        onSurfaceVariant: Color(palette.muted),
        surfaceContainerLow: Color.alphaBlend(
          accent.withValues(alpha: .04),
          bg,
        ),
        surfaceContainerHighest: Color.alphaBlend(
          fg.withValues(alpha: .06),
          surface,
        ),
        outline: Color.alphaBlend(fg.withValues(alpha: .45), surface),
        outlineVariant: Color.alphaBlend(fg.withValues(alpha: .18), surface),
      );
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Pretendard',
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
  );
  final text = AppTypography.apply(base.textTheme);
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(appCornerRadius),
  );
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(appCornerRadius),
        borderSide: BorderSide(color: color, width: width),
      );
  final button = ButtonStyle(
    shape: WidgetStatePropertyAll(shape),
    minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
    textStyle: WidgetStatePropertyAll(text.labelLarge),
  );
  return base.copyWith(
    textTheme: text,
    filledButtonTheme: FilledButtonThemeData(style: button),
    outlinedButtonTheme: OutlinedButtonThemeData(style: button),
    textButtonTheme: TextButtonThemeData(style: button),
    elevatedButtonTheme: ElevatedButtonThemeData(style: button),
    cardTheme: CardThemeData(shape: shape, color: surface, elevation: 0),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      border: border(scheme.outline),
      enabledBorder: border(scheme.outline),
      focusedBorder: border(accent, 2),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, 2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    dialogTheme: DialogThemeData(
      shape: shape,
      alignment: Alignment.center,
      constraints: const BoxConstraints(maxWidth: 640),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: text.bodyMedium,
      subtitleTextStyle: text.bodySmall,
    ),
  );
}

/// Temporary, session-only style comparison. Selecting a palette does not
/// remount the Router, clear forms, change roles, or write user data.
class AppPaletteHost extends StatefulWidget {
  const AppPaletteHost({super.key, required this.builder});
  final Widget Function(ThemeData theme, TransitionBuilder preview) builder;
  @override
  State<AppPaletteHost> createState() => _AppPaletteHostState();
}

class _AppPaletteHostState extends State<AppPaletteHost> {
  AppPalette _palette = AppPalette.cream;
  bool _expanded = false;
  @override
  Widget build(BuildContext context) => widget.builder(
    buildAppTheme(_palette),
    (context, child) => Stack(
      fit: StackFit.expand,
      children: [
        child!,
        if (!kReleaseMode)
          Positioned(
            bottom: 8,
            right: 8,
            child: SafeArea(
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(appCornerRadius),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_expanded)
                      for (final value in AppPalette.values)
                        TextButton.icon(
                          onPressed: () => setState(() {
                            _palette = value;
                            _expanded = false;
                          }),
                          icon: Icon(
                            value == _palette
                                ? Icons.check
                                : Icons.circle_outlined,
                            size: 16,
                          ),
                          label: Text(value.label),
                        ),
                    Semantics(
                      label: '팔레트 비교',
                      button: true,
                      child: IconButton(
                        key: const Key('palette-preview'),
                        icon: Icon(
                          _expanded ? Icons.close : Icons.palette_outlined,
                        ),
                        onPressed: () => setState(() => _expanded = !_expanded),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
