import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/features/api/academic_guidance_models.dart';
import 'package:university_path_frontend/features/assistant/assistant_panel.dart';
import 'package:university_path_frontend/features/assistant/assistant_conversation.dart';
import 'package:university_path_frontend/features/assistant/academic_guidance_view.dart';
import 'package:university_path_frontend/features/home/home_page.dart';
import 'package:university_path_frontend/shared/app_style.dart';

import 'guidance_criteria_test.dart' as criteria;

// Synthetic responses only; these are not a school's actual requirements.
void main() {
  testWidgets('published cards preserve the surrounding full workspace', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    tester.view.devicePixelRatio = 1;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.resetDevicePixelRatio);
    await (FontLoader('Pretendard')..addFont(
          rootBundle.load('assets/fonts/pretendard/Pretendard-Regular.otf'),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: const UniversityPathApp(startAuthenticated: true),
      ),
    );
    await tester.pumpAndSettle();
    final home = find.byType(HomePage);
    final homeElement = tester.element(home);
    final closedBounds = tester.getRect(home);
    Future<void> capture(String name) async {
      if (!const bool.fromEnvironment('GUIDANCE_CAPTURE')) return;
      await tester.runAsync(() async {
        final output = Directory('../output/guidance-published-cards');
        await output.create(recursive: true);
        final frame =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
        await File('${output.path}/workspace_$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        frame.dispose();
      });
    }

    await capture('closed');
    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pumpAndSettle();
    final c = tester
        .widget<AssistantPanel>(find.byType(AssistantPanel))
        .conversation;
    final base = <String, dynamic>{
      'schema_version': 'academic-click-v3',
      'node_id': 'credits',
      'title': '이수학점',
      'state': 'ready',
      'reason': 'general_criteria',
      'message': '학교 게시 기준 안내 · 합성 응답',
      'warnings': [],
      'buttons': [
        {
          'id': 'home',
          'label': '처음으로',
          'action': 'select_node',
          'node_id': 'home',
          'availability': 'available',
        },
      ],
      'cards': [],
    };
    c.guidance = AcademicGuidance.fromJson(base);
    c.guidanceOpen = true;
    c.guidanceError = null;
    c.setMode(AssistantMode.school);
    await tester.pumpAndSettle();
    final dockedBounds = tester.getRect(home);
    expect(identical(tester.element(home), homeElement), isTrue);
    await capture('empty');
    c.guidance = AcademicGuidance.fromJson({
      ...base,
      'cards': [
        {
          'type': 'reference_table',
          'title': '합성 졸업 학점표',
          'body': '합성학과 · 2026학년도 입학 · 단일전공',
          'table': {
            'rows': [],
            'grid': [
              ['구분', '단일전공'],
              ['졸업 학점', '120'],
              ['전공 필수', '30'],
            ],
          },
          'sources': [
            {'title': '학교 게시 기준 · 합성 개정본'},
          ],
        },
      ],
    });
    c.setMode(AssistantMode.school);
    await tester.pumpAndSettle();
    expect(find.text('합성 졸업 학점표'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(tester.getRect(home), dockedBounds);
    expect(identical(tester.element(home), homeElement), isTrue);
    final panelRect = tester.getRect(find.byType(AssistantPanel));
    expect(dockedBounds.right, lessThanOrEqualTo(panelRect.left));
    expect(tester.takeException(), isNull);
    await capture('cards');
    await tester.tap(find.byTooltip('AI 도우미 닫기'));
    await tester.pumpAndSettle();
    expect(tester.getRect(home), closedBounds);
    expect(identical(tester.element(home), homeElement), isTrue);
    expect(tester.takeException(), isNull);
    await capture('restored');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('published criteria desktop render matrix', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    tester.view.devicePixelRatio = 1;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.resetDevicePixelRatio);
    await (FontLoader('Pretendard')..addFont(
          rootBundle.load('assets/fonts/pretendard/Pretendard-Regular.otf'),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final output = Directory('../output/guidance-published-cards');
    const capture = bool.fromEnvironment('GUIDANCE_CAPTURE');
    if (capture) {
      await tester.runAsync(() => output.create(recursive: true));
    }
    for (final palette in AppPalette.values) {
      for (final state in ['credits', 'volunteer', 'empty']) {
        for (final scale in [1.0, if (state == 'credits') 2.0]) {
          final empty = state == 'empty';
          final message = empty
              ? '학업 기준을 적용하면 학교 게시 기준을 볼 수 있습니다.'
              : '학교 관리자가 게시한 기준입니다. 내 학업 기준에 맞는 부분만 보여 드립니다.';
          final api = criteria.CriteriaGateway()
            // Exercise a failed independent rule catalog without losing cards.
            ..selection = {}
            ..nodeOverrides = {
              'title': state == 'volunteer' ? '봉사' : '이수학점',
              'state': 'ready',
              'reason': 'general_criteria',
              'message': message,
              'cards': [
                if (!empty)
                  {
                    'type': state == 'credits'
                        ? 'reference_table'
                        : 'reference_text',
                    'title': '합성 학교 게시 기준',
                    'body': state == 'credits'
                        ? '적용: 합성학과 · 2026학년도 입학 · 단일전공'
                        : '졸업인증 (1개 선택): 사회봉사 36시간\n'
                              '선택 조건 중 하나일 수 있습니다. 전체 조건은 졸업인증 항목에서 확인해 주세요.',
                    'sources': [
                      {'title': '학교 게시 기준 · 합성 개정본'},
                    ],
                    if (state == 'credits')
                      'table': {
                        'rows': [],
                        'grid': [
                          ['구분', '단일전공'],
                          ['최소 졸업 학점', '120'],
                          ['전공 · 필수', '30'],
                          ['해당 없는 항목', '해당 없음'],
                          ['미지정 항목', null],
                        ],
                      },
                  },
              ],
            };
          final c = criteria.conversation(api);
          await c.navigateGuidance(state == 'volunteer' ? state : 'credits');
          expect(c.criteriaError, isNotNull);
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
                      child: Align(
                        alignment: Alignment.topRight,
                        child: SizedBox(
                          width: 480,
                          child: SingleChildScrollView(
                            child: AcademicGuidanceView(conversation: c),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(message), findsOneWidget);
          expect(find.text(c.criteriaError!), findsNothing);
          if (!empty) {
            expect(find.text('학교 게시 기준 · 합성 개정본'), findsOneWidget);
          }
          if (state == 'credits') {
            expect(find.text('120'), findsOneWidget);
            await tester.ensureVisible(find.text('넓게 자세히 보기'));
            await tester.tap(find.text('넓게 자세히 보기'));
            await tester.pumpAndSettle();
            expect(find.byType(Dialog), findsOneWidget);
            expect(find.text('120'), findsNWidgets(2));
            await tester.tap(find.byTooltip('상세 닫기'));
            await tester.pumpAndSettle();
          }
          await tester.ensureVisible(find.text('처음으로'));
          expect(tester.takeException(), isNull);
          if (capture) {
            await tester.runAsync(() async {
              final frame =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 1);
              final bytes = await frame.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File('${output.path}/${state}_${palette.name}_$scale.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              frame.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox());
          c.dispose();
        }
      }
    }
  });
}
