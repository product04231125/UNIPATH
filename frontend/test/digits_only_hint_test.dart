import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/admin/admin_models.dart';
import 'package:university_path_frontend/features/admin/graduation_certification.dart';
import 'package:university_path_frontend/features/admin/graduation_certification_page.dart';
import 'package:university_path_frontend/features/admin/graduation_credit_grid.dart';
import 'package:university_path_frontend/features/admin/graduation_credit_grid_page.dart';
import 'package:university_path_frontend/features/records/personal_record_form.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/shared/widgets/digits_only_hint.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

List<AdminRecord> departments() => [
  AdminRecord(
    id: 'dept-cs',
    kind: AdminKind.department,
    values: {'name': '컴퓨터공학과', 'institutionId': 'school-a'},
  ),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('course section shows red digits-only hint', (tester) async {
    final repo = PersonalRecordRepository(PersonalRecordKind.course);
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showPersonalRecordForm(
              context: context,
              kind: PersonalRecordKind.course,
              repository: repo,
              addLabel: '수강 과목 추가',
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('record-field-section')), findsOneWidget);
    expect(find.text(digitsOnlyInputHint), findsWidgets);
    final hint = tester.widget<Text>(find.text(digitsOnlyInputHint).first);
    expect(hint.style?.color, Theme.of(tester.element(find.text(digitsOnlyInputHint).first)).colorScheme.error);
  });

  testWidgets('credit grid year and number cell show digits-only hint', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final grid = GraduationCreditGrid(
      admissionYear: '2026',
      departmentId: 'dept-cs',
      columns: [GraduationCreditColumn(id: 'c', label: '열')],
      rows: [GraduationCreditRow(id: 'r', label: '경로')],
      cells: {
        'r/c': GraduationCreditCell(
          kind: GraduationCreditCellKind.number,
          value: '7',
        ),
      },
    );
    await tester.pumpWidget(
      host(
        GraduationCreditGridPage(
          schoolName: '학교',
          departments: departments(),
          initial: grid,
          scrollable: true,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('credit-grid-year')), findsOneWidget);
    expect(find.byKey(const ValueKey('credit-grid-cell-r/c')), findsOneWidget);
    expect(find.text(digitsOnlyInputHint), findsNWidgets(2));
  });

  testWidgets('certification pick count shows digits-only hint', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final draft = GraduationCertificationDraft(
      departmentId: 'dept-cs',
      groups: [
        GraduationCertificationGroup(
          id: 'g1',
          label: '그룹',
          choice: GraduationCertificationChoice.pickN,
          pickCount: 1,
          items: [
            GraduationCertificationItem(id: 'i1', label: '항목'),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      host(
        GraduationCertificationPage(
          schoolName: '학교',
          departments: departments(),
          initial: draft,
          scrollable: true,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('certification-pick-g1')), findsOneWidget);
    expect(find.text(digitsOnlyInputHint), findsOneWidget);
  });
}
