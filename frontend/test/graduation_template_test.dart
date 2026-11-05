import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/admin/admin_models.dart';
import 'package:university_path_frontend/features/admin/admin_repository.dart';
import 'package:university_path_frontend/features/admin/admin_workspace.dart';
import 'package:university_path_frontend/features/admin/admin_rule_execution_panel.dart';
import 'package:university_path_frontend/features/admin/graduation_certification.dart';
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
  test(
    'credit grid copy keeps IDs unique and leaves sparse source unchanged',
    () {
      final grid = GraduationCreditGrid(
        admissionYear: '2026',
        departmentId: 'dept-cs',
        groups: [
          for (var i = 0; i < 100; i++)
            GraduationCreditColumnGroup(id: 'g$i', label: '묶음 $i'),
        ],
        columns: [
          for (var i = 0; i < 100; i++)
            GraduationCreditColumn(id: 'c$i', label: '열 $i', groupId: 'g$i'),
        ],
        rows: [GraduationCreditRow(id: 'r1', label: '경로')],
      );
      final copy = copyCreditGrid(grid);
      expect(copy.groups.map((g) => g.id).toSet(), hasLength(100));
      expect(copy.columns.map((c) => c.id).toSet(), hasLength(100));
      for (var i = 0; i < 100; i++) {
        expect(copy.columns[i].groupId, copy.groups[i].id);
      }
      copy.cellFor(copy.rows.single.id, copy.columns.first.id).value = '9';
      expect(grid.cells, isEmpty);
    },
  );

  test('certification IDs stay unique during rapid creation', () {
    expect({
      for (var i = 0; i < 1000; i++) GraduationCertificationDraft.newId(),
    }, hasLength(1000));
  });

  testWidgets(
    'credit draft isolates initial data and detects edit and revert',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final grid = GraduationCreditGrid(
        admissionYear: '2026',
        departmentId: 'dept-cs',
      );
      final key = GlobalKey<GraduationCreditGridPageState>();
      await tester.pumpWidget(
        host(
          GraduationCreditGridPage(
            key: key,
            schoolName: '학교',
            departments: departments(),
            initial: grid,
          ),
        ),
      );
      expect(key.currentState!.dirty, isFalse);
      await tester.enterText(
        find.byKey(const ValueKey('credit-grid-year')),
        '2027',
      );
      expect(key.currentState!.dirty, isTrue);
      expect(grid.admissionYear, '2026');
      await tester.enterText(
        find.byKey(const ValueKey('credit-grid-year')),
        '2026',
      );
      expect(key.currentState!.dirty, isFalse);
    },
  );

  testWidgets(
    'certification draft isolates nested initial data and tracks revert',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final nested = GraduationCertificationGroup(id: 'child', label: '안쪽');
      final initial = GraduationCertificationDraft(
        departmentId: 'dept-cs',
        groups: [
          GraduationCertificationGroup(id: 'parent', groups: [nested]),
        ],
      );
      final key = GlobalKey<GraduationCertificationPageState>();
      await tester.pumpWidget(
        host(
          GraduationCertificationPage(
            key: key,
            schoolName: '학교',
            departments: departments(),
            initial: initial,
            scrollable: true,
          ),
        ),
      );
      expect(key.currentState!.dirty, isFalse);
      final field = find.byKey(const ValueKey('certification-group-child'));
      await tester.enterText(field, '수정');
      expect(key.currentState!.dirty, isTrue);
      expect(nested.label, '안쪽');
      await tester.enterText(field, '안쪽');
      expect(key.currentState!.dirty, isFalse);
    },
  );

  testWidgets('cell kind changes clear the displayed and previewed number', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final grid = GraduationCreditGrid(
      admissionYear: '2026',
      departmentId: 'dept-cs',
      columns: [GraduationCreditColumn(id: 'c', label: '학점')],
      rows: [GraduationCreditRow(id: 'r', label: '경로')],
    );
    grid.cellFor('r', 'c')
      ..kind = GraduationCreditCellKind.number
      ..value = '7';
    final key = GlobalKey<GraduationCreditGridPageState>();
    await tester.pumpWidget(
      host(
        GraduationCreditGridPage(
          key: key,
          schoolName: '학교',
          departments: departments(),
          initial: grid,
          scrollable: true,
        ),
      ),
    );
    expect(key.currentState!.dirty, isFalse);
    await tester.tap(find.byKey(const ValueKey('credit-grid-kind-r/c-empty')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('credit-grid-kind-r/c-number')));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('credit-grid-cell-r/c')),
    );
    expect(field.controller!.text, isEmpty);
    expect(grid.cellFor('r', 'c').value, '7');
    await tester.enterText(
      find.byKey(const ValueKey('credit-grid-cell-r/c')),
      '8',
    );
    await tester.tap(find.byKey(const ValueKey('credit-grid-preview')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('template-preview-dialog')),
        matching: find.text('8'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('execution draft resets when school context changes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = FakeAdminRepository();
    addTearDown(repo.dispose);
    final key = GlobalKey<AdminRuleExecutionPanelState>();
    Widget panel(String school) => host(
      AdminRuleExecutionPanel(
        key: key,
        repository: repo,
        actorId: '',
        schoolId: school,
        ruleType: 'credits',
        description: '',
        rule: null,
        metadataDirty: false,
        onBusy: (_) {},
        onChanged: () {},
      ),
    );
    await tester.pumpWidget(panel('school-a'));
    await tester.enterText(find.byType(TextFormField).first, '30');
    expect(key.currentState!.dirty, isTrue);
    await tester.pumpWidget(panel('school-b'));
    expect(key.currentState!.draft.values, isEmpty);
    expect(key.currentState!.dirty, isFalse);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .initialValue,
      isEmpty,
    );
  });

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

  testWidgets('invalid pick-N shows an error and still opens the preview', (
    tester,
  ) async {
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
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'certification-choice-',
            ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, '택 N'));
    await tester.pumpAndSettle();

    const overEmpty = '기준은 0개입니다. 택하는 개수는 기준 수를 넘지 않게 입력하세요.';
    expect(find.text(overEmpty), findsOneWidget);
    final preview = find.byKey(const ValueKey('certification-preview'));
    expect(tester.widget<OutlinedButton>(preview).onPressed, isNotNull);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.text('인증 요건 미리보기'), findsOneWidget);
    expect(find.text('묶음 (택 1)'), findsOneWidget);
    expect(find.text(overEmpty), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('template-preview-close')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('기준 추가'));
    await tester.pump();
    expect(find.text(overEmpty), findsNothing);

    final pick = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'certification-pick-',
          ),
    );
    await tester.enterText(pick, '');
    await tester.pump();
    expect(find.text('택하는 개수를 입력하세요.'), findsOneWidget);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.text('인증 요건 미리보기'), findsOneWidget);
    expect(find.text('묶음 (택 미입력)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('template-preview-close')));
    await tester.pumpAndSettle();

    await tester.enterText(pick, '0');
    await tester.pump();
    expect(find.text('택하는 개수는 1 이상의 숫자로 입력하세요.'), findsOneWidget);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.text('묶음 (택 0)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('template-preview-close')));
    await tester.pumpAndSettle();

    await tester.enterText(pick, '2');
    await tester.pump();
    const overItems = '기준은 1개입니다. 택하는 개수는 기준 수를 넘지 않게 입력하세요.';
    expect(find.text(overItems), findsOneWidget);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.text('인증 요건 미리보기'), findsOneWidget);
    expect(find.text('묶음 (택 2)'), findsOneWidget);
    expect(find.text(overItems), findsOneWidget);
  });

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
      expect(
        find.widgetWithText(FilledButton, '한 줄 요건'),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, '학점표'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '인증 요건'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('admin-section-ruleSet')),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('rule-view-grid')));
      await tester.tap(find.byKey(const ValueKey('rule-view-grid')));
      await tester.pumpAndSettle();
      expect(find.text('학점표 저장 불가 · 연결 전'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '학점표'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '한 줄 요건'), findsOneWidget);
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
