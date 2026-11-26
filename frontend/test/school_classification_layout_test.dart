import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/features/admin/admin_models.dart';
import 'package:university_path_frontend/features/admin/admin_repository.dart';
import 'package:university_path_frontend/features/admin/admin_workspace.dart';
import 'package:university_path_frontend/features/admin/school_classification_drafts.dart';
import 'package:university_path_frontend/features/admin/school_classification_widgets.dart';
import 'package:university_path_frontend/features/auth/app_role.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/features/settings/settings_page.dart';
import 'package:university_path_frontend/shared/app_style.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';

const capture = bool.fromEnvironment('SCHOOL_CLASSIFICATION_CAPTURE');

Future<void> screenshot(WidgetTester tester, GlobalKey key, String name) async {
  if (!capture) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final frame = await boundary.toImage(pixelRatio: 1);
    final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
    final output = Directory('../output/school-classification-ui')
      ..createSync(recursive: true);
    await File('${output.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    frame.dispose();
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    if (!capture) return;
    await (FontLoader('Pretendard')..addFont(
          rootBundle.load('assets/fonts/pretendard/Pretendard-Regular.otf'),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets('saved school track remains visible with no fixed choice menu', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = PlanningRepository();
    addTearDown(repository.dispose);
    await repository.load();
    await repository.saveProfile(
      const PlanningProfile(
        school: '합성 대학',
        department: '합성 학과',
        admissionYear: 2026,
        track: 'single_major',
      ),
    );
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: universityPathTheme(),
        home: RepaintBoundary(
          key: boundary,
          child: Scaffold(body: SettingsPage(repository: repository)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final track = find.byKey(const Key('settings-school-track'));
    expect(
      find.descendant(of: track, matching: find.text('단일전공')),
      findsOneWidget,
    );
    expect(tester.widget<InputDecorator>(track).decoration.enabled, isFalse);
    expect(find.text('복수전공'), findsNothing);
    expect(tester.takeException(), isNull);
    await screenshot(tester, boundary, 'settings');
  });

  for (final empty in [true, false]) {
    testWidgets('curriculum tabs keep the same card origin with empty=$empty', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final seed = FakeAdminRepository().records
          .where(
            (r) =>
                !empty ||
                ![
                  AdminKind.course,
                  AdminKind.curriculum,
                  AdminKind.curriculumCourse,
                ].contains(r.kind),
          )
          .toList();
      if (!empty) {
        seed.addAll([
          AdminRecord(
            id: 'layout-course',
            kind: AdminKind.course,
            values: {
              'name': '합성 과목',
              'institutionId': 'school-a',
              'code': 'COURSE',
              'credits': '3',
            },
          ),
          AdminRecord(
            id: 'layout-link',
            kind: AdminKind.curriculumCourse,
            values: {
              'name': '합성 과목 연결',
              'curriculumId': 'school-a-curr',
              'courseId': 'layout-course',
              'institutionId': 'school-a',
              'category': 'major',
              'required': 'true',
            },
          ),
        ]);
      }
      final repo = FakeAdminRepository(seed: seed);
      addTearDown(repo.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: universityPathTheme(),
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              body: AdminWorkspace(
                repository: repo,
                role: AppRole.superAdmin,
                path: '/admin/curricula',
                initialSchoolId: 'school-a',
                onNavigate: (_) {},
                onSignedOut: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Rect? origin;
      for (final kind in [
        AdminKind.course,
        AdminKind.curriculum,
        AdminKind.curriculumCourse,
      ]) {
        tester
            .widget<OutlinedButton>(
              find.byKey(ValueKey('admin-curriculum-view-${kind.name}')),
            )
            .onPressed!();
        await tester.pumpAndSettle();
        final frame = find.byKey(ValueKey('admin-frame-${kind.name}'));
        final rect = tester.getRect(frame);
        origin ??= rect;
        expect(rect.top, closeTo(origin.top, .01));
        expect(rect.left, closeTo(origin.left, .01));
        expect(rect.width, closeTo(origin.width, .01));
        if (kind != AdminKind.curriculum) {
          final section = find.byKey(
            ValueKey('admin-course-classifications-${kind.name}'),
          );
          for (final field in ['category', 'required']) {
            expect(
              find.descendant(
                of: section,
                matching: find.byKey(ValueKey('admin-field-$field')),
              ),
              findsOneWidget,
            );
          }
          expect(
            find.descendant(
              of: section,
              matching: find.byWidgetPredicate(
                (w) => w is AnchoredSelectField<String> && w.label == '이수 경로',
              ),
            ),
            findsOneWidget,
          );
          expect(find.text('세부분류·이수 경로 초안 · 서버 저장 전'), findsNothing);
        } else {
          expect(find.text('과목 분류'), findsNothing);
        }
        if (capture && !empty) {
          await tester.ensureVisible(frame);
          await tester.pumpAndSettle();
          await screenshot(tester, boundary, kind.name);
          final scrollable = find
              .ancestor(of: frame, matching: find.byType(Scrollable))
              .first;
          tester.state<ScrollableState>(scrollable).position.jumpTo(0);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets(
    'school classification lists retain school scope and scroll long lists',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final drafts = SchoolClassificationDrafts();
      addTearDown(drafts.dispose);
      for (var i = 0; i < 7; i++) {
        drafts.save(
          schoolId: 'a',
          kind: SchoolClassificationKind.category,
          name: '전공 분류 $i',
        );
      }
      final category = drafts.entries('a').first;
      drafts.save(
        schoolId: 'a',
        kind: SchoolClassificationKind.subcategory,
        name: '전공기초',
        parentId: category.id,
      );
      drafts.save(
        schoolId: 'a',
        kind: SchoolClassificationKind.track,
        name: '학교 등록 이수 경로',
      );
      drafts.save(
        schoolId: 'b',
        kind: SchoolClassificationKind.track,
        name: '다른 학교 경로',
      );
      final boundary = GlobalKey();
      Widget host(AppPalette palette) => MaterialApp(
        theme: universityPathTheme(palette: palette),
        home: RepaintBoundary(
          key: boundary,
          child: Scaffold(
            body: SingleChildScrollView(
              child: SchoolClassificationSection(
                drafts: drafts,
                schoolId: 'a',
                schoolName: '합성 대학',
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(host(AppPalette.cream));
      await tester.pumpAndSettle();
      expect(find.text('다른 학교 경로'), findsNothing);
      expect(find.text('학교 등록 이수 경로'), findsOneWidget);
      final group = find.byKey(const ValueKey('classification-list-category'));
      final list = find.descendant(of: group, matching: find.byType(ListView));
      expect(tester.getSize(list).height, lessThanOrEqualTo(64 * 3));
      final last = drafts.entries('a', SchoolClassificationKind.category).last;
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('classification-row-${last.id}')),
        100,
        scrollable: find.descendant(
          of: group,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(last.name).hitTestable(), findsOneWidget);
      expect(
        find.descendant(
          of: group,
          matching: find.widgetWithText(OutlinedButton, '수정'),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: group,
          matching: find.widgetWithText(FilledButton, '초안 삭제'),
        ),
        findsWidgets,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '학교 분류 저장 · 연결 전'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await screenshot(tester, boundary, 'classification-lists');
      if (capture) {
        for (final palette in AppPalette.values.where(
          (p) => p != AppPalette.cream,
        )) {
          await tester.pumpWidget(host(palette));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await screenshot(
            tester,
            boundary,
            'classification-lists-${palette.name}',
          );
        }
      }
    },
  );
}
