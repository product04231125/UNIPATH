import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/api/student_api_models.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/auth/guest_preview_scope.dart';
import 'package:university_path_frontend/features/auth/school_workflow_session.dart';
import 'package:university_path_frontend/features/graduation/graduation_page.dart';
import 'package:university_path_frontend/features/graduation/student_academic_page.dart';
import 'package:university_path_frontend/features/graduation/official_graduation_page.dart';
import 'package:university_path_frontend/features/graduation/personal_calculation_controller.dart';
import 'package:university_path_frontend/features/graduation/personal_calculation_draft.dart';
import 'package:university_path_frontend/features/graduation/personal_calculation_page.dart';
import 'package:university_path_frontend/features/planning/planning_profile_cta.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/features/records/personal_repository_scope.dart';
import 'package:university_path_frontend/shared/widgets/feature_page.dart';

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
      if (path.endsWith('/academic-contexts')) {
        return fixture.json({
          'owner_id': userId,
          'version': 0,
          'institution_id': otherId,
          'contexts': <Object>[],
          'issues': ['contexts_required'],
        });
      }
      if (path.endsWith('/academic-requirements')) {
        return fixture.json({
          'owner_id': userId,
          'workspace_version': 0,
          'activation_id': null,
          'documents': <Object>[],
          'issues': ['contexts_required'],
        });
      }
      if (path.endsWith('/academic-requirements/preview')) {
        return fixture.json({
          'owner_id': userId,
          'workspace_version': 0,
          'active_activation_id': null,
          'digest': 'a' * 64,
          'documents': <Object>[],
          'changes': <Object>[],
          'issues': ['contexts_required'],
        });
      }
      if (path.endsWith('/academic-credit-progress')) {
        return fixture.json({
          'owner_id': userId,
          'activation_id': null,
          'tables': <Object>[],
          'links': <Object>[],
          'issues': ['contexts_required'],
        });
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
  PlanningRepository? planning,
  PersonalCalculationController? calculations,
  VoidCallback? onOpenSettings,
  bool withSession = true,
  bool guest = false,
}) {
  final page = GraduationPage(
    planning: planning,
    onOpenSettings: onOpenSettings ?? () {},
  );
  final body = SchoolWorkflowSession(
    auth: auth,
    identity: AuthIdentity.fromJson(Map<String, dynamic>.from(identityJson())),
    child: calculations == null
        ? page
        : PersonalRepositoryScope(
            records: (_) => throw StateError('unused'),
            portfolio: () => throw StateError('unused'),
            calculations: calculations,
            child: page,
          ),
  );
  return MaterialApp(
    home: Scaffold(
      body: GuestPreviewScope(active: guest, child: withSession ? body : page),
    ),
  );
}

class ReviewPlanningRepository extends PlanningRepository {
  bool failed = true;
  bool loading = false;
  int reloads = 0;
  @override
  bool get loadFailed => failed;
  @override
  bool get isLoading => loading;
  @override
  Future<void> load() async {
    reloads++;
    failed = false;
    notifyListeners();
  }
}

class ReviewCalculationController extends PersonalCalculationController {
  ReviewCalculationController(super.student) : super(ensureOpen: () {});
  int curriculaLoads = 0, historyLoads = 0;
  @override
  Future<void> loadCurricula({bool preserveSelection = false}) async {
    curriculaLoads++;
  }

  @override
  Future<void> loadHistory({bool more = false}) async {
    historyLoads++;
  }
}

class ReviewCurriculum extends Fake
    implements StudentRecord<StudentPersonalCurriculumCreate> {
  @override
  String get id => otherId;
  @override
  int get version => 1;
  @override
  StudentPersonalCurriculumCreate get data => ReviewCurriculumData();
}

class ReviewCurriculumData extends Fake
    implements StudentPersonalCurriculumCreate {
  @override
  String get title => '개인 교육과정';
  @override
  int get curriculumYear => 2024;
}

void main() {
  testWidgets(
    'catalog profile opens new requirements and retains official history entry',
    (tester) async {
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
      expect(find.byType(StudentAcademicPage), findsOneWidget);
      expect(find.byType(OfficialGraduationPage), findsNothing);
      expect(find.byType(PersonalCalculationPage), findsNothing);
      expect(find.text('학업 기준 설정'), findsOneWidget);
      expect(find.byType(FeaturePage), findsOneWidget);
      expect(find.text('졸업 요건'), findsOneWidget);
      await tester.tap(find.text('기존 졸업 감사·이력'));
      await tester.pumpAndSettle();
      expect(find.byType(OfficialGraduationPage), findsOneWidget);
      expect(find.text('졸업요건 감사 실행'), findsOneWidget);
    },
  );

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
    expect(find.byType(FeaturePage), findsOneWidget);
    expect(find.text('졸업 요건'), findsOneWidget);
    expect(find.text('개인 기준 계산'), findsNothing);
    expect(find.text('설정한 개인 기준으로 계산합니다.'), findsOneWidget);
    expect(find.textContaining('설정 · 개인 교육과정 작업에서 먼저 등록하세요'), findsOneWidget);
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

  testWidgets('missing calculation scope explains unavailable workspace', (
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
    var settingsOpened = false;
    await tester.pumpWidget(
      host(
        auth: auth,
        planning: planning,
        onOpenSettings: () => settingsOpened = true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OfficialGraduationPage), findsNothing);
    expect(find.byType(PersonalCalculationPage), findsNothing);
    expect(find.textContaining('학생 작업 공간이 필요합니다'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(PlanningProfileSettingsCta),
        matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        ),
      ),
    );
    expect(settingsOpened, isTrue);
    expect(find.text('졸업 요건'), findsOneWidget);
  });

  testWidgets('missing session shows unavailable API without calculation', (
    tester,
  ) async {
    final auth = await loginAuth();
    addTearDown(auth.close);
    await tester.pumpWidget(host(auth: auth, withSession: false));
    expect(find.text('학교 기준을 가져오는 API가 아직 연결되지 않았습니다.'), findsOneWidget);
    expect(find.byType(OfficialGraduationPage), findsNothing);
    expect(find.byType(PersonalCalculationPage), findsNothing);
    expect(find.text('졸업 요건'), findsOneWidget);
  });

  testWidgets('profile read failure is distinct from an unconfigured profile', (
    tester,
  ) async {
    final auth = await loginAuth();
    addTearDown(auth.close);
    final planning = ReviewPlanningRepository();
    addTearDown(planning.dispose);
    await tester.pumpWidget(host(auth: auth, planning: planning));
    expect(find.textContaining('학업 프로필을 읽지 못했습니다'), findsOneWidget);
    expect(find.byType(OfficialGraduationPage), findsNothing);
    expect(find.byType(PersonalCalculationPage), findsNothing);
    await tester.tap(find.text('학업 프로필 다시 불러오기'));
    await tester.pumpAndSettle();
    expect(planning.reloads, 1);
    expect(find.textContaining('학업 프로필을 읽지 못했습니다'), findsNothing);
    expect(find.text('설정에서 학업 프로필 등록'), findsOneWidget);
  });

  testWidgets('loading profile does not open a graduation execution page', (
    tester,
  ) async {
    final auth = await loginAuth();
    addTearDown(auth.close);
    final planning = ReviewPlanningRepository()..loading = true;
    addTearDown(planning.dispose);
    await tester.pumpWidget(host(auth: auth, planning: planning));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(OfficialGraduationPage), findsNothing);
    expect(find.byType(PersonalCalculationPage), findsNothing);
    expect(find.text('졸업 요건'), findsOneWidget);
  });

  testWidgets(
    'incomplete registered profile shows the new requirements setup action',
    (tester) async {
      final auth = await loginAuth();
      addTearDown(auth.close);
      final planning = await seededPlanning(
        const PlanningProfile(school: '검증 대학', institutionId: otherId),
      );
      addTearDown(planning.dispose);
      var settingsOpened = false;
      await tester.pumpWidget(
        host(
          auth: auth,
          planning: planning,
          onOpenSettings: () => settingsOpened = true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(StudentAcademicPage), findsOneWidget);
      expect(find.byType(OfficialGraduationPage), findsNothing);
      await tester.tap(find.text('프로필 설정으로'));
      expect(settingsOpened, isTrue);
    },
  );

  testWidgets('guest cannot run an otherwise ready official audit', (
    tester,
  ) async {
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
    await tester.pumpWidget(host(auth: auth, planning: planning, guest: true));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '졸업요건 감사 실행'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('empty curricula settings CTA invokes navigation', (
    tester,
  ) async {
    final auth = await loginAuth();
    addTearDown(auth.close);
    final controller = ReviewCalculationController(
      StudentApi(auth.forOwner(userId), ownerId: userId),
    );
    addTearDown(controller.dispose);
    var settingsOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PersonalCalculationPage(
            controller: controller,
            title: '졸업 요건',
            onOpenSettings: () => settingsOpened = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('설정 · 개인 교육과정 작업'));
    expect(settingsOpened, isTrue);
    expect(find.text('졸업 요건'), findsOneWidget);
  });

  testWidgets(
    'replacing calculation controller loads the new workspace and date',
    (tester) async {
      final auth = await loginAuth();
      addTearDown(auth.close);
      final first = ReviewCalculationController(
        StudentApi(auth.forOwner(userId), ownerId: userId),
      )..asOf = '2026-01-01';
      final second = ReviewCalculationController(
        StudentApi(auth.forOwner(userId), ownerId: userId),
      )..asOf = '2026-02-02';
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      Widget page(PersonalCalculationController c) => MaterialApp(
        home: Scaffold(body: PersonalCalculationPage(controller: c)),
      );
      await tester.pumpWidget(page(first));
      await tester.pumpAndSettle();
      expect(find.text('2026-01-01'), findsOneWidget);
      await tester.pumpWidget(page(second));
      await tester.pumpAndSettle();
      expect(second.curriculaLoads, 1);
      expect(second.historyLoads, 1);
      expect(find.text('2026-02-02'), findsOneWidget);
      expect(find.text('2026-01-01'), findsNothing);
    },
  );

  testWidgets('refresh detects a selected curriculum removed in settings', (
    tester,
  ) async {
    final auth = await loginAuth();
    addTearDown(auth.close);
    final controller = PersonalCalculationController(
      StudentApi(auth.forOwner(userId), ownerId: userId),
      ensureOpen: () {},
    );
    addTearDown(controller.dispose);
    final curriculum = ReviewCurriculum();
    controller.curricula = [curriculum];
    controller.sources = PersonalCalculationSources(
      curriculum: curriculum,
      rules: [],
      links: [],
      courses: [],
      activities: [],
      credentials: [],
      achievements: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PersonalCalculationPage(
            controller: controller,
            onOpenSettings: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('자료 다시 불러오기'));
    await tester.pumpAndSettle();
    expect(controller.sourceError, isNull);
    expect(controller.sources, isNull);
    expect(controller.curricula, isEmpty);
    expect(find.textContaining('설정 · 개인 교육과정 작업에서 먼저 등록하세요'), findsOneWidget);
  });

  test(
    'failed curricula refresh preserves entered calculation criteria',
    () async {
      final auth = await loginAuth();
      addTearDown(auth.close);
      final controller = PersonalCalculationController(
        StudentApi(auth.forOwner(userId), ownerId: userId),
        ensureOpen: () => throw StateError('workspace unavailable'),
      );
      addTearDown(controller.dispose);
      final draft = PersonalCalculationDraft()..values['minimum'] = '12';
      controller.drafts['rule'] = draft;
      await controller.loadCurricula();
      expect(controller.sourceError, isNotNull);
      expect(controller.drafts['rule'], same(draft));
      expect(draft.values['minimum'], '12');
    },
  );
}
