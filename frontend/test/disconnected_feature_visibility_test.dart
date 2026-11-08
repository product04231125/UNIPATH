import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/admin/admin_repository.dart';
import 'package:university_path_frontend/features/admin/admin_rule_execution_panel.dart';
import 'package:university_path_frontend/features/auth/school_workflow_actions.dart';
import 'package:university_path_frontend/features/graduation/graduation_page.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/features/settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/graduation/personal_graduation_workspace.dart';
import 'package:university_path_frontend/features/records/personal_repository_scope.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/portfolio/portfolio_workspace_repository.dart';

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('disconnected school actions remain visible and disabled', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(const SchoolWorkflowActions()));
    for (final label in ['학교 문서 검색·근거', '학교 발급 PDF 제출·이력', '학교 확인 학생 기록']) {
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, label),
      );
      expect(button.onPressed, isNull);
    }
  });
  testWidgets(
    'rule API disconnection retains scope, destination, save and review controls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = FakeAdminRepository();
      addTearDown(repo.dispose);
      await tester.pumpWidget(
        host(
          AdminRuleExecutionPanel(
            repository: repo,
            actorId: 'super-admin',
            schoolId: 'school-a',
            ruleType: 'manual_review',
            description: '',
            rule: null,
            metadataDirty: false,
            onBusy: (_) {},
            onChanged: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('저장 위치'), findsWidgets);
      expect(find.textContaining('적용 입학연도 시작'), findsWidgets);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '한 줄 요건 저장'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '실행본 승인·회수 검토'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'graduation without session keeps implemented calculation and history entry labels',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: const GraduationPage())),
      );
      for (final label in ['학교 기준 졸업 감사', '감사 이력 조회', '개인 기준 계산·이력']) {
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, label),
              )
              .onPressed,
          isNull,
        );
      }
    },
  );
  testWidgets(
    'personal workspace keeps unsupported department and disconnected calculation discoverable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repositories = <PersonalRecordKind, PersonalRecordRepository>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PersonalRepositoryScope(
              records: (kind) => repositories.putIfAbsent(
                kind,
                () => PersonalRecordRepository(kind),
              ),
              portfolio: PortfolioWorkspaceRepository.new,
              child: PersonalGraduationWorkspace(onBack: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '학과 · 서버 연결 전'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '개인 기준 계산·이력'),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('개인 학과 관리의 서버 저장 계약'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'local settings show server import and school lookup availability',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final planning = PlanningRepository();
      await planning.load();
      addTearDown(planning.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SettingsPage(repository: planning)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('기기 학업 정보·일정 이전'), findsOneWidget);
      expect(find.text('기기 개인 기록 이전'), findsOneWidget);
      expect(find.text('등록된 학교·학과·교육과정 선택'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
