import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/shared/widgets/responsive_columns.dart';

void main() {
  testWidgets(
    'columns stack at narrow widths or enlarged text without resetting input',
    (tester) async {
      final controller = TextEditingController(), focus = FocusNode();
      addTearDown(() {
        controller.dispose();
        focus.dispose();
        return tester.binding.setSurfaceSize(null);
      });
      Widget host(bool enabled) => MaterialApp(
        home: Scaffold(
          body: ResponsiveColumns(
            enabled: enabled,
            first: TextField(
              key: const Key('first-field'),
              controller: controller,
              focusNode: focus,
            ),
            second: const TextField(key: Key('second-field')),
          ),
        ),
      );
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      await tester.pumpWidget(host(true));
      final first = find.byKey(const Key('first-field')),
          second = find.byKey(const Key('second-field'));
      await tester.enterText(first, '작성 중인 값');
      final state = tester.state(first);
      expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy);
      expect(
        tester.getTopLeft(second).dx,
        greaterThan(tester.getTopLeft(first).dx),
      );
      for (final size in [const Size(480, 520), const Size(1000, 700)]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpAndSettle();
        expect(identical(tester.state(first), state), isTrue);
        expect(controller.text, '작성 중인 값');
        expect(focus.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(host(false));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(second).dy,
        greaterThan(tester.getTopLeft(first).dy),
      );
      expect(identical(tester.state(first), state), isTrue);
      await tester.pumpWidget(host(true));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(second).dy,
        greaterThan(tester.getTopLeft(first).dy),
      );
      expect(controller.text, '작성 중인 값');
      expect(tester.takeException(), isNull);
    },
  );
}
