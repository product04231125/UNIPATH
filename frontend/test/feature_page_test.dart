import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/app_shell/phone_shell.dart';
import 'package:university_path_frontend/shared/widgets/feature_actions.dart';
import 'package:university_path_frontend/shared/widgets/feature_line.dart';
import 'package:university_path_frontend/shared/widgets/feature_page.dart';
import 'package:university_path_frontend/shared/widgets/page_header.dart';
import 'package:university_path_frontend/shared/widgets/surface_card.dart';

Widget host(
  Widget child, {
  Size size = const Size(1440, 900),
  bool phone = false,
}) {
  return MaterialApp(
    theme: universityPathTheme(),
    home: PhoneChromeScope(
      active: phone,
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  testWidgets('FeaturePage has a single header gap and no role banner', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      host(
        const FeaturePage(
          title: '수강 관리',
          description: '학기별 수강 계획과 개인 이수 기록을 정리합니다.',
          body: [
            SurfaceCard(
              child: FeatureLine.one(text: '개인 기록이 없습니다. 직접 입력해 주세요.'),
            ),
          ],
          actions: [FilledButton(onPressed: null, child: Text('수강 과목 추가'))],
        ),
      ),
    );
    expect(find.byType(PageHeader), findsOneWidget);
    expect(find.textContaining('역할'), findsNothing);
    expect(find.textContaining('작업 공간'), findsNothing);
    expect(find.textContaining('공식 판정 아님'), findsNothing);
    final header = tester.getRect(find.byType(PageHeader));
    final card = tester.getRect(find.byType(SurfaceCard));
    expect(card.top, closeTo(header.bottom, 0.5));
    expect(find.byType(FeatureActions), findsOneWidget);
    expect(
      tester.getTopLeft(find.widgetWithText(FilledButton, '수강 과목 추가')).dy -
          tester.getBottomLeft(find.byType(SurfaceCard)).dy,
      16,
    );
  });

  testWidgets('FeaturePage does not add a gap beyond PageHeader bottom', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      host(
        const FeaturePage(
          title: '수강 관리',
          description: '학기별 수강 계획과 개인 이수 기록을 정리합니다.',
          body: [
            SurfaceCard(
              child: FeatureLine.one(text: '개인 기록이 없습니다. 직접 입력해 주세요.'),
            ),
          ],
        ),
        size: const Size(390, 844),
        phone: true,
      ),
    );
    final header = tester.getRect(find.byType(PageHeader));
    final card = tester.getRect(find.byType(SurfaceCard));
    expect(card.top, closeTo(header.bottom, 0.5));
  });

  testWidgets('primary actions use 48 metrics and reload uses 36', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        FeaturePage(
          title: '일정',
          description: '개인 일정을 주간으로 보고 추가합니다.',
          body: [
            FeatureLine.section(
              text: '목록',
              trailing: FeatureLine.reload(onPressed: null),
            ),
          ],
          actions: [
            FilledButton.icon(
              onPressed: null,
              icon: const Icon(Icons.add),
              label: const Text('일정 추가'),
            ),
          ],
        ),
      ),
    );
    expect(tester.getSize(find.byType(FilledButton)).height, 48);
    expect(tester.getSize(find.byType(OutlinedButton)).height, 36);
    final filledStyle = Theme.of(tester.element(find.byType(FilledButton)))
        .filledButtonTheme
        .style!;
    expect(filledStyle.minimumSize?.resolve({})?.height, 48);
    expect(filledStyle.textStyle?.resolve({})?.height, 1.0);
    expect(filledStyle.textStyle?.resolve({})?.fontSize, 14);
    expect(filledStyle.iconSize?.resolve({}), 18);
  });

  testWidgets('FeatureActions uses a 16 gap, 12 on phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      host(
        const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(key: Key('slot-card'), height: 40),
            FeatureActions(
              children: [FilledButton(onPressed: null, child: Text('저장'))],
            ),
          ],
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.widgetWithText(FilledButton, '저장')).dy -
          tester.getBottomLeft(find.byKey(const Key('slot-card'))).dy,
      16,
    );

    await tester.pumpWidget(
      host(
        const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(key: Key('slot-card'), height: 40),
            FeatureActions(
              children: [FilledButton(onPressed: null, child: Text('저장'))],
            ),
          ],
        ),
        phone: true,
      ),
    );
    expect(
      tester.getTopLeft(find.widgetWithText(FilledButton, '저장')).dy -
          tester.getBottomLeft(find.byKey(const Key('slot-card'))).dy,
      12,
    );
  });
}
