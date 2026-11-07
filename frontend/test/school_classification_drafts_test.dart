import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/admin/school_classification_drafts.dart';
import 'package:university_path_frontend/features/admin/school_classification_widgets.dart';
import 'package:university_path_frontend/shared/drafts/form_draft_store.dart';
import 'package:university_path_frontend/shared/drafts/form_draft_persistence.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';

void main() {
  test('classification IDs survive renaming, target migration and school draft roundtrips', () {
    final drafts = SchoolClassificationDrafts();
    addTearDown(drafts.dispose);
    for (final kind in SchoolClassificationKind.values) {
      drafts.save(
        schoolId: 'a',
        kind: kind,
        code: kind.name,
        name: '같은 표시 이름',
        parentId: kind == SchoolClassificationKind.subcategory
            ? drafts.entries('a', SchoolClassificationKind.category).single.id
            : null,
        requiredCourse: kind == SchoolClassificationKind.requirement
            ? true
            : null,
      );
    }
    final refs = {for (final row in drafts.entries('a')) row.kind: row.id};
    drafts.bind('a', 'course:temporary', refs);
    final category = drafts
        .entries('a', SchoolClassificationKind.category)
        .single;
    drafts.save(
      id: category.id,
      schoolId: 'a',
      kind: category.kind,
      code: 'RENAMED',
      name: '다른 표시 이름',
    );
    expect(drafts.binding('a', 'course:temporary'), refs);
    drafts.moveBinding('a', 'course:temporary', 'course:server-id');
    expect(drafts.binding('a', 'course:temporary'), isEmpty);
    expect(drafts.binding('a', 'course:server-id'), refs);
    final restored = SchoolClassificationDrafts();
    addTearDown(restored.dispose);
    restored.restoreSchool(
      'a',
      Map<String, dynamic>.from(drafts.exportSchool('a')),
    );
    expect(restored.binding('a', 'course:server-id'), refs);
    expect(restored.get(category.id)!.name, '다른 표시 이름');
    expect(() => restored.remove('a', category.id), throwsStateError);
  });
  test('foreign school links, duplicate codes and invalid restores are rejected atomically', () {
    final drafts = SchoolClassificationDrafts();
    addTearDown(drafts.dispose);
    drafts.save(
      schoolId: 'a',
      kind: SchoolClassificationKind.category,
      code: 'C',
      name: '표시',
    );
    drafts.save(
      schoolId: 'b',
      kind: SchoolClassificationKind.category,
      code: 'C',
      name: '표시',
    );
    final a = drafts.entries('a').single, b = drafts.entries('b').single;
    expect(
      () => drafts.save(schoolId: 'a', kind: a.kind, code: 'c', name: '다른 이름'),
      throwsStateError,
    );
    expect(() => drafts.bind('b', 'rule:1', {a.kind: a.id}), throwsStateError);
    expect(
      () => drafts.save(
        schoolId: 'b',
        kind: SchoolClassificationKind.subcategory,
        code: 'SUB',
        name: '하위',
        parentId: a.id,
      ),
      throwsStateError,
    );
    expect(
      () => drafts.restoreSchool(
        'b',
        Map<String, dynamic>.from(drafts.exportSchool('a')),
      ),
      throwsStateError,
    );
    final invalid = Map<String, dynamic>.from(drafts.exportSchool('b'));
    (invalid['items'] as List).single['id'] = a.id;
    expect(() => drafts.restoreSchool('b', invalid), throwsStateError);
    expect(drafts.entries('a').single.id, a.id);
    expect(drafts.entries('b').single.id, b.id);
  });
  testWidgets(
    'school section edits classification drafts and saves ID bindings without claiming server persistence',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      FormDraftStore.resetInstanceForTest(
        FormDraftStore(MemoryFormDraftPersistence()),
      );
      addTearDown(FormDraftStore.resetInstanceForTest);
      final drafts = SchoolClassificationDrafts();
      addTearDown(drafts.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  SchoolClassificationSection(
                    drafts: drafts,
                    schoolId: 'a',
                    schoolName: '합성 학교',
                  ),
                  SchoolClassificationBindingFields(
                    drafts: drafts,
                    schoolId: 'a',
                    target: 'rule:1',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('classification-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('classification-code')),
        'MAJOR',
      );
      await tester.enterText(
        find.byKey(const ValueKey('classification-name')),
        '전공',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('classification-save-draft')));
      await tester.pumpAndSettle();
      final row = drafts.entries('a').single;
      final picker = find.byKey(
        const ValueKey('classification-binding-rule:1-category'),
      );
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('전공 · MAJOR').last);
      await tester.pumpAndSettle();
      expect(
        drafts.binding('a', 'rule:1')[SchoolClassificationKind.category],
        row.id,
      );
      drafts.save(
        id: row.id,
        schoolId: 'a',
        kind: row.kind,
        code: 'MAJOR',
        name: '전공 이름 변경',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<AnchoredSelectField<String>>(picker).value, row.id);
      expect(
        tester.widget<AnchoredSelectField<String>>(picker).options.last.label,
        '전공 이름 변경 · MAJOR',
      );
      final tempSave = find.text('분류·연결 임시저장');
      await tester.ensureVisible(tempSave);
      await tester.tap(tempSave);
      await tester.pumpAndSettle();
      final saved = await FormDraftStore.instance.list(
        formDraftCollectionKey('admin.classifications.a'),
      );
      expect(saved.single.payload['bindings'], {
        'rule:1': {'category': row.id},
      });
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '학교 분류 저장 · 연결 전'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
