import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app.dart';
import 'package:university_path_frontend/shared/widgets/page_header.dart';
import 'package:university_path_frontend/features/records/course/course_page.dart';
import 'package:university_path_frontend/features/records/activity/activity_page.dart';
import 'package:university_path_frontend/features/records/experience/experience_page.dart';
import 'package:university_path_frontend/features/records/credential/credential_page.dart';

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
