import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/admin/admin_models.dart';
import 'package:university_path_frontend/features/admin/admin_repository.dart';
import 'package:university_path_frontend/features/admin/admin_workspace.dart';
import 'package:university_path_frontend/features/admin/graduation_credit_grid.dart';
import 'package:university_path_frontend/features/admin/graduation_credit_grid_page.dart';
import 'package:university_path_frontend/features/admin/school_classification_drafts.dart';
import 'package:university_path_frontend/features/auth/app_role.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'course registration keeps classification ID links when editing the saved record',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = FakeAdminRepository();
      addTearDown(repo.dispose);
      final drafts = SchoolClassificationDrafts();
      addTearDown(drafts.dispose);
      drafts.save(
        schoolId: 'school-a',
        kind: SchoolClassificationKind.track,
        code: 'TRACK',
        name: '단일전공',
      );
      final category = drafts.entries('school-a').single;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminWorkspace(
              repository: repo,
              classificationDrafts: drafts,
              role: AppRole.superAdmin,
              path: '/admin/curricula',
              initialSchoolId: 'school-a',
              onNavigate: (_) {},
              onSignedOut: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('학교별 교육과정 분류'), findsOneWidget);
      final frame = find.byKey(const ValueKey('admin-frame-course'));
      final picker = find.descendant(
        of: frame,
        matching: find.byWidgetPredicate(
          (w) => w is AnchoredSelectField<String> && w.label == '이수 경로',
        ),
      );
      await tester.ensureVisible(picker);
      tester.widget<AnchoredSelectField<String>>(picker).onChanged(category.id);
      await tester.pumpAndSettle();
      for (final entry in {
        'name': '표시용 과목명',
        'code': 'C01',
        'credits': '3',
      }.entries) {
        final input = find.descendant(
          of: frame,
          matching: find.byKey(ValueKey('admin-field-${entry.key}')),
        );
        await tester.ensureVisible(input);
        await tester.enterText(input, entry.value);
        await tester.pump();
      }
      for (final entry in {'curriculumId': 'school-a-curr', 'category': 'major', 'required': 'true'}.entries) {
        final select = find.descendant(of: frame, matching: find.byKey(ValueKey('admin-field-${entry.key}')));
        tester.widget<AnchoredSelectField<String>>(select).onChanged(entry.value);
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const ValueKey('admin-frame-curriculumCourse')), findsNothing);
      expect(find.byKey(const ValueKey('admin-frame-curriculum')), findsNothing);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final save = find.descendant(
        of: frame,
        matching: find.widgetWithText(FilledButton, '등록'),
      );
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final record = repo.records.singleWhere(
        (r) => r.kind == AdminKind.course && r.name == '표시용 과목명',
      );
      expect(
        drafts.binding('school-a', 'course:${record.id}')[category.kind],
        category.id,
      );
      final link = repo.records.singleWhere((r) => r.kind == AdminKind.curriculumCourse && r.value('courseId') == record.id);
      expect(link.value('curriculumId'), 'school-a-curr');
      expect(link.value('category'), 'major');
      expect(link.value('required'), 'true');
      final row = find.byKey(ValueKey('admin-row-${record.id}'));
      final edit = find.descendant(
        of: row,
        matching: find.widgetWithText(OutlinedButton, '수정'),
      );
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnchoredSelectField<String>>(picker).value,
        category.id,
      );
      final curriculum = find.descendant(of: frame, matching: find.byKey(const ValueKey('admin-field-curriculumId')));
      expect(tester.widget<AnchoredSelectField<String>>(curriculum).value, 'school-a-curr');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'credit column and track bindings survive display edits and copy by ID',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final drafts = SchoolClassificationDrafts();
      addTearDown(drafts.dispose);
      drafts.save(
        schoolId: 'a',
        kind: SchoolClassificationKind.category,
        code: 'C',
        name: '같은 이름',
      );
      drafts.save(
        schoolId: 'a',
        kind: SchoolClassificationKind.track,
        code: 'T',
        name: '같은 이름',
      );
      final category = drafts
          .entries('a', SchoolClassificationKind.category)
          .single;
      final track = drafts.entries('a', SchoolClassificationKind.track).single;
      final grid = GraduationCreditGrid(
        admissionYear: '2026',
        departmentId: 'dept',
        columns: [GraduationCreditColumn(id: 'column', label: '표시 제목')],
        rows: [GraduationCreditRow(id: 'row', label: '표시 경로')],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GraduationCreditGridPage(
              schoolName: '합성 학교',
              departments: [
                AdminRecord(
                  id: 'dept',
                  kind: AdminKind.department,
                  values: {'name': '학과', 'institutionId': 'a'},
                ),
              ],
              initial: grid,
              institutionId: 'a',
              classificationDrafts: drafts,
              scrollable: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> select(String key, String id) async {
        final field = find.byKey(ValueKey(key));
        await tester.ensureVisible(field);
        tester.widget<AnchoredSelectField<String>>(field).onChanged(id);
        await tester.pumpAndSettle();
      }

      await select(
        'classification-binding-credit-column:column-category',
        category.id,
      );
      await select('classification-binding-credit-row:row-track', track.id);
      final label = find.byKey(const ValueKey('credit-grid-row-row'));
      await tester.ensureVisible(label);
      await tester.enterText(label, '자유롭게 다른 제목');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(drafts.binding('a', 'credit-row:row')[track.kind], track.id);
      final copy = find.byKey(const ValueKey('credit-grid-copy-year'));
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await tester.pumpAndSettle();
      final bindings = (drafts.exportSchool('a')['bindings'] as Map).values
          .toList();
      expect(bindings, contains(equals({'category': category.id})));
      expect(bindings, contains(equals({'track': track.id})));
      expect(drafts.binding('a', 'credit-column:column'), isEmpty);
      expect(drafts.binding('a', 'credit-row:row'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
