import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/auth/school_workflow_session.dart';
import 'package:university_path_frontend/features/graduation/graduation_page.dart';
import 'package:university_path_frontend/features/graduation/official_graduation_page.dart';
import 'package:university_path_frontend/features/graduation/personal_calculation_controller.dart';
import 'package:university_path_frontend/features/graduation/personal_calculation_page.dart';
import 'package:university_path_frontend/features/planning/planning_profile_cta.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/features/records/personal_repository_scope.dart';
import 'package:university_path_frontend/features/records/portfolio/portfolio_workspace_repository.dart';

import 'graduation_api_test.dart' as fixture;
import 'support/auth_fixture.dart';

Future<AuthApi> loginAuth() async {
  final auth = AuthApi(
    cookieMode: false,
    client: MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/login')) {
        return fixture.json({...identityJson(), 'access_token': token});
      }
      return fixture.json({'items': <Object?>[], 'next_cursor': null});
    }),
  );
  await fixture.login(auth);
  return auth;
}

Future<PlanningRepository> seededPlanning(PlanningProfile profile) async {
  SharedPreferences.setMockInitialValues({});
  final repo = PlanningRepository();
  await repo.load();
  await repo.saveProfile(profile);
  return repo;
}

Widget host({
  required AuthApi auth,
  required PlanningRepository planning,
  PersonalCalculationController? calculations,
}) {
  final page = GraduationPage(planning: planning, onOpenSettings: () {});
  final body = SchoolWorkflowSession(
    auth: auth,
    identity: AuthIdentity.fromJson(
      Map<String, dynamic>.from(identityJson()),
    ),
    child: calculations == null
        ? page
        : PersonalRepositoryScope(
            records: (_) => throw StateError('unused'),
            portfolio: () => throw StateError('unused'),
            calculations: calculations,
            child: page,
          ),
  );
  return MaterialApp(home: Scaffold(body: body));
}

void main() {
  testWidgets('catalog profile opens official graduation body', (tester) async {
    final auth = await loginAuth();
    addTearDown(auth.close);
    final planning = await seededPlanning(
      const PlanningProfile(
        school: '검증 대학',
        department: '검증 학과',
        admissionYear: 2026,
        track: 'single_major',
        institutionId: otherId,
        departmentId: otherId,
        curriculumId: otherId,
      ),
    );
    addTearDown(planning.dispose);
    await tester.pumpWidget(host(auth: auth, planning: planning));
    await tester.pumpAndSettle();
    expect(find.byType(OfficialGraduationPage), findsOneWidget);
    expect(find.byType(PersonalCalculationPage), findsNothing);
    expect(find.text('졸업요건 감사 실행'), findsOneWidget);
  });

  testWidgets('personal configured profile opens personal calculation body', (
    tester,
  ) async {
    final auth = await loginAuth();
    addTearDown(auth.close);
    final planning = await seededPlanning(
      const PlanningProfile(
        school: '개인 대학',
        department: '개인 학과',
        admissionYear: 2024,
      ),
    );
    addTearDown(planning.dispose);
    final student = StudentApi(auth.forOwner(userId), ownerId: userId);
    final calculations = PersonalCalculationController(
      student,
      ensureOpen: () {},
    );
    addTearDown(calculations.dispose);
    await tester.pumpWidget(
      host(auth: auth, planning: planning, calculations: calculations),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OfficialGraduationPage), findsNothing);
    expect(find.byType(PersonalCalculationPage), findsOneWidget);
    expect(find.text('졸업 요건'), findsWidgets);
    expect(find.text('설정한 개인 기준으로 계산합니다.'), findsOneWidget);
    expect(
      find.textContaining('설정 · 개인 교육과정 작업에서 먼저 등록하세요'),
      findsOneWidget,
    );
  });

  testWidgets('incomplete profile shows configured settings CTA', (
    tester,
  ) async {
    final auth = await loginAuth();
    addTearDown(auth.close);
    final planning = await seededPlanning(const PlanningProfile());
    addTearDown(planning.dispose);
    await tester.pumpWidget(host(auth: auth, planning: planning));
    await tester.pumpAndSettle();
    expect(find.byType(OfficialGraduationPage), findsNothing);
    expect(find.byType(PersonalCalculationPage), findsNothing);
    expect(find.byKey(planningProfileSettingsCtaKey), findsOneWidget);
    expect(find.text('설정에서 학업 프로필 등록'), findsOneWidget);
  });
}
