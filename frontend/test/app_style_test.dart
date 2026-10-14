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
  for (final palette in AppPalette.values) {
    testWidgets('${palette.name} login errors fit compact enlarged text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(480, 520));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        return tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(const UniversityPathApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('palette-preview')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(palette.label));
      await tester.pumpAndSettle();
      final submit = find.byKey(const Key('login-submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('이메일 주소를 입력해 주세요.'), findsOneWidget);
      expect(find.text('비밀번호를 입력해 주세요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('admin draft and workspace survive palette switching', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const UniversityPathApp());
    await tester.pumpAndSettle();
    final entry = find.byKey(const Key('sample-super-admin-entry'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    await tester.tap(find.text('학교·학과'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('학교 등록'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('admin-field-name'));
    await tester.enterText(field, '팔레트 비교 중인 합성 학교');
    for (final palette in AppPalette.values) {
      await tester.tap(find.byKey(const Key('palette-preview')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(palette.label));
      await tester.pumpAndSettle();
      expect(find.text('팔레트 비교 중인 합성 학교'), findsOneWidget);
      expect(find.text('목업에 저장'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
