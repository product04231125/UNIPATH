import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/shared/widgets/page_header.dart';
import 'package:university_path_frontend/features/records/course/course_page.dart';
import 'package:university_path_frontend/features/records/activity/activity_page.dart';
import 'package:university_path_frontend/features/records/experience/experience_page.dart';
import 'package:university_path_frontend/features/records/credential/credential_page.dart';
import 'package:university_path_frontend/features/records/portfolio/portfolio_page.dart';
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
          const CoursePage(showMockData: false),
          const ActivityPage(showMockData: false),
          const ExperiencePage(showMockData: false),
          const CredentialPage(showMockData: false),
          SchedulePage(repository: repository),
          SettingsPage(repository: repository),
          const GraduationPage(showMockData: false),
        ]) {
          await tester.pumpWidget(host(page, scale: scale));
          await tester.pumpAndSettle();
          final header = find.byType(PageHeader);
          expect(header, findsOneWidget);
          expect(tester.getTopLeft(header), const Offset(28, 28));
          expect(tester.takeException(), isNull, reason: '$page');
        }

        await tester.pumpWidget(
          host(const PortfolioPage(showMockData: false), scale: scale),
        );
        await tester.pumpAndSettle();
        final tabs = ['1. 성과 기록', '2. 포트폴리오 구성', '3. 지원 문서'];
        final titles = ['성과 기록', '포트폴리오 구성', '지원 문서'];
        final anchor = tester.getTopLeft(find.byType(PageHeader));
        final tabRow = find
            .ancestor(of: find.text(tabs.first), matching: find.byType(Wrap))
            .first;
        expect(anchor.dx, 28);
        expect(anchor.dy - tester.getBottomLeft(tabRow).dy, closeTo(12, .01));
        for (var index = 0; index < tabs.length; index++) {
          await tester.tap(find.text(tabs[index]));
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(find.byType(PageHeader)), anchor);
          expect(
            find.descendant(
              of: find.byType(PageHeader),
              matching: find.text(titles[index]),
            ),
            findsOneWidget,
          );
          expect(find.textContaining('PORTFOLIO & OUTCOMES'), findsNothing);
          if (index > 0) {
            expect(
              tester.getTopLeft(find.byType(FilledButton).first).dx,
              anchor.dx,
            );
            expect(
              find.textContaining(
                index == 1 ? '기기 로컬 사용 의도' : '지원처로 제출하지 않습니다.',
              ),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
        }

        await tester.pumpWidget(
          host(PersonalGraduationWorkspace(onBack: () {}), scale: scale),
        );
        await tester.pumpAndSettle();
        final personalAnchor = tester.getTopLeft(find.byType(PageHeader));
        expect(personalAnchor.dx, 28);
        for (final label in ['교육과정', '교육과정 과목', '개인 규칙']) {
          await tester.tap(find.text(label).first);
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(find.byType(PageHeader)), personalAnchor);
          expect(find.text('개인 학업 작업 공간'), findsOneWidget);
          expect(find.textContaining('학교 공식 규칙이나 판정이 아닙니다.'), findsOneWidget);
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
      const CoursePage(showMockData: false),
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

  testWidgets(
    'record menu headers use Korean titles and retain local notices',
    (tester) async {
      for (final (page, title) in <(Widget, String)>[
        (const CoursePage(showMockData: false), '수강 관리'),
        (const ActivityPage(showMockData: false), '활동'),
        (const ExperiencePage(showMockData: false), '경험'),
        (const CredentialPage(showMockData: false), '자격'),
      ]) {
        await tester.pumpWidget(host(page));
        // The same header stays visible before and after storage loads.
        expect(find.byType(PageHeader), findsOneWidget);
        expect(tester.getTopLeft(find.text(title)), const Offset(28, 28));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.text(title)), const Offset(28, 28));
        expect(find.textContaining('학교 정보가 없어도'), findsOneWidget);
        expect(find.textContaining('RECORDS'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
