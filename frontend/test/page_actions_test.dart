import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/shared/app_style.dart';
import 'package:university_path_frontend/shared/widgets/page_actions.dart';

Color? iconColor(WidgetTester tester, IconData icon) => tester
    .widget<RichText>(
      find.descendant(of: find.byIcon(icon), matching: find.byType(RichText)),
    )
    .text
    .style
    ?.color;

void main() {
  for (final palette in AppPalette.values) {
    testWidgets('header … and + share one color in ${palette.name}', (
      tester,
    ) async {
      for (final enabled in [true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(palette),
            home: Scaffold(
              body: Row(
                children: [
                  PageMoreMenu(enabled: enabled, itemBuilder: (_) => const []),
                  PageAddButton(
                    label: '활동 추가',
                    onPressed: enabled ? () {} : null,
                  ),
                ],
              ),
            ),
          ),
        );
        expect(
          iconColor(tester, Icons.add),
          iconColor(tester, Icons.more_horiz),
        );
        expect(find.byTooltip('활동 추가'), findsOneWidget);
      }
    });
  }
}
