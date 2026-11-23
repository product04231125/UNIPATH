import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/academics/academics_page.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/career/career_goal.dart';
import 'package:university_path_frontend/features/career/career_goal_card.dart';

import 'job_recommendation_test.dart' show categoryFixture, selectOption;

class GoalGateway extends ApiGateway {
  Map<String, dynamic> goal = {
    'category_codes': <String>[],
    'keyword': '',
    'version': 0,
    'category_label': null,
  };
  final puts = <Map<String, Object?>>[];
  Object? putFailure;

  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    if (path == 'me/job-categories') return categoryFixture;
    expect(path, 'me/career-goal');
    if (method == 'GET') return goal;
    expect(method, 'PUT');
    puts.add(body!);
    if (putFailure case final failure?) {
      putFailure = null;
      throw failure;
    }
    final codes = body['category_codes'] as List;
    goal = {
      'category_codes': codes,
      'keyword': body['keyword'],
      'version': (goal['version'] as int) + 1,
      'category_label': codes.isEmpty
          ? null
          : codes.first == '024'
          ? '소프트웨어'
          : '연구 및 공학기술',
    };
    return goal;
  }
}

Future<CareerGoalController> mountCard(
  WidgetTester tester,
  GoalGateway api,
) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = CareerGoalController(api);
  addTearDown(controller.dispose);
  await controller.load();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CareerGoalCard(controller: controller, onFindJobs: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('학생이 목표 직무를 정하고 바꾼다', (tester) async {
    final api = GoalGateway();
    await mountCard(tester, api);
    await tester.tap(find.byKey(const ValueKey('career-goal-set')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('goal-save')));
    await tester.pumpAndSettle();
    expect(find.text('직종을 고르거나 세부 검색어를 입력하세요.'), findsOneWidget);
    expect(api.puts, isEmpty);

    await selectOption(tester, 'goal-category', '연구 및 공학기술');
    await selectOption(tester, 'goal-subcategory-02', '소프트웨어');
    await tester.enterText(
      find.byKey(const ValueKey('goal-keyword')),
      ' 프론트엔드 ',
    );
    await tester.tap(find.byKey(const ValueKey('goal-save')));
    await tester.pumpAndSettle();
    expect(api.puts.single, {
      'category_codes': ['024'],
      'keyword': '프론트엔드',
      'expected_version': 0,
    });
    expect(find.text('소프트웨어 · 프론트엔드'), findsOneWidget);
    expect(find.text('맞는 공고 찾기'), findsOneWidget);

    // Another device changed the goal first: reload and ask to save again.
    api.putFailure = const AuthFailure('conflict', status: 409);
    await tester.tap(find.byKey(const ValueKey('career-goal-change')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('goal-save')));
    await tester.pumpAndSettle();
    expect(
      find.text('다른 기기에서 목표 직무가 바뀌어 다시 불러왔습니다. 확인 후 다시 저장하세요.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('goal-save')));
    await tester.pumpAndSettle();
    expect(api.puts.last['expected_version'], 1);
    expect(find.text('소프트웨어 · 프론트엔드'), findsOneWidget);
  });

  testWidgets('학사는 수강 관리와 졸업 요건을 탭으로 연다', (tester) async {
    var tab = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AcademicsPage(
              tab: tab,
              onTabChanged: (value) => setState(() => tab = value),
              courses: const Text('수강 화면'),
              graduation: const Text('졸업 화면'),
            ),
          ),
        ),
      ),
    );
    expect(find.text('졸업 화면'), findsOneWidget);
    expect(find.text('수강 화면', skipOffstage: true), findsNothing);
    await tester.tap(find.text('수강 관리'));
    await tester.pumpAndSettle();
    expect(find.text('수강 화면'), findsOneWidget);
  });
}
