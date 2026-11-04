import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/app_shell/phone_shell.dart';
import 'package:university_path_frontend/shared/widgets/feature_line.dart';

Widget host(Widget child, {bool phone = false}) => MaterialApp(
  theme: universityPathTheme(),
  home: PhoneChromeScope(
    active: phone,
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('FeatureLine.one shows a single text row', (tester) async {
    await tester.pumpWidget(
      host(const FeatureLine.one(text: '개인 기록이 없습니다. 직접 입력해 주세요.')),
    );
    final line = tester.widget<FeatureLine>(find.byType(FeatureLine));
    expect(line.variant, FeatureLineVariant.one);
    expect(find.text('개인 기록이 없습니다. 직접 입력해 주세요.'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FeatureLine),
        matching: find.byType(Column),
      ),
      findsNothing,
    );
  });

  testWidgets('FeatureLine.two shows primary and secondary', (tester) async {
    await tester.pumpWidget(
      host(const FeatureLine.two(primary: '자료구조', secondary: '전공 · 3학점')),
    );
    final line = tester.widget<FeatureLine>(find.byType(FeatureLine));
    expect(line.variant, FeatureLineVariant.two);
    expect(find.text('자료구조'), findsOneWidget);
    expect(find.text('전공 · 3학점'), findsOneWidget);
  });

  testWidgets('FeatureLine.section keeps reload on the trailing side', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      host(
        FeatureLine.section(
          text: '내 수강 과목',
          trailing: FeatureLine.reload(onPressed: () => tapped = true),
        ),
      ),
    );
    expect(find.text('내 수강 과목'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '다시 읽기'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('내 수강 과목')).dx,
      lessThan(tester.getTopLeft(find.text('다시 읽기')).dx),
    );
    await tester.tap(find.text('다시 읽기'));
    expect(tapped, isTrue);
  });
}
