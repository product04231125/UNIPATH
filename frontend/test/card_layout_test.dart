import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/record_menu_page.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/features/schedule/schedule_page.dart';
import 'package:university_path_frontend/shared/widgets/equal_height_row.dart';
import 'package:university_path_frontend/shared/widgets/surface_card.dart';

Widget host(Widget child, double scale) => MaterialApp(
  theme: universityPathTheme(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: child),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('card row remeasures when a child changes after layout', (
    tester,
  ) async {
    final text = ValueNotifier('짧은 기록');
    addTearDown(text.dispose);
    await tester.pumpWidget(
      host(
        SingleChildScrollView(
          child: EqualHeightRow(
            children: [
              Expanded(
                child: SurfaceCard(
                  child: ValueListenableBuilder<String>(
                    valueListenable: text,
                    builder: (context, value, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text(value)],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: SurfaceCard(child: Column(children: [Text('준비')])),
              ),
            ],
          ),
        ),
        2,
      ),
    );
    await tester.pumpAndSettle();
    final cards = find.byType(SurfaceCard);
    final before = tester.getSize(cards.first).height;
    text.value = '추가된 긴 기록 ' * 50;
    await tester.pumpAndSettle();
    expect(tester.getSize(cards.first).height, greaterThan(before));
    expect(
      tester.getSize(cards.first).height,
      tester.getSize(cards.last).height,
    );
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    for (final populated in [false, true]) {
      testWidgets('record cards align scale=$scale populated=$populated', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(900, 768));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final kind in PersonalRecordKind.values) {
          if (populated) {
            final repository = PersonalRecordRepository(kind);
            await repository.load();
            await repository.save(
              PersonalRecord(
                id: 'layout-test',
                values: {
                  'title': '긴 개인 기록 제목 ' * 12,
                  'description': '메모 ' * 40,
                },
              ),
            );
          }
          await tester.pumpWidget(
            host(
              RecordMenuPage(
                key: ValueKey(kind),
                kind: kind,
                title: '기록',
                description: '개인 기록',
                notice: '학교 공식 판정 아님',
                listTitle: '등록 기록',
                fixture: const [],
                guideTitle: '준비',
                guides: ['긴 안내 문구 ' * 15],
                addLabel: '추가',
                detailLabel: '상세',
                showMockData: false,
              ),
              scale,
            ),
          );
          await tester.pumpAndSettle();
          final cards = find.byType(SurfaceCard);
          expect(cards, findsNWidgets(2));
          expect(
            tester.getTopLeft(cards.first).dy,
            tester.getTopLeft(cards.last).dy,
          );
          expect(
            tester.getBottomLeft(cards.first).dy,
            closeTo(tester.getBottomLeft(cards.last).dy, .01),
          );
          expect(tester.takeException(), isNull, reason: kind.name);
        }
      });
    }

    testWidgets('schedule cards align and narrow cards stack scale=$scale', (
      tester,
    ) async {
      final repository = PlanningRepository();
      addTearDown(repository.dispose);
      await repository.load();
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final size in [const Size(900, 768), const Size(480, 520)]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          host(SchedulePage(repository: repository), scale),
        );
        await tester.pumpAndSettle();
        final cards = find.byType(Card);
        expect(cards, findsNWidgets(2));
        if (size.width >= 820) {
          expect(find.byType(EqualHeightRow), findsOneWidget);
          expect(
            tester.getBottomLeft(cards.first).dy,
            closeTo(tester.getBottomLeft(cards.last).dy, .01),
          );
        } else {
          expect(find.byType(EqualHeightRow), findsNothing);
          expect(
            tester.getTopLeft(cards.last).dy,
            greaterThan(tester.getBottomLeft(cards.first).dy),
          );
          expect(
            tester.getSize(cards.first).height,
            isNot(closeTo(tester.getSize(cards.last).height, .01)),
          );
        }
        expect(tester.takeException(), isNull);
      }
    });
  }
}
