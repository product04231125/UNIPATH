import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('selection starts below its trigger and restores focus', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    int selected = 2;
    await tester.pumpWidget(
      MaterialApp(
        theme: universityPathTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: SizedBox(
                width: 300,
                child: AnchoredSelectField<int>(
                  key: const Key('select'),
                  value: selected,
                  label: '선택',
                  options: const [
                    SelectOption(1, '첫 번째'),
                    SelectOption(2, '두 번째'),
                  ],
                  onChanged: (value) => selected = value,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final trigger = tester.getRect(find.byKey(const Key('select')));
    await tester.tap(find.byKey(const Key('select')));
    await tester.pumpAndSettle();
    final first = tester.getRect(find.byType(MenuItemButton).first);
    expect(first.left, closeTo(trigger.left, 8));
    expect(first.top, greaterThanOrEqualTo(trigger.bottom));
    await tester.tap(find.text('첫 번째'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(find.byType(MenuItemButton), findsNothing);
    expect(FocusManager.instance.primaryFocus, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNWidgets(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
  });

  testWidgets('selection fits inside the viewport near its lower edge', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(480, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: universityPathTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: SizedBox(
              width: 240,
              child: AnchoredSelectField<int>(
                value: 6,
                label: '선택',
                options: List.generate(7, (i) => SelectOption(i, '$i 항목')),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(AnchoredSelectField<int>));
    await tester.pumpAndSettle();
    for (final element in find.byType(MenuItemButton).evaluate()) {
      final rect = tester.getRect(find.byWidget(element.widget));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(480));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(520));
    }
    expect(tester.takeException(), isNull);
  });
}
