import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/main.dart';

void main() {
  testWidgets('renders the UniversityPath workspace', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(const UniversityPathApp());
    expect(find.text('UniversityPath'), findsOneWidget);
    expect(find.text('정민서님, 오늘 무엇을 정리해볼까요?'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('adds a personal record from the course menu', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(const UniversityPathApp());

    await tester.tap(find.text('수강 관리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('수강 과목 직접 입력'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '운영체제');
    await tester.enterText(find.byType(TextField).at(1), '전공선택 · 3학점');
    await tester.tap(find.text('내 기록에 저장'));
    await tester.pumpAndSettle();

    expect(find.text('운영체제'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('configures a personal academic rule set', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(const UniversityPathApp());

    await tester.tap(find.text('졸업 요건'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('내 학교·학과 기준 설정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '테스트대학교');
    await tester.enterText(find.byType(TextField).at(1), '소프트웨어학과');
    await tester.enterText(find.byType(TextField).at(2), '2024');
    await tester.enterText(find.byType(TextField).at(3), '최소 총 취득학점');
    await tester.enterText(find.byType(TextField).at(4), '120');
    await tester.enterText(find.byType(TextField).at(5), '90');
    await tester.tap(find.text('개인 기준으로 저장'));
    await tester.pumpAndSettle();

    expect(find.text('개인 기준 계산'), findsOneWidget);
    expect(find.textContaining('테스트대학교'), findsWidgets);
    await tester.binding.setSurfaceSize(null);
  });
}
