import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    testWidgets('light workspace retains readable text colors on $platform', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const UniversityPathApp(startAuthenticated: true),
      );
      await tester.pumpAndSettle();
      for (final label in [
        '나의 대학생활 경로',
        '이번 주 일정',
        '홈',
        '앞으로 예정된 개인 일정이 없습니다.',
        '학업과 계획 정보',
      ]) {
        final richText = tester.widget<RichText>(
          find
              .byWidgetPredicate(
                (widget) =>
                    widget is RichText && widget.text.toPlainText() == label,
              )
              .first,
        );
        expect(
          richText.text.style?.color,
          isNotNull,
          reason: '$platform: $label must retain a theme color',
        );
        final color = richText.text.style!.color!;
        expect(
          color.computeLuminance(),
          lessThan(0.35),
          reason: '$platform: $label',
        );
      }
      final theme = universityPathTheme();
      expect(theme.textTheme.bodyMedium!.fontFamily, 'Malgun Gothic');
      expect(theme.textTheme.bodyMedium!.color, isNotNull);
      expect(theme.dialogTheme.contentTextStyle!.color, isNotNull);
      expect(theme.listTileTheme.titleTextStyle!.color, isNotNull);
    }, variant: TargetPlatformVariant({platform}));
  }
}
