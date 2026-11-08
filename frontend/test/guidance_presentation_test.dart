import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/shared/app_style.dart';
import 'package:university_path_frontend/shared/widgets/external_link_button.dart';
import 'package:university_path_frontend/features/api/academic_guidance_models.dart';
import 'package:university_path_frontend/features/api/rule_program_models.dart';
import 'package:university_path_frontend/features/assistant/academic_guidance_view.dart';
import 'package:university_path_frontend/features/assistant/guidance_sources.dart';
import 'package:university_path_frontend/features/assistant/guidance_menu.dart';

import 'academic_guidance_test.dart' as tree;
import 'rule_program_api_test.dart' as rules;

const originalUrl = 'https://school.example.invalid/calendar';
const source = {'type': 'official_calendar', 'source_url': originalUrl};
Map<String, dynamic> calendar() => {
  ...tree.node('calendar:2026:01'),
  'title': '1월 학사일정',
  'message': '2026년 1월 학사일정 2건입니다.',
  'fetched_at': '2026-11-02T05:58:56.978367+00:00',
  'snapshot_stale': true,
  'warnings': ['수집 시점에 게시된 일정입니다.'],
  'source': source,
  'cards': [
    for (final event in [
      ('신년 하례식', '01. 02(금)'),
      ('복학 신청', '01. 07(수) ~ 01. 10(토)'),
    ])
      {
        'type': 'calendar_event',
        'title': event.$1,
        'date_text': event.$2,
        'body': event.$1 == '복학 신청'
            ? '학사 시스템에서 신청합니다.'
            : '${event.$2} — ${event.$1}',
        'sources': [source],
      },
  ],
  'buttons': [
    {
      'id': 'back',
      'label': '이전 메뉴',
      'action': 'select_node',
      'node_id': 'calendar:2026',
      'availability': 'available',
    },
    {
      'id': 'home',
      'label': '처음으로',
      'action': 'select_node',
      'node_id': 'home',
      'availability': 'available',
    },
  ],
};

void main() {
  testWidgets(
    'sections drill down using received IDs without requesting synthetic nodes',
    (tester) async {
      final selected = <String>[];
      final options = [
        for (final item in [
          ('졸업', 'graduation'),
          ('학사일정', 'calendar'),
          ('등록금', 'tuition'),
        ])
          GuidanceButton(
            id: item.$2,
            label: item.$1,
            action: 'select_node',
            nodeId: item.$2,
            availability: 'available',
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GuidanceMenu(
              nodeId: 'home',
              options: options,
              loading: false,
              onSelect: selected.add,
            ),
          ),
        ),
      );
      expect(find.text('수업·학사'), findsOneWidget);
      expect(find.text('졸업'), findsNothing);
      await tester.tap(find.text('수업·학사'));
      await tester.pumpAndSettle();
      expect(selected, isEmpty);
      await tester.tap(find.text('졸업'));
      expect(selected, ['graduation']);
      await tester.tap(find.text('분야 다시 선택'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('장학·등록'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('등록금'));
      expect(selected, ['graduation', 'tuition']);
    },
  );

  test('source grouping preserves distinct URLs, documents and PDF pages', () {
    final first = const GuidanceSource(
      sourceUrl: originalUrl,
      page: 1,
      documentId: 'a',
    );
    final sources = uniqueGuidanceSources([
      first,
      first,
      const GuidanceSource(sourceUrl: originalUrl, page: 2, documentId: 'a'),
      const GuidanceSource(
        sourceUrl: 'https://school.example.invalid/another',
        page: 1,
        documentId: 'a',
      ),
      const GuidanceSource(sourceUrl: originalUrl, page: 1, documentId: 'b'),
    ]);
    expect(sources, hasLength(4));
  });

  testWidgets(
    'calendar shows one shared source and no duplicate title/date or collection timestamp',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = tree.conversation(
        tree.AcademicGateway()..response = calendar(),
      );
      await c.showGuidance();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AcademicGuidanceView(conversation: c),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ExternalLinkButton), findsOneWidget);
      expect(find.text('신년 하례식'), findsOneWidget);
      expect(find.text('01. 02(금)'), findsOneWidget);
      expect(find.text('01. 02(금) — 신년 하례식'), findsNothing);
      expect(find.textContaining('수집 시각:'), findsNothing);
      expect(find.textContaining('2026-11-02T'), findsNothing);
      expect(find.text('수집 시점에 게시된 일정입니다.'), findsNothing);
      expect(find.text('이전 메뉴'), findsOneWidget);
      expect(find.text('처음으로'), findsOneWidget);
      expect(find.text('학사 시스템에서 신청합니다.'), findsNothing);
      await tester.tap(find.text('복학 신청'));
      await tester.pumpAndSettle();
      expect(find.text('학사 시스템에서 신청합니다.'), findsOneWidget);
      expect(find.text('신년 하례식'), findsOneWidget);
      expect(find.text('01. 02(금)'), findsOneWidget);
      await tester.tap(find.text('자료 정보'));
      await tester.pumpAndSettle();
      expect(find.text('수집 시점에 게시된 일정입니다.'), findsOneWidget);
      expect(find.textContaining('2026-11-02T'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets('school guidance desktop visual matrix', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    tester.view.devicePixelRatio = 1;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.resetDevicePixelRatio);
    final fonts = FontLoader('Pretendard')
      ..addFont(
        rootBundle.load('assets/fonts/pretendard/Pretendard-Regular.otf'),
      );
    await fonts.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final root = tree.conversation(tree.AcademicGateway())
      ..guidance = AcademicGuidance.fromJson({
        ...tree.node('home'),
        'title': '학교 안내',
        'message': '궁금한 항목을 선택해 주세요.',
        'buttons': [
          for (final item in [
            ('졸업', 'graduation'),
            ('학사일정', 'calendar'),
            ('학칙·규정', 'regulations'),
            ('장학금', 'scholarship'),
          ])
            {
              'id': item.$2,
              'label': item.$1,
              'action': 'select_node',
              'node_id': item.$2,
              'availability': 'available',
            },
        ],
      });
    final dates = tree.conversation(tree.AcademicGateway())
      ..guidance = AcademicGuidance.fromJson(calendar());
    final visualCriteria = rules.selection();
    visualCriteria['programs'][0]['rules'][0]['condition']['minimum'] = '130';
    final definition = tree.conversation(tree.AcademicGateway())
      ..guidance = AcademicGuidance.fromJson({
        ...tree.node('credits'),
        'title': '이수학점',
        'buttons': [
          {
            'id': 'graduation',
            'label': '이전 메뉴',
            'action': 'select_node',
            'node_id': 'graduation',
            'availability': 'available',
          },
          {
            'id': 'home',
            'label': '처음으로',
            'action': 'select_node',
            'node_id': 'home',
            'availability': 'available',
          },
        ],
      })
      ..guidanceCriteria = OfficialProgramSelection.fromJson(visualCriteria);
    final output = Directory(
      '../output/pr53-school-guidance-refinement/visuals',
    );
    await tester.runAsync(() => output.create(recursive: true));
    for (final palette in AppPalette.values) {
      for (final scale in [1.0, if (palette == AppPalette.cream) 2.0]) {
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: universityPathTheme(palette: palette),
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(1440, 1000),
                textScaler: TextScaler.linear(scale),
              ),
              child: RepaintBoundary(
                key: boundary,
                child: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final c in [root, dates, definition])
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: SingleChildScrollView(
                                child: AcademicGuidanceView(conversation: c),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final frame =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
          await File('${output.path}/${palette.name}-$scale.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          frame.dispose();
        });
      }
    }
    await tester.pumpWidget(const SizedBox());
    root.dispose();
    dates.dispose();
    definition.dispose();
  }, skip: !const bool.fromEnvironment('GUIDANCE_CAPTURE'));
}
