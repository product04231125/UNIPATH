import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/records/course/course_pick_options.dart';
import 'package:university_path_frontend/features/records/personal_record_form.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';

class Catalog implements ApiGateway {
  bool multiple = false;
  @override Future<Map<String, dynamic>?> request(String method, String path, [Map<String, Object?>? body]) async {
    if (path.startsWith('catalog/courses?')) {
      return {'items': [for (final id in ['a', 'b']) {
        'id': id, 'version': 1, 'institution_id': 'school', 'name': '같은 이름',
        'code': 'CODE-$id', 'credits': '3',
      }], 'next_cursor': null};
    }
    return {'items': [for (final id in ['a', 'b']) {
      'id': 'link-$id', 'version': 1, 'institution_id': 'school', 'name': '과목 연결',
      'curriculum_id': 'curriculum', 'course_id': id, 'category': id == 'a' ? 'major' : 'general', 'required': id == 'a',
    }, if (multiple) {
      'id': 'other-link', 'version': 1, 'institution_id': 'school', 'name': '다른 교육과정',
      'curriculum_id': 'other', 'course_id': 'a', 'category': 'other', 'required': false,
    }], 'next_cursor': null};
  }
}
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('same names preserve separate source IDs and ambiguous curricula never overwrite classification', () async {
    final gateway = Catalog();
    final repo = PersonalRecordRepository(PersonalRecordKind.course);
    Future<List<CoursePickOption>> load([String? curriculum]) => loadCoursePickOptions(
      courseRepository: repo, studentApi: StudentApi(gateway, ownerId: 'owner'), institutionId: 'school', curriculumId: curriculum,
    );
    final options = await load('curriculum');
    expect(options.map((o) => o.id), ['catalog:a', 'catalog:b']);
    expect(options.first.category, 'major');
    expect(options.first.requiredCourse, isTrue);
    expect(options.last.requiredCourse, isFalse);
    expect(options.first.curriculumCourseId, 'link-a');
    expect(options.first.matches(PersonalRecord(id: 'new', values: {'title': '같은 이름', 'courseCode': 'CODE-a'})), isFalse);
    gateway.multiple = true;
    final ambiguous = (await load()).first;
    expect(ambiguous.category, isEmpty);
    expect(ambiguous.requiredCourse, isNull);
    expect(ambiguous.curriculumCourseId, isNull);
    expect((await load('curriculum')).first.curriculumCourseId, 'link-a');
  });
  testWidgets('picking a managed course applies category and required status without another student input', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = PersonalRecordRepository(PersonalRecordKind.course);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () => showPersonalRecordForm(context: context, kind: PersonalRecordKind.course, repository: repo,
        addLabel: '수강 과목 추가', studentApi: StudentApi(Catalog(), ownerId: 'owner'), institutionId: 'school', curriculumId: 'curriculum'),
      child: const Text('열기'),
    )))));
    await tester.tap(find.text('열기')); await tester.pumpAndSettle();
    final picker = find.byKey(const ValueKey('record-select-course'));
    await tester.tap(picker); await tester.pumpAndSettle();
    final label = tester.widget<AnchoredSelectField<String>>(picker).options.firstWhere((o) => o.value == 'catalog:a').label;
    await tester.tap(find.text(label).last); await tester.pumpAndSettle();
    expect(find.textContaining('학교 교육과정에 연결된 기준'), findsOneWidget);
    expect(find.textContaining('전공 · 필수'), findsWidgets);
    expect(find.byKey(const ValueKey('record-field-category')), findsNothing);
    final term = find.byWidgetPredicate((w) => w is AnchoredSelectField<String> && w.label.startsWith('학기'));
    final field = tester.widget<AnchoredSelectField<String>>(term);
    field.onChanged(field.options.firstWhere((o) => o.value.isNotEmpty).value);
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, '내 기록에 저장');
    await tester.ensureVisible(save); await tester.tap(save); await tester.pumpAndSettle();
    expect(repo.records.single.value('category'), 'major');
    expect(repo.records.single.value('courseCode'), 'CODE-a');
    expect(tester.takeException(), isNull);
  });
}
