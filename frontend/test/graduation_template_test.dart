import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/admin/admin_models.dart';
import 'package:university_path_frontend/features/admin/admin_repository.dart';
import 'package:university_path_frontend/features/admin/admin_workspace.dart';
import 'package:university_path_frontend/features/admin/graduation_certification_page.dart';
import 'package:university_path_frontend/features/admin/graduation_credit_grid.dart';
import 'package:university_path_frontend/features/admin/graduation_credit_grid_page.dart';
import 'package:university_path_frontend/features/auth/app_role.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

List<AdminRecord> departments() => [
  AdminRecord(
    id: 'dept-cs',
    kind: AdminKind.department,
    values: {'name': '컴퓨터공학과', 'institutionId': 'school-a'},
  ),
];

void main() {
  testWidgets('credit grid keeps empty, number, and not-applicable cells', (
    tester,
  ) async {
    final group = GraduationCreditColumnGroup(id: 'g1', label: '교양 과목');
    final leaf = GraduationCreditColumn(id: 'c1', label: '기초교양', groupId: 'g1');
    final empty = GraduationCreditColumn(
      id: 'c2',
      label: '경동교양',
      groupId: 'g1',
    );
    final na = GraduationCreditColumn(id: 'c3', label: '기초과학', groupId: 'g1');
    final row = GraduationCreditRow(id: 'r1', label: '단일전공', note: '');
    final grid = GraduationCreditGrid(
      admissionYear: '2026',
      departmentId: 'dept-cs',
      groups: [group],
      columns: [leaf, empty, na],
      rows: [row],
    );
    grid.cellFor('r1', 'c1')
      ..kind = GraduationCreditCellKind.number
      ..value = '7';
    grid.cellFor('r1', 'c3').kind = GraduationCreditCellKind.notApplicable;
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      host(
        GraduationCreditGridPage(
          schoolName: '경동대학교',
          departments: departments(),
          initial: grid,
          scrollable: true,
        ),
      ),
    );
    expect(find.text('7'), findsWidgets);
    expect(find.text('비어 있음'), findsWidgets);
    expect(find.text('해당 없음'), findsWidgets);
    expect(find.text('학점표 저장 불가 · 연결 전'), findsOneWidget);
    expect(find.textContaining('저장은 연결되지 않았습니다'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('credit-grid-preview')));
    await tester.pumpAndSettle();
    expect(find.text('학점표 미리보기'), findsOneWidget);
    expect(find.text('경동대학교 컴퓨터공학과 졸업최소이수학점'), findsOneWidget);
    expect(find.text('2026학년도 입학자'), findsOneWidget);
    expect(find.text('-'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('template-preview-dialog')),
        matching: find.text('비어 있음'),
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('template-preview-close')));
    await tester.pumpAndSettle();
    expect(find.text('학점표 미리보기'), findsNothing);
  });

  testWidgets('credit grid warns when printed subtotal differs from leaf sum', (
    tester,
  ) async {
    final group = GraduationCreditColumnGroup(id: 'g1', label: '교양 과목');
    final leaf = GraduationCreditColumn(id: 'c1', label: '기초교양', groupId: 'g1');
    final subtotal = GraduationCreditColumn(id: 'c2', label: '교양 과목');
    final row = GraduationCreditRow(id: 'r1', label: '단일전공');
    final grid = GraduationCreditGrid(
      admissionYear: '2026',
      departmentId: 'dept-cs',
      groups: [group],
      columns: [leaf, subtotal],
      rows: [row],
    );
    grid.cellFor('r1', 'c1')
      ..kind = GraduationCreditCellKind.number
      ..value = '7';
    grid.cellFor('r1', 'c2')
      ..kind = GraduationCreditCellKind.number
      ..value = '31';
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      host(
        GraduationCreditGridPage(
          schoolName: '경동대학교',
          departments: departments(),
          initial: grid,
          scrollable: true,
        ),
      ),
    );
    expect(find.textContaining('잎 칸 합 7과 입력한 교양 과목 31이 다릅니다'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
    expect(find.text('학점표 저장 불가 · 연결 전'), findsOneWidget);
  });

  testWidgets(
    'certification groups keep pick-one and exemption without judging',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        host(
          GraduationCertificationPage(
            schoolName: '경동대학교',
            departments: departments(),
            scrollable: true,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('certification-add-group')));
      await tester.pump();
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'certification-group-',
              ),
        ),
        '창의영역',
      );
      await tester.tap(find.text('기준 추가'));
      await tester.pump();
      await tester.tap(find.text('면제 대상 추가'));
      await tester.pump();
      expect(find.textContaining('창의영역'), findsWidgets);
      expect(find.text('인증 요건 저장 불가 · 연결 전'), findsOneWidget);
      expect(find.textContaining('취득 여부를 판정하지 않습니다'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('certification-preview')));
      await tester.pumpAndSettle();
      expect(find.text('인증 요건 미리보기'), findsOneWidget);
      expect(find.text('경동대학교 컴퓨터공학과 졸업자격요건'), findsOneWidget);
      expect(find.text('창의영역 (모두)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('template-preview-close')));
      await tester.pumpAndSettle();
      expect(find.text('인증 요건 미리보기'), findsNothing);
    },
  );

  testWidgets(
    'rules menu keeps line editor beside credit and certification views',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = FakeAdminRepository();
      addTearDown(repo.dispose);
      await tester.pumpWidget(
        host(
          AdminWorkspace(
            repository: repo,
            role: AppRole.superAdmin,
            path: '/admin/rules',
            onNavigate: (_) {},
            onSignedOut: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('한 줄 요건'), findsOneWidget);
      expect(find.text('학점표'), findsOneWidget);
      expect(find.text('인증 요건'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('admin-section-ruleSet')),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('rule-view-grid')));
      await tester.tap(find.byKey(const ValueKey('rule-view-grid')));
      await tester.pumpAndSettle();
      expect(find.text('학점표 저장 불가 · 연결 전'), findsOneWidget);
      expect(find.byKey(const ValueKey('admin-section-ruleSet')), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('rule-view-cert')));
      await tester.tap(find.byKey(const ValueKey('rule-view-cert')));
      await tester.pumpAndSettle();
      expect(find.text('인증 요건 저장 불가 · 연결 전'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('rule-view-line')));
      await tester.tap(find.byKey(const ValueKey('rule-view-line')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('admin-section-ruleSet')),
        findsOneWidget,
      );
    },
  );
}
