import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/graduation/personal_graduation_workspace.dart';
import 'package:university_path_frontend/features/graduation/personal_graduation_fields.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/personal_record_codec.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';

import 'personal_graduation_test.dart' as fixture;
import 'remote_personal_ui_test.dart' as server;
import 'support/personal_gateway.dart';
import 'support/auth_fixture.dart';
import 'support/personal_workspace_fixture.dart';

Future<void> desktop(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> showWorkspace(WidgetTester tester) async {
  await desktop(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: PersonalGraduationWorkspace(onBack: () {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  final action = find.widgetWithText(FilledButton, '내 기록에 저장');
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'all student graduation tabs share one mixed frame and keep every field',
    (tester) async {
      await showWorkspace(tester);
      for (final entry in {
        '학교': PersonalRecordKind.personalSchool,
        '학과': PersonalRecordKind.personalDepartment,
        '교육과정': PersonalRecordKind.personalCurriculum,
        '교육과정 과목': PersonalRecordKind.personalCurriculumCourse,
        '개인 규칙': PersonalRecordKind.personalGraduationRule,
      }.entries) {
        await tester.tap(find.widgetWithText(OutlinedButton, entry.key));
        await tester.pumpAndSettle();
        final frame = find.byKey(
          ValueKey('personal-frame-${entry.value.name}'),
        );
        final list = find.byKey(ValueKey('personal-list-${entry.value.name}'));
        final basic = find.byKey(
          ValueKey('personal-basic-${entry.value.name}'),
        );
        final details = find.byKey(
          ValueKey('personal-details-${entry.value.name}'),
        );
        expect(frame, findsOneWidget);
        expect(
          find.descendant(of: frame, matching: find.byType(Card)),
          findsNothing,
        );
        for (final section in [list, basic, details]) {
          expect(find.descendant(of: frame, matching: section), findsOneWidget);
        }
        expect(
          tester.getTopLeft(list).dx,
          lessThan(tester.getTopLeft(basic).dx),
        );
        expect(
          tester.getTopLeft(details).dy,
          greaterThan(tester.getBottomLeft(list).dy),
        );
        expect(
          tester.getTopLeft(details).dy,
          greaterThan(tester.getBottomLeft(basic).dy),
        );
        expect(
          tester.getSize(details).width,
          greaterThan(tester.getSize(basic).width * 1.8),
        );
        expect(find.text('등록한 항목 0개'), findsOneWidget);
        expect(find.text('등록된 자료가 없습니다.'), findsOneWidget);
        expect(
          find.descendant(of: details, matching: find.text('내 기록에 저장')),
          findsOneWidget,
        );
        final fields = await personalGraduationFields(entry.value);
        for (final field in fields) {
          expect(
            find.byKey(
              ValueKey(
                'record-${field.options.isEmpty ? 'field' : 'select'}-${field.key}',
              ),
            ),
            findsOneWidget,
          );
        }
        if (entry.value == PersonalRecordKind.personalCurriculum) {
          final year = find.byKey(const ValueKey('record-field-admissionYear'));
          final other = find.byKey(
            const ValueKey('record-field-curriculumYear'),
          );
          expect(
            tester.getTopLeft(year).dy,
            closeTo(tester.getTopLeft(other).dy, .1),
          );
          expect(
            tester.getTopLeft(year).dx,
            lessThan(tester.getTopLeft(other).dx),
          );
          expect(
            tester
                .getSize(find.byKey(const ValueKey('record-field-detail')))
                .width,
            greaterThan(tester.getSize(year).width * 1.8),
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'student mixed frame retains draft when cancelling tab change and saves selected school',
    (tester) async {
      await fixture.seed(PersonalRecordKind.personalSchool, 'school', {
        'title': '합성 학교',
      });
      await showWorkspace(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, '학과'));
      await tester.pumpAndSettle();
      await fixture.fill(tester, {'title': '합성 학과', 'code': 'CS'});
      await fixture.select(tester, 'schoolId', '합성 학교');
      await tester.tap(find.widgetWithText(OutlinedButton, '교육과정'));
      await tester.pumpAndSettle();
      expect(find.text('작성한 내용을 폐기할까요?'), findsOneWidget);
      await tester.tap(find.text('계속 작성'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('record-field-title')),
            )
            .controller!
            .text,
        '합성 학과',
      );
      expect(
        tester
            .widget<AnchoredSelectField<String>>(
              find.byKey(const ValueKey('record-select-schoolId')),
            )
            .value,
        'school',
      );
      await save(tester);
      final repo = PersonalRecordRepository(
        PersonalRecordKind.personalDepartment,
      );
      await repo.load();
      expect(repo.records.single.value('schoolId'), 'school');
      expect(repo.records.single.value('code'), 'CS');
      expect(find.text('등록한 항목 1개'), findsOneWidget);
      expect(find.byType(Card), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'server graduation mixed frame preserves failed edit and retries existing contract',
    (tester) async {
      await desktop(tester);
      final gateway = GraduationLayoutGateway()..failWrites = true;
      await tester.pumpWidget(
        server.scope(gateway, PersonalGraduationWorkspace(onBack: () {})),
      );
      await tester.pumpAndSettle();
      expect(find.text('합성 personalCurriculum'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '학교'), findsNothing);
      await tester.tap(find.widgetWithText(OutlinedButton, '수정'));
      await tester.pumpAndSettle();
      await fixture.fill(tester, {'title': '서버 이름 수정', 'department': '수정할 학과'});
      await save(tester);
      expect(find.text('저장하지 못했습니다. 입력을 유지했으니 다시 시도하세요.'), findsOneWidget);
      expect(find.text('합성 personalCurriculum'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('record-field-title')),
            )
            .controller!
            .text,
        '서버 이름 수정',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('record-field-department')),
            )
            .controller!
            .text,
        '수정할 학과',
      );
      gateway.failWrites = false;
      await save(tester);
      final patches = gateway.calls
          .where((call) => call.$1 == 'PATCH')
          .toList();
      expect(patches, hasLength(2));
      expect(patches[0].$3, patches[1].$3);
      expect(
        patches[1].$2,
        'me/personal-curricula/${fixtureId(PersonalRecordKind.personalCurriculum)}',
      );
      expect(patches[1].$3!['expected_version'], 1);
      expect(patches[1].$3!['title'], '서버 이름 수정');
      expect(patches[1].$3!['department'], '수정할 학과');
      expect(
        patches[1].$3!.keys,
        unorderedEquals([
          ...PersonalRecordCodec(PersonalRecordKind.personalCurriculum)
              .encode(fixtureValues(PersonalRecordKind.personalCurriculum))
              .toJson()
              .keys
              .where((key) => key != 'client_id'),
          'expected_version',
        ]),
      );
      expect(find.text('서버 이름 수정'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class GraduationLayoutGateway extends PersonalGateway {
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    if (method != 'PATCH' || failWrites) {
      return super.request(method, path, body);
    }
    calls.add((method, path, body));
    return {
      ...body!,
      'id': path.split('/').last,
      'owner_id': userId,
      'version': 2,
      'origin': 'personal',
      'official': false,
      'created_at': '2026-10-25T00:00:00Z',
      'updated_at': '2026-10-25T00:00:00Z',
    };
  }
}
