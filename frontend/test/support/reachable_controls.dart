import 'package:flutter_test/flutter_test.dart';

/// Scroll each control into view without repeating its business transaction.
Future<void> expectControlsReachable(
  WidgetTester tester,
  Iterable<Finder> controls,
) async {
  final viewport =
      Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
  for (final control in controls) {
    await tester.ensureVisible(control);
    await tester.pumpAndSettle();
    expect(control.hitTestable(), findsOneWidget);
    final rect = tester.getRect(control);
    expect(rect.left, greaterThanOrEqualTo(viewport.left));
    expect(rect.right, lessThanOrEqualTo(viewport.right));
    expect(rect.top, greaterThanOrEqualTo(viewport.top));
    expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(tester.takeException(), isNull);
  }
}
