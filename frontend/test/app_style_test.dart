import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/shared/app_style.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
}

void main() {
  for (final palette in AppPalette.values) {
    test('${palette.name} preserves readable text and round controls', () {
      final theme = buildAppTheme(palette), c = theme.colorScheme;
      expect(contrast(c.primary, c.onPrimary), greaterThanOrEqualTo(4.5));
      expect(contrast(c.surface, c.onSurface), greaterThanOrEqualTo(4.5));
      expect(
        contrast(c.surface, c.onSurfaceVariant),
        greaterThanOrEqualTo(4.5),
      );
      final border =
          theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder;
      expect(border.borderRadius, BorderRadius.circular(20));
      expect(
        theme.brightness,
        palette.dark ? Brightness.dark : Brightness.light,
      );
    });
  }
  testWidgets('palette preview retains entered text', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      AppPaletteHost(
        builder: (theme, preview) => MaterialApp(
          theme: theme,
          builder: preview,
          home: Scaffold(body: TextField(controller: controller)),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '작성 중인 값');
    await tester.tap(find.byKey(const Key('palette-preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다크 퍼플'));
    await tester.pumpAndSettle();
    expect(controller.text, '작성 중인 값');
    expect(
      Theme.of(tester.element(find.byType(TextField))).brightness,
      Brightness.dark,
    );
    expect(tester.takeException(), isNull);
  });
}
