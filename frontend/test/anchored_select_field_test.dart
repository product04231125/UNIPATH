import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';

void main() {
  testWidgets('missing selection keeps field usable after options reload', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnchoredSelectField<String>(
            value: 'removed',
            label: '학교 선택',
            options: const [SelectOption('current', '현재 학교')],
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(AnchoredSelectField<String>));
    await tester.pumpAndSettle();
    expect(find.text('현재 학교'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
