import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/shared/widgets/input_dialog.dart';
import 'package:university_path_frontend/shared/widgets/content_scroll_view.dart';
import 'package:university_path_frontend/features/records/record_menu_page.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/features/schedule/schedule_page.dart';
import 'package:university_path_frontend/features/records/portfolio/portfolio_drafts_page.dart';

Widget host(Widget child, {double scale = 1}) => MaterialApp(
  theme: universityPathTheme(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: child),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final document in [false, true]) {
    testWidgets(
      'portfolio defaults dismiss but text protects document=$document',
      (tester) async {
        await tester.pumpWidget(
          host(PortfolioDraftsPage(isDocument: document)),
        );
        await tester.pumpAndSettle();
        final add = find.widgetWithText(
          FilledButton,
          document ? '지원 문서 초안 추가' : '포트폴리오 구성 추가',
        );
        await tester.tap(add);
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(find.byType(InputDialog), findsNothing);
        await tester.tap(add);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('portfolio-title')),
          '작성 중',
        );
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(find.byType(InputDialog), findsOneWidget);
        await tester.tap(find.text('취소'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('all record input kinds protect content and dismiss whitespace', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final kind in PersonalRecordKind.values) {
      await tester.pumpWidget(
        host(
          RecordMenuPage(
            key: ValueKey(kind),
            kind: kind,
            title: '기록',
            description: '',
            notice: '개인 기록',
            listTitle: '목록',
            fixture: const [],
            guideTitle: '준비',
            guides: const [],
            addLabel: '추가',
            detailLabel: '상세',
            showMockData: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '추가'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(InputDialog), findsNothing, reason: kind.name);
      await tester.tap(find.widgetWithText(FilledButton, '추가'));
      await tester.pumpAndSettle();
      final field = find.byType(TextFormField).first;
      await tester.enterText(field, '작성 중');
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(InputDialog), findsOneWidget, reason: kind.name);
      await tester.enterText(field, '   ');
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(InputDialog), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('editing remains protected after clearing original values', (
    tester,
  ) async {
    final repo = PersonalRecordRepository(PersonalRecordKind.activity);
    await repo.load();
    await repo.save(PersonalRecord(id: 'original', values: {'title': '원본'}));
    await tester.pumpWidget(
      host(
        const RecordMenuPage(
          kind: PersonalRecordKind.activity,
          title: '기록',
          description: '',
          notice: '개인 기록',
          listTitle: '목록',
          fixture: [],
          guideTitle: '준비',
          guides: [],
          addLabel: '추가',
          detailLabel: '상세',
          showMockData: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();
    for (final element in find.byType(TextFormField).evaluate().toList()) {
      (element.widget as TextFormField).controller!.clear();
    }
    await tester.pump();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(InputDialog), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.byType(InputDialog), findsNothing);
    expect(repo.records.single.value('title'), '원본');
    expect(tester.takeException(), isNull);
  });

  testWidgets('schedule defaults are empty but authored title is protected', (
    tester,
  ) async {
    final repo = PlanningRepository();
    addTearDown(repo.dispose);
    await repo.load();
    await tester.pumpWidget(host(SchedulePage(repository: repo)));
    await tester.tap(find.widgetWithText(FilledButton, '일정 추가'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(InputDialog), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, '일정 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '일정');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(InputDialog), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(repo.events, isEmpty);
  });

  for (final size in [
    const Size(1440, 900),
    const Size(900, 768),
    const Size(480, 520),
  ]) {
    testWidgets('input shell margins gutter and fixed actions at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final changes = ValueNotifier(0);
      addTearDown(changes.dispose);
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showInputDialog<void>(
                context: context,
                builder: (context) => InputDialog(
                  changes: changes,
                  hasContent: () => false,
                  title: const Text('등록'),
                  content: Column(
                    children: [
                      for (var i = 0; i < 20; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: TextFormField(
                            key: ValueKey('field-$i'),
                            decoration: InputDecoration(
                              labelText: '긴 입력 항목 $i',
                            ),
                          ),
                        ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('취소'),
                    ),
                    FilledButton(onPressed: () {}, child: const Text('저장')),
                  ],
                ),
              ),
              child: const Text('열기'),
            ),
          ),
          scale: 2,
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      final rect = tester.getRect(
        find.byKey(const Key('input-dialog-surface')),
      );
      expect(rect.width, lessThanOrEqualTo(640));
      expect(rect.left, greaterThanOrEqualTo(24));
      expect(rect.top, greaterThanOrEqualTo(24));
      expect(rect.right, lessThanOrEqualTo(size.width - 24));
      expect(rect.bottom, lessThanOrEqualTo(size.height - 24));
      final body = tester.getRect(find.byType(ContentScrollView));
      expect(
        body.right -
            tester.getRect(find.byKey(const ValueKey('field-0'))).right,
        greaterThanOrEqualTo(16),
      );
      final buttonBefore = tester.getRect(find.text('저장'));
      await tester.drag(find.byType(ContentScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('저장')), buttonBefore);
      expect(find.text('저장').hitTestable(), findsOneWidget);
      expect(find.text('취소').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
    });
  }
}
