import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/shared/app_style.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('appearance defaults, persists, recovers unknown values and isolates writes', () async {
    final a = AppAppearance();
    await a.load();
    expect(a.palette, AppPalette.cream);
    await a.select(AppPalette.orange);
    final restored = AppAppearance();
    await restored.load();
    expect(restored.palette, AppPalette.orange);
    final failed = AppAppearance(writer: (_, _) async => false);
    await failed.load();
    await failed.select(AppPalette.blue);
    expect(failed.palette, AppPalette.orange);
    expect(failed.error, isNotNull);
    await failed.load();
    expect(failed.error, isNull);
    SharedPreferences.setMockInitialValues({
      AppAppearance.storageKey: 'purple',
    });
    final legacy = AppAppearance();
    await legacy.load();
    expect(legacy.palette, AppPalette.cream);
    expect(AppPalette.values.length, 3);
    for (final item in [a, restored, failed, legacy]) {
      item.dispose();
    }
  });
  for (final palette in AppPalette.values) {
    test('${palette.name} readable controls, error and title contrast', () {
      final theme = buildAppTheme(palette), c = theme.colorScheme;
      for (final pair in [
        (c.primary, c.onPrimary),
        (c.surface, c.onSurface),
        (c.surface, c.onSurfaceVariant),
        (c.error, c.onError),
        (c.error, c.surfaceContainerHighest),
      ]) {
        expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
      }
      final title = titleBarColor(c);
      expect(
        palette.dark
            ? title.computeLuminance() > c.surface.computeLuminance()
            : title.computeLuminance() < c.surface.computeLuminance(),
        isTrue,
      );
      expect(contrast(title, c.onSurface), greaterThanOrEqualTo(4.5));
      expect(
        (theme.inputDecorationTheme.errorBorder! as OutlineInputBorder)
            .borderSide
            .color,
        c.error,
      );
    });
    testWidgets('${palette.name} compact enlarged login errors', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        AppAppearance.storageKey: palette.name,
      });
      await tester.binding.setSurfaceSize(const Size(480, 520));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        return tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(const UniversityPathApp());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('login-submit')));
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();
      expect(find.text('이메일 주소를 입력해 주세요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'settings selects persistent theme without losing profile edits or navigation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const UniversityPathApp(startAuthenticated: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('설정'));
      await tester.pumpAndSettle();
      final school = find.byType(TextFormField).first;
      await tester.enterText(school, '저장 전 학교');
      final selector = find.byKey(const Key('appearance-palette'));
      await tester.ensureVisible(selector);
      await tester.tap(
        find.descendant(of: selector, matching: find.byType(InkWell)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('다크 오렌지'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(school).controller!.text, '저장 전 학교');
      expect(Theme.of(tester.element(school)).brightness, Brightness.dark);
      expect(
        (await SharedPreferences.getInstance()).getString(
          AppAppearance.storageKey,
        ),
        'orange',
      );
      expect(find.byKey(const Key('palette-preview')), findsNothing);
      expect(find.text('다크 퍼플'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('solid delete retains confirmation and dark readable states', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      AppAppearance.storageKey: 'orange',
    });
    await tester.pumpWidget(const UniversityPathApp());
    await tester.pumpAndSettle();
    final entry = find.byKey(const Key('sample-super-admin-entry'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    await tester.tap(find.text('학교·학과'));
    await tester.pumpAndSettle();
    final button = find
        .ancestor(
          of: find.text('삭제').first,
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        )
        .first;
    final style = tester.widget<ButtonStyleButton>(button).style!;
    final fg = style.foregroundColor!.resolve({})!,
        bg = style.backgroundColor!.resolve({})!;
    expect(bg, const Color(0xffb91c1c));
    expect(contrast(fg, bg), greaterThanOrEqualTo(4.5));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('취소')),
    );
    await tester.pumpAndSettle();
    expect(find.text('합성 대학 A'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
