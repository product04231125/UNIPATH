import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/admin/admin_fixture.dart';
import 'package:university_path_frontend/features/admin/admin_models.dart';
import 'package:university_path_frontend/features/admin/admin_repository.dart';
import 'package:university_path_frontend/features/admin/admin_workspace.dart';
import 'package:university_path_frontend/features/auth/app_role.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';

void main() {
  testWidgets('registering a rule set makes its draft selectable and saves the rule source URL', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1440, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = FakeAdminRepository(seed: [
      ...adminFixture(),
      AdminRecord(id: 'foreign', kind: AdminKind.ruleSet, values: {'name': '타 학교 묶음', 'institutionId': 'school-b'}),
      AdminRecord(id: 'applied', kind: AdminKind.ruleSet, status: 'applied', values: {'name': '이미 적용된 묶음', 'institutionId': 'school-a'}),
    ]);
    addTearDown(repo.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminWorkspace(
      repository: repo, role: AppRole.superAdmin, path: '/admin/rules', initialSchoolId: 'school-a',
      onNavigate: (_) {}, onSignedOut: () {},
    ))));
    await tester.pumpAndSettle();
    final group = find.byKey(const ValueKey('admin-frame-ruleSet'));
    final rule = find.byKey(const ValueKey('admin-frame-rule'));
    Finder field(Finder frame, String key) => find.descendant(of: frame, matching: find.byKey(ValueKey('admin-field-$key')));
    Future<void> enter(Finder frame, String key, String value) async {
      final input = field(frame, key);
      await tester.ensureVisible(input);
      await tester.enterText(input, value);
      await tester.pumpAndSettle();
    }
    final picker = field(rule, 'ruleSetId');
    expect(tester.widget<AnchoredSelectField<String>>(picker).options.map((o) => o.value), ['']);
    expect(find.textContaining('선택할 초안이 없습니다.'), findsOneWidget);
    await enter(group, 'name', '2026 공통 요건');
    FocusManager.instance.primaryFocus?.unfocus();
    final register = find.descendant(of: group, matching: find.widgetWithText(FilledButton, '등록'));
    await tester.ensureVisible(register);
    await tester.tap(register);
    await tester.pumpAndSettle();
    final saved = repo.records.singleWhere((r) => r.name == '2026 공통 요건');
    final options = tester.widget<AnchoredSelectField<String>>(picker).options;
    expect(options.map((o) => o.value), ['', saved.id]);
    expect(find.textContaining('같은 학교의 규칙 묶음 초안만 선택합니다.'), findsOneWidget);
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text(options.last.label).last);
    await tester.pumpAndSettle();
    expect(tester.widget<AnchoredSelectField<String>>(picker).value, saved.id);
    await enter(rule, 'name', '필수 활동 확인');
    await enter(rule, 'definition', '학교 규정을 확인합니다.');
    final type = field(rule, 'ruleType');
    tester.widget<AnchoredSelectField<String>>(type).onChanged('custom');
    await tester.pumpAndSettle();
    expect(find.textContaining('학생 화면에는 이 주소를 표시하지 않습니다'), findsOneWidget);
    await enter(rule, 'sourceUrl', 'https://school.example.invalid/regulations');
    FocusManager.instance.primaryFocus?.unfocus();
    final save = find.descendant(of: rule, matching: find.widgetWithText(FilledButton, '요건 설명 저장'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final savedRule = repo.records.singleWhere((r) => r.kind == AdminKind.rule);
    expect(savedRule.value('ruleSetId'), saved.id);
    expect(savedRule.value('institutionId'), 'school-a');
    expect(savedRule.value('sourceUrl'), 'https://school.example.invalid/regulations');
    expect(tester.takeException(), isNull);
  });
}
