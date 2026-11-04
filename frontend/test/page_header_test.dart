import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/app_shell/phone_shell.dart';
import 'package:university_path_frontend/shared/app_typography.dart';
import 'package:university_path_frontend/shared/widgets/page_header.dart';
import 'package:university_path_frontend/shared/widgets/content_scroll_view.dart';
import 'package:university_path_frontend/features/records/course/course_page.dart';
import 'package:university_path_frontend/features/records/activity/activity_page.dart';
import 'package:university_path_frontend/features/records/experience/experience_page.dart';
import 'package:university_path_frontend/features/records/credential/credential_page.dart';
import 'package:university_path_frontend/features/records/portfolio/job_analysis_page.dart';
import 'package:university_path_frontend/features/records/portfolio/materials_page.dart';
import 'package:university_path_frontend/features/records/portfolio/portfolio_drafts_page.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/features/schedule/schedule_page.dart';
import 'package:university_path_frontend/features/settings/settings_page.dart';
import 'package:university_path_frontend/features/graduation/graduation_page.dart';
import 'package:university_path_frontend/features/graduation/personal_graduation_workspace.dart';

Widget host(Widget child, {double scale = 1}) => MaterialApp(
  theme: universityPathTheme(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(28),
      child: Align(alignment: Alignment.topLeft, child: child),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [
    const Size(1440, 900),
    const Size(900, 768),
    const Size(480, 520),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('all menu headers and tabs align at $size scale=$scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = PlanningRepository();
        addTearDown(repository.dispose);
        await repository.load();
        for (final page in <Widget>[
          const CoursePage(),
          const ActivityPage(),
          const ExperiencePage(),
          const CredentialPage(),
          SchedulePage(repository: repository),
          SettingsPage(repository: repository),
          const GraduationPage(),
          const MaterialsPage(),
          const JobAnalysisPage(),
        ]) {
          await tester.pumpWidget(host(page, scale: scale));
          await tester.pumpAndSettle();
          final header = find.byType(PageHeader);
          expect(header, findsOneWidget);
          expect(tester.getTopLeft(header), const Offset(28, 28));
          final scroll = find
              .ancestor(of: header, matching: find.byType(ContentScrollView))
              .first;
          expect(
            tester.getRect(scroll).right - tester.getRect(header).right,
            greaterThanOrEqualTo(16),
          );
          expect(tester.takeException(), isNull, reason: '$page');
        }

        await tester.pumpWidget(
          host(PersonalGraduationWorkspace(onBack: () {}), scale: scale),
        );
        await tester.pumpAndSettle();
        final personalAnchor = tester.getTopLeft(find.byType(PageHeader));
        expect(personalAnchor.dx, 28);
        for (final label in ['교육과정', '교육과정 과목', '규칙']) {
          await tester.tap(find.text(label).first);
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(find.byType(PageHeader)), personalAnchor);
          expect(find.textContaining('개인 학업 정보'), findsOneWidget);
          expect(find.text('개인 $label'), findsOneWidget);
          expect(find.text('개인 개인 규칙'), findsNothing);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('headers remain identifiable when local storage fails', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'university_path.personal_records.course.v1': 'invalid',
      'university_path.personal_planning.v1': 'invalid',
      'university_path.portfolio_workspace.v1': 'invalid',
    });
    final repository = PlanningRepository();
    addTearDown(repository.dispose);
    await repository.load();
    for (final page in <Widget>[
      const CoursePage(),
      SchedulePage(repository: repository),
      SettingsPage(repository: repository),
      const PortfolioDraftsPage(isDocument: false),
      const PortfolioDraftsPage(isDocument: true),
    ]) {
      await tester.pumpWidget(host(page));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(PageHeader)), const Offset(28, 28));
      expect(find.text('다시 시도'), findsOneWidget);
      expect(find.textContaining('덮어쓰지 않습니다.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('page header optional lines have no reserved label space', (
    tester,
  ) async {
    await tester.pumpWidget(host(const PageHeader(title: '제목')));
    final titleRect = tester.getRect(find.text('제목'));
    expect(titleRect.topLeft, const Offset(28, 28));
    expect(
      tester.getSize(find.byType(PageHeader)).height,
      closeTo(titleRect.height + 16, .01),
    );
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.text('제목')),
      matchesSemantics(label: '제목', isHeader: true),
    );
    semantics.dispose();
    await tester.pumpWidget(
      host(
        const PageHeader(title: '제목', contextLabel: '개인 자료', description: '설명'),
      ),
    );
    expect(tester.getTopLeft(find.text('제목')), titleRect.topLeft);
    expect(
      tester.getTopLeft(find.text('개인 자료')).dy -
          tester.getBottomLeft(find.text('제목')).dy,
      closeTo(8, .01),
    );
    expect(
      tester.getTopLeft(find.text('설명')).dy -
          tester.getBottomLeft(find.text('개인 자료')).dy,
      closeTo(8, .01),
    );
  });

  testWidgets(
    'page header long Korean text and actions reflow at narrow width and 200%',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 520));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: PageHeader(
              title: '개인 교육과정과 졸업 요건 기록',
              contextLabel: '학교와 학과 및 적용 입학연도는 직접 기록한 개인 자료입니다.',
              description: '자료의 성격과 현재 화면에서 할 수 있는 작업을 긴 한글 문장으로 설명합니다.',
              actions: [
                OutlinedButton(
                  onPressed: () {},
                  child: const Text('내 학교·학과 기준 설정'),
                ),
              ],
            ),
          ),
          scale: 2,
        ),
      );
      expect(
        tester.getTopLeft(find.byType(OutlinedButton)).dy,
        greaterThan(tester.getBottomLeft(find.text('개인 교육과정과 졸업 요건 기록')).dy),
      );
      expect(find.text('학교와 학과 및 적용 입학연도는 직접 기록한 개인 자료입니다.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('record menu headers use Korean titles and a short description', (
    tester,
  ) async {
    for (final (page, title) in <(Widget, String)>[
      (const CoursePage(), '수강 관리'),
      (const ActivityPage(), '활동'),
      (const ExperiencePage(), '경험'),
      (const CredentialPage(), '자격'),
    ]) {
      await tester.pumpWidget(host(page));
      // The same header stays visible before and after storage loads.
      expect(find.byType(PageHeader), findsOneWidget);
      expect(tester.getTopLeft(find.text(title)), const Offset(28, 28));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text(title)), const Offset(28, 28));
      expect(
        find.textContaining(
          page is CoursePage
              ? '학기별 수강 계획과 개인 이수 기록을 정리합니다.'
              : page is ActivityPage
              ? '교내외 활동과 봉사 내역을 한곳에 기록합니다.'
              : page is ExperiencePage
              ? '프로젝트·인턴·동아리 경험을 이력 문장과 강점으로 정리합니다.'
              : '자격증·어학·교육 이수 내역을 관리합니다.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('RECORDS'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('phone chrome uses a compact page title and bottom gap', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: universityPathTheme(),
        home: const PhoneChromeScope(
          active: true,
          child: Scaffold(body: PageHeader(title: '제목')),
        ),
      ),
    );
    expect(
      tester.widget<Text>(find.text('제목')).style?.fontSize,
      phonePageTitleSize,
    );
    final titleRect = tester.getRect(find.text('제목'));
    expect(
      tester.getSize(find.byType(PageHeader)).height,
      closeTo(titleRect.height + phonePageHeaderBottomGap, .01),
    );
  });

  testWidgets('phone size without PhoneChromeScope keeps the wide page title', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: universityPathTheme(),
        home: const Scaffold(body: PageHeader(title: '제목')),
      ),
    );
    expect(
      tester.widget<Text>(find.text('제목')).style?.fontSize,
      AppTypography.page,
    );
  });
}
