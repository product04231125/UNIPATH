import 'package:shared_preferences/shared_preferences.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../chat_window.dart' as native;

import 'app_typography.dart';

/// Local appearance preference, separate from academic and account data.
class AppAppearance extends ChangeNotifier {
  AppAppearance({this.writer});
  static const storageKey = 'university_path.appearance.v1';
  final Future<bool> Function(String, String)? writer;
  AppPalette palette = AppPalette.cream;
  bool loading = true, saving = false;
  String? error;
  SharedPreferences? _preferences;
  bool _disposed = false;
  void receive(String value) {
    final next = AppPalette.values.where((p) => p.name == value).firstOrNull;
    if (next == null || _disposed) return;
    palette = next;
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    error = null;
    _changed();
    try {
      _preferences ??= await SharedPreferences.getInstance();
      await _preferences!.reload();
      final raw = _preferences!.getString(storageKey);
      palette =
          AppPalette.values.where((p) => p.name == raw).firstOrNull ??
          AppPalette.cream;
    } catch (_) {
      error = '화면 설정을 읽지 못했습니다. 다시 읽어 주세요.';
    }
    loading = false;
    _changed();
  }

  Future<void> select(AppPalette value) async {
    if (loading || saving || error != null) return;
    saving = true;
    _changed();
    try {
      final saved =
          await (writer?.call(storageKey, value.name) ??
              _preferences!.setString(storageKey, value.name));
      if (!saved) throw StateError('Appearance write failed');
      palette = value;
      unawaited(native.publishAppearance(value.name).catchError((Object _) {}));
    } catch (_) {
      error = '테마를 저장하지 못했습니다. 기존 테마를 유지합니다.';
    } finally {
      saving = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class AppearanceScope extends InheritedNotifier<AppAppearance> {
  const AppearanceScope({
    super.key,
    required AppAppearance appearance,
    required super.child,
  }) : super(notifier: appearance);
  static AppAppearance? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>()?.notifier;
}

/// Theme updates retain the router, forms and active session.
class AppPaletteHost extends StatefulWidget {
  const AppPaletteHost({super.key, required this.builder});
  final Widget Function(ThemeData theme, TransitionBuilder wrapper) builder;
  @override
  State<AppPaletteHost> createState() => _AppPaletteHostState();
}

class _AppPaletteHostState extends State<AppPaletteHost> {
  final _appearance = AppAppearance();
  StreamSubscription<String>? _subscription;
  @override
  void initState() {
    super.initState();
    _appearance.load();
    _subscription = native.appearanceChanges().listen(_appearance.receive);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _appearance,
    builder: (context, _) => widget.builder(
      buildAppTheme(_appearance.palette),
      (context, child) =>
          AppearanceScope(appearance: _appearance, child: child!),
    ),
  );
}

Color titleBarColor(ColorScheme colors) => Color.alphaBlend(
  colors.onSurface.withValues(
    alpha: colors.brightness == Brightness.dark ? .12 : .09,
  ),
  colors.surface,
);

ButtonStyle destructiveButtonStyle(BuildContext context) {
  const fill = Color(0xffb91c1c);
  return FilledButton.styleFrom(
    backgroundColor: fill,
    foregroundColor: Colors.white,
  ).copyWith(
    overlayColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? Colors.transparent
          : Colors.black.withValues(
              alpha: states.contains(WidgetState.pressed)
                  ? .20
                  : states.contains(WidgetState.hovered)
                  ? .12
                  : 0,
            ),
    ),
    side: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? BorderSide(color: Theme.of(context).colorScheme.onSurface, width: 2)
          : const BorderSide(color: fill),
    ),
  );
}

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
        error: palette.dark ? const Color(0xffff6262) : const Color(0xffb42318),
        onError: palette.dark ? Colors.black : Colors.white,
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
          (palette.dark ? fg : Color(palette.secondary)).withValues(
            alpha: palette.dark ? .06 : .16,
          ),
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
    elevation: const WidgetStatePropertyAll(0),
    side: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? BorderSide(color: fg, width: 2)
          : null,
    ),
    overlayColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? Colors.transparent
          : states.contains(WidgetState.pressed)
          ? fg.withValues(alpha: .22)
          : states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)
          ? fg.withValues(alpha: .14)
          : Colors.transparent,
    ),
  );
  return base.copyWith(
    textTheme: text,
    filledButtonTheme: FilledButtonThemeData(
      style: button.copyWith(
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? Colors.transparent
              : states.contains(WidgetState.pressed)
              ? (primaryText == Colors.black ? Colors.white : Colors.black)
                    .withValues(alpha: .30)
              : states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)
              ? (primaryText == Colors.black ? Colors.white : Colors.black)
                    .withValues(alpha: .22)
              : Colors.transparent,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: button.copyWith(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? null : fg,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: button.copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? null
              : scheme.surfaceContainerHighest,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? null : fg,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: button.copyWith(
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: button),
    cardTheme: CardThemeData(shape: shape, color: surface, elevation: 0),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      floatingLabelStyle: WidgetStateTextStyle.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.error) ? scheme.error : fg,
        ),
      ),
      border: border(scheme.outline),
      enabledBorder: border(scheme.outline),
      disabledBorder: border(scheme.outlineVariant),
      focusedBorder: border(accent, 2),
      errorStyle: TextStyle(color: scheme.error),
      errorBorder: border(scheme.error, 1.5),
      focusedErrorBorder: border(scheme.error, 2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
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
