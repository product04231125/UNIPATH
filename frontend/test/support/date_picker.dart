import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Chooses [day] in a [DatePickerFormField] the way a person can: open the calendar,
/// switch it to typing, enter the date in the dialog's own format and confirm. Works
/// with English test apps and the Korean app alike.
Future<void> pickDate(WidgetTester tester, Finder field, DateTime day) async {
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  final dialog = find.byType(DatePickerDialog);
  final words = MaterialLocalizations.of(tester.element(dialog));
  await tester.tap(
    find.descendant(
      of: dialog,
      matching: find.byWidgetPredicate(
        (w) =>
            w is Icon &&
            (w.icon == Icons.edit_outlined || w.icon == Icons.edit),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(of: dialog, matching: find.byType(TextField)),
    words.formatCompactDate(day),
  );
  await tester.tap(
    find.descendant(of: dialog, matching: find.text(words.okButtonLabel)),
  );
  await tester.pumpAndSettle();
}
