import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens the ⋮ menu of the [index]th record row and picks [label]
/// (수정, 삭제, 상세 보기). A delete still needs its confirm dialog tapped.
Future<void> tapRecordAction(
  WidgetTester tester,
  String label, {
  int index = 0,
}) async {
  final menus = find.byIcon(Icons.more_vert);
  await tester.ensureVisible(menus.at(index));
  await tester.pumpAndSettle();
  await tester.tap(menus.at(index));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}
