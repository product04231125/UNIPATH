import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/admin/admin_models.dart';
import 'package:university_path_frontend/features/admin/admin_repository.dart';
import 'package:university_path_frontend/features/admin/admin_editor.dart';
import 'package:university_path_frontend/features/admin/admin_workspace.dart';
import 'package:university_path_frontend/features/auth/app_role.dart';
import 'package:university_path_frontend/shared/widgets/input_dialog.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';

Widget host(Widget child, {double scale = 1}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: child),
);

Future<void> setField(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(ValueKey('admin-field-$key'));
  await tester.ensureVisible(finder);
  if (tester.widget(finder) is AnchoredSelectField<String>) {
    tester.widget<AnchoredSelectField<String>>(finder).onChanged(value);
  } else {
    await tester.enterText(finder, value);
  }
  await tester.pumpAndSettle();
}

Future<void> openEditor(
  WidgetTester tester,
  FakeAdminRepository repo,
  AdminKind kind, {
  AdminRecord? record,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    host(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showInputDialog<void>(
            context: context,
            builder: (_) => AdminEditor(
              repository: repo,
              actorId: 'super-admin',
              kind: kind,
              schoolId: 'school-a',
              record: record,
            ),
          ),
          child: const Text('열기'),
        ),
      ),
      scale: scale,
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('admin labels stay above their controls', (tester) async {
    final repo = FakeAdminRepository();
    await openEditor(tester, repo, AdminKind.department);
    final input = find.byKey(const ValueKey('admin-field-name'));
    final label = find.text('이름 *');
    expect(
      tester.getBottomLeft(label).dy,
      lessThan(tester.getTopLeft(input).dy),
    );
    final editable = find.descendant(
      of: input,
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(editable).decoration?.labelText, isNull);
    final school = tester.widget<AnchoredSelectField<String>>(
      find.byKey(const ValueKey('admin-field-institutionId')),
    );
    expect(school.externalLabel, isTrue);
    await tester.enterText(input, '작성 중 학과');
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.text('작성한 내용을 폐기할까요?'), findsOneWidget);
  });
  testWidgets(
    'school search selects one allowed school and cancellation preserves target',
    (tester) async {
      final repo = FakeAdminRepository();
      addTearDown(repo.dispose);
      await tester.pumpWidget(
        host(
          AdminWorkspace(
            repository: repo,
            role: AppRole.superAdmin,
            path: '/admin/schools',
            onNavigate: (_) {},
            onSignedOut: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final selector = find.byKey(const ValueKey('admin-school-selector'));
      expect(
        find.byKey(const ValueKey('admin-search-school-a-institution')),
        findsNothing,
      );
      await tester.tap(selector);
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('select-search-input'));
      await tester.enterText(search, '대학 B');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(MenuItemButton, '합성 대학 A'), findsNothing);
      await tester.tap(find.widgetWithText(MenuItemButton, '합성 대학 B'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnchoredSelectField<String>>(selector).value,
        'school-b',
      );
      expect(search, findsNothing);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.enterText(search, '없는 학교');
      await tester.pumpAndSettle();
      expect(find.text('검색에 맞는 항목이 없습니다.'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnchoredSelectField<String>>(selector).value,
        'school-b',
      );
      expect(search, findsNothing);
      final trigger = tester.widget<InkWell>(
        find.descendant(of: selector, matching: find.byType(InkWell)).first,
      );
      expect(trigger.focusNode!.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('detail actions retain apply failures and immutable versions', (
    tester,
  ) async {
    var failApply = true;
    final repo = FakeAdminRepository(
      beforeOperation: (op) async {
        if (op == 'apply' && failApply) throw StateError('합성 적용 실패');
      },
    );
    addTearDown(repo.dispose);
    await repo.save(
      'super-admin',
      AdminRecord(
        id: 'detail-doc',
        kind: AdminKind.document,
        values: {
          'name': '상세 검토 문서',
          'institutionId': 'school-a',
          'documentType': 'graduation',
          'sourceUrl': 'https://example.org/detail',
        },
      ),
    );
    await tester.pumpWidget(
      host(
        AdminWorkspace(
          repository: repo,
          role: AppRole.superAdmin,
          path: '/admin/documents/detail-doc',
          onNavigate: (_) {},
          onSignedOut: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('상세'), findsNothing);
    expect(find.text('수정'), findsOneWidget);
    await tester.tap(find.text('검토·적용'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('초안 적용'));
    await tester.pumpAndSettle();
    expect(find.text('합성 적용 실패'), findsOneWidget);
    expect(repo.find('detail-doc')!.status, 'draft');
    failApply = false;
    await tester.tap(find.text('검토·적용'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('초안 적용'));
    await tester.pumpAndSettle();
    expect(find.text('수정'), findsNothing);
    expect(find.text('합성 적용 실패'), findsNothing);
    expect(find.text('버전 1 · 목업 적용'), findsOneWidget);
    await tester.tap(find.text('새 버전 초안'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '새 버전 초안'),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.find('detail-doc')!.status, 'applied');
    expect(repo.records.where((r) => r.kind == AdminKind.document).length, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets('list filters preserve scope and reset when school changes', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    addTearDown(repo.dispose);
    for (final (id, school) in [
      ('alpha', 'a'),
      ('beta', 'a'),
      ('gamma', 'b'),
    ]) {
      await repo.save(
        'super-admin',
        AdminRecord(
          id: id,
          kind: AdminKind.document,
          values: {
            'name': id,
            'institutionId': 'school-$school',
            'documentType': 'graduation',
            'sourceUrl': 'https://example.org/$id',
          },
        ),
      );
    }
    await repo.apply('super-admin', 'beta');
    await tester.pumpWidget(
      host(
        AdminWorkspace(
          repository: repo,
          role: AppRole.superAdmin,
          path: '/admin/documents',
          onNavigate: (_) {},
          onSignedOut: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);
    expect(find.text('gamma'), findsNothing);
    tester
        .widget<AnchoredSelectField<String>>(
          find.byKey(const ValueKey('admin-status-document')),
        )
        .onChanged('draft');
    await tester.pumpAndSettle();
    expect(find.text('beta'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('admin-search-school-a-document')),
      '없는 항목',
    );
    await tester.pumpAndSettle();
    expect(find.text('alpha'), findsNothing);
    expect(find.textContaining('검색·필터에 맞는 항목'), findsOneWidget);
    tester
        .widget<AnchoredSelectField<String>>(
          find.byKey(const ValueKey('admin-school-selector')),
        )
        .onChanged('school-b');
    await tester.pumpAndSettle();
    expect(find.text('gamma'), findsOneWidget);
    expect(
      tester
          .widget<AnchoredSelectField<String>>(
            find.byKey(const ValueKey('admin-status-document')),
          )
          .value,
      '',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('overview scopes drafts and recent changes and opens next task', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    addTearDown(repo.dispose);
    for (final school in ['a', 'b']) {
      await repo.save(
        'super-admin',
        AdminRecord(
          id: 'doc-$school',
          kind: AdminKind.document,
          values: {
            'name': '검토 문서 $school',
            'institutionId': 'school-$school',
            'documentType': 'graduation',
            'sourceUrl': 'https://example.org/$school',
          },
        ),
      );
    }
    String? target;
    await tester.pumpWidget(
      host(
        AdminWorkspace(
          repository: repo,
          role: AppRole.superAdmin,
          path: '/admin/overview',
          onNavigate: (path) => target = path,
          onSignedOut: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('확인할 초안 1개'), findsOneWidget);
    expect(find.text('검토 문서 a'), findsNWidgets(2));
    expect(find.text('검토 문서 b'), findsNothing);
    tester
        .widget<AnchoredSelectField<String>>(
          find.byType(AnchoredSelectField<String>),
        )
        .onChanged('school-b');
    await tester.pumpAndSettle();
    expect(find.text('검토 문서 a'), findsNothing);
    expect(find.text('검토 문서 b'), findsNWidgets(2));
    await tester.tap(find.text('검토 문서 b').first);
    expect(target, '/admin/documents/doc-b');
    final register = find.text('공식 문서 등록');
    await tester.ensureVisible(register);
    await tester.pumpAndSettle();
    await tester.tap(register);
    await tester.pumpAndSettle();
    expect(find.byType(AdminEditor), findsOneWidget);
    expect(
      tester
          .widget<AnchoredSelectField<String>>(
            find.byKey(const ValueKey('admin-field-institutionId')),
          )
          .value,
      'school-b',
    );
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final compact in [false, true]) {
    testWidgets('shared shell retains selected navigation compact=$compact', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(
        compact ? const Size(480, 520) : const Size(1440, 900),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = FakeAdminRepository();
      addTearDown(repo.dispose);
      var path = '/admin/overview';
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, update) => AdminWorkspace(
              repository: repo,
              role: AppRole.schoolAdmin,
              path: path,
              onNavigate: (next) => update(() => path = next),
              onSignedOut: () {},
            ),
          ),
          scale: compact ? 2 : 1,
        ),
      );
      await tester.pumpAndSettle();
      if (compact) {
        await tester.tap(find.byTooltip('관리자 메뉴 열기'));
        await tester.pumpAndSettle();
      }
      final overview = find.byKey(const ValueKey('admin-menu-/admin/overview'));
      expect(tester.widget<ListTile>(overview).selected, isTrue);
      expect(
        find.byKey(const ValueKey('admin-menu-/admin/accounts')),
        findsNothing,
      );
      final documents = find.byKey(
        const ValueKey('admin-menu-/admin/documents'),
      );
      await tester.ensureVisible(documents);
      await tester.pumpAndSettle();
      await tester.tap(documents);
      await tester.pumpAndSettle();
      expect(path, '/admin/documents');
      if (compact) {
        expect(documents, findsNothing);
        await tester.tap(find.byTooltip('관리자 메뉴 열기'));
        await tester.pumpAndSettle();
      }
      expect(tester.widget<ListTile>(documents).selected, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'school context follows direct details and switching leaves detail',
    (tester) async {
      final repo = FakeAdminRepository();
      addTearDown(repo.dispose);
      var path = '/admin/schools/school-b';
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, update) => AdminWorkspace(
              repository: repo,
              role: AppRole.superAdmin,
              path: path,
              onNavigate: (next) => update(() => path = next),
              onSignedOut: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      AnchoredSelectField<String> selector() =>
          tester.widget<AnchoredSelectField<String>>(
            find.byType(AnchoredSelectField<String>),
          );
      expect(selector().value, 'school-b');
      selector().onChanged('school-a');
      await tester.pumpAndSettle();
      expect(path, '/admin/schools');
      expect(selector().value, 'school-a');
      expect(find.text('목록으로'), findsNothing);
      expect(find.text('합성 대학 B'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'school selector restricts choices and document opens external confirmation',
    (tester) async {
      final repo = FakeAdminRepository();
      await repo.save(
        'super-admin',
        AdminRecord(
          id: 'd',
          kind: AdminKind.document,
          values: {
            'name': '합성 원문',
            'institutionId': 'school-a',
            'documentType': 'graduation',
            'sourceUrl': 'https://example.org/document',
          },
        ),
      );
      await tester.pumpWidget(
        host(
          AdminWorkspace(
            repository: repo,
            role: AppRole.schoolAdmin,
            path: '/admin/documents/d',
            onNavigate: (_) {},
            onSignedOut: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final school = tester.widget<AnchoredSelectField<String>>(
        find.byType(AnchoredSelectField<String>),
      );
      expect(school.options.map((o) => o.value).toList(), ['school-a']);
      await tester.ensureVisible(find.text('원문 열기 · 외부 열기'));
      await tester.tap(find.text('원문 열기 · 외부 열기'));
      await tester.pumpAndSettle();
      expect(find.text('https://example.org/document'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('admin flows apply draft, preserve version and show details', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    await repo.save(
      'school-admin',
      AdminRecord(
        id: 'r',
        kind: AdminKind.rule,
        values: {
          'name': '검토할 합성 요건',
          'institutionId': 'school-a',
          'ruleType': 'credits',
          'definition': '합성 조건',
        },
      ),
    );
    var path = '/admin/rules';
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, update) => AdminWorkspace(
            repository: repo,
            role: AppRole.schoolAdmin,
            path: path,
            onNavigate: (v) => update(() => path = v),
            onSignedOut: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('검토·적용'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('검토·적용'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('초안 적용'));
    await tester.pumpAndSettle();
    expect(repo.find('r')!.status, 'applied');
    await tester.ensureVisible(find.text('새 버전 초안'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('새 버전 초안'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '새 버전 초안'),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.records.where((r) => r.kind == AdminKind.rule).length, 2);
    expect(repo.find('r')!.status, 'applied');
    await tester.ensureVisible(find.text('상세').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('상세').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('규칙 종류: 학점'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('admin flows delete shows references and preserves source', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    await tester.pumpWidget(
      host(
        AdminWorkspace(
          repository: repo,
          role: AppRole.superAdmin,
          path: '/admin/schools',
          onNavigate: (_) {},
          onSignedOut: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('연결된 항목'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();
    expect(find.text('연결된 데이터가 있습니다. 참조를 먼저 정리하세요.'), findsOneWidget);
    expect(repo.find('school-a'), isNotNull);
  });
  testWidgets(
    'admin flows curriculum course relation and narrow document editor',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 520));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = FakeAdminRepository();
      await repo.save(
        'super-admin',
        AdminRecord(
          id: 'course',
          kind: AdminKind.course,
          values: {
            'name': '합성 연결 과목',
            'institutionId': 'school-a',
            'code': 'C1',
            'credits': '3',
          },
        ),
      );
      await openEditor(tester, repo, AdminKind.curriculumCourse, scale: 2);
      for (final entry in {
        'name': '합성 연결',
        'curriculumId': 'school-a-curr',
        'courseId': 'course',
        'category': 'major',
        'required': 'true',
      }.entries) {
        await setField(tester, entry.key, entry.value);
      }
      await tester.tap(find.text('목업에 저장'));
      await tester.pumpAndSettle();
      expect(
        repo.records.any((r) => r.kind == AdminKind.curriculumCourse),
        isTrue,
      );
      await openEditor(tester, repo, AdminKind.document, scale: 2);
      await setField(tester, 'name', '합성 문서');
      await setField(tester, 'documentType', 'graduation');
      await setField(tester, 'sourceUrl', 'https://example.org/document');
      expect(find.text('취소').hitTestable(), findsOneWidget);
      expect(find.text('목업에 저장').hitTestable(), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('내용 폐기'));
      await tester.pumpAndSettle();
      expect(find.byType(InputDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('admin flows user status and scope revoke use protected forms', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    await openEditor(
      tester,
      repo,
      AdminKind.account,
      record: repo.find('sample-user'),
    );
    await setField(tester, 'accountStatus', 'suspended');
    await tester.tap(find.text('목업에 저장'));
    await tester.pumpAndSettle();
    expect(repo.active('sample-user'), isFalse);
    await tester.pumpWidget(
      host(
        AdminWorkspace(
          repository: repo,
          role: AppRole.superAdmin,
          path: '/admin/accounts',
          onNavigate: (_) {},
          onSignedOut: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('범위 회수'));
    await tester.tap(find.text('범위 회수'));
    await tester.pumpAndSettle();
    await setField(tester, 'reason', '합성 회수');
    await tester.tap(find.widgetWithText(FilledButton, '범위 회수'));
    await tester.pumpAndSettle();
    expect(repo.find('scope-a')!.status, 'revoked');
    expect(repo.find('scope-a')!.value('reason'), '합성 회수');
  });
  final inputs = <AdminKind, Map<String, String>>{
    AdminKind.ruleSet: {'name': '합성 규칙 묶음'},
    AdminKind.institution: {'name': '합성 신규 대학'},
    AdminKind.department: {'name': '합성 신규 학과', 'code': 'NEW'},
    AdminKind.curriculum: {
      'name': '합성 신규 교육과정',
      'departmentId': 'school-a-dept',
      'year': '2027',
    },
    AdminKind.course: {'name': '합성 과목', 'code': 'C1', 'credits': '3'},
    AdminKind.rule: {
      'name': '합성 요건',
      'ruleType': 'credits',
      'definition': '합성 조건 설명',
    },
    AdminKind.document: {
      'name': '합성 문서',
      'documentType': 'graduation',
      'sourceUrl': 'https://example.org/document',
    },
    AdminKind.scope: {
      'name': '합성 부여',
      'userId': 'sample-user',
      'reason': '합성 테스트',
    },
  };
  for (final entry in inputs.entries) {
    testWidgets('${entry.key.name} form creates edits and protects discard', (
      tester,
    ) async {
      final repo = FakeAdminRepository();
      await openEditor(tester, repo, entry.key);
      for (final field in entry.value.entries) {
        await setField(tester, field.key, field.value);
      }
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(find.text('작성한 내용을 폐기할까요?'), findsOneWidget);
      await tester.tap(find.text('계속 작성'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('admin-field-name')),
            )
            .controller!
            .text,
        entry.value['name'],
      );
      await tester.tap(find.text('목업에 저장'));
      await tester.pumpAndSettle();
      expect(find.byType(InputDialog), findsNothing);
      final created = repo.records.singleWhere(
        (r) => r.name == entry.value['name'],
      );
      await openEditor(tester, repo, entry.key, record: created);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(find.byType(InputDialog), findsNothing);
      await openEditor(tester, repo, entry.key, record: created);
      await setField(tester, 'name', '수정 ${created.name}');
      await tester.tap(find.text('목업에 저장'));
      await tester.pumpAndSettle();
      expect(repo.find(created.id)!.name, '수정 ${created.name}');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'save failure preserves draft and busy blocks cancel then retries',
    (tester) async {
      final gate = Completer<void>();
      var attempt = 0;
      final repo = FakeAdminRepository(
        beforeOperation: (op) async {
          if (op == 'save' && attempt++ == 0) {
            await gate.future;
            throw StateError('합성 저장 실패');
          }
        },
      );
      await openEditor(tester, repo, AdminKind.institution);
      await setField(tester, 'name', '합성 실패 보존');
      await tester.tap(find.text('목업에 저장'));
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '취소'))
            .onPressed,
        isNull,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('합성 저장 실패'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('admin-field-name')),
            )
            .controller!
            .text,
        '합성 실패 보존',
      );
      await tester.tap(find.text('목업에 저장'));
      await tester.pumpAndSettle();
      expect(repo.records.any((r) => r.name == '합성 실패 보존'), isTrue);
    },
  );
  for (final role in [AppRole.schoolAdmin, AppRole.superAdmin]) {
    for (final path in AdminWorkspace.menus.keys) {
      testWidgets('${role.name} $path narrow 200 percent', (tester) async {
        await tester.binding.setSurfaceSize(const Size(480, 520));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          host(
            AdminWorkspace(
              role: role,
              path: path,
              onNavigate: (_) {},
              onSignedOut: () {},
            ),
            scale: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('개발용 목업 · 실제 권한 및 서버 저장 없음'), findsOneWidget);
      });
    }
  }
  testWidgets(
    'scope revocation and account suspension immediately block detail access',
    (tester) async {
      final repo = FakeAdminRepository();
      await tester.pumpWidget(
        host(
          AdminWorkspace(
            repository: repo,
            role: AppRole.schoolAdmin,
            path: '/admin/schools/school-a-dept',
            onNavigate: (_) {},
            onSignedOut: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('접근할 수 없습니다.'), findsNothing);
      await repo.revoke('super-admin', 'scope-a', '합성 회수');
      await tester.pumpAndSettle();
      expect(find.text('접근할 수 없습니다.'), findsOneWidget);
      final account = repo.find('school-admin')!;
      await repo.save(
        'super-admin',
        account.copy(values: {...account.values, 'accountStatus': 'suspended'}),
      );
      await tester.pumpAndSettle();
      expect(find.text('접근할 수 없습니다.'), findsOneWidget);
    },
  );
  testWidgets('loading fails then recovers and keyboard reaches controls', (
    tester,
  ) async {
    var fail = true;
    final repo = FakeAdminRepository(
      beforeOperation: (_) async {
        if (fail) throw StateError('합성 읽기');
      },
    );
    await tester.pumpWidget(
      host(
        AdminWorkspace(
          repository: repo,
          role: AppRole.superAdmin,
          path: '/admin/overview',
          onNavigate: (_) {},
          onSignedOut: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('다시 읽기'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('다시 읽기'));
    await tester.pumpAndSettle();
    expect(find.text('관리 가능한 학교 2개'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(FocusManager.instance.primaryFocus, isNotNull);
  });
}
