import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/records/course/course_page.dart';
import 'package:university_path_frontend/features/records/personal_record_form.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';
import 'package:university_path_frontend/app.dart';

import 'student_academic_integration_test.dart' as academic;
import 'remote_personal_ui_test.dart' as remote;
import 'support/personal_gateway.dart';

void main() {
  setUpAll(() async {
    if (const bool.fromEnvironment('COURSE_FLOW_CAPTURE')) {
      await (FontLoader('Pretendard')..addFont(
            rootBundle.load('assets/fonts/pretendard/Pretendard-Regular.otf'),
          ))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'one course selection stores academic IDs and completion without a second link form',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = PersonalRecordRepository(PersonalRecordKind.course);
      await repo.load();
      final gateway = academic.AcademicTransport();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPersonalRecordForm(
                  context: context,
                  kind: PersonalRecordKind.course,
                  repository: repo,
                  addLabel: '수강 과목 추가',
                  studentApi: StudentApi(gateway, ownerId: 'owner'),
                  institutionId: 'school',
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      final picker = tester.widget<AnchoredSelectField<String>>(
        find.byKey(const ValueKey('record-select-course')),
      );
      picker.onChanged('academic:context:entry');
      await tester.pumpAndSettle();
      final term = tester.widget<AnchoredSelectField<String>>(
        find.byKey(const ValueKey('record-select-term')),
      );
      term.onChanged('1학기');
      final status = tester.widget<AnchoredSelectField<String>>(
        find.byKey(const ValueKey('record-select-completion')),
      );
      expect(
        status.options.map((o) => o.value),
        containsAll(['수강 예정', '수강 중', '이수 완료', '미이수']),
      );
      status.onChanged('이수 완료');
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, '내 기록에 저장');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.records.single.value('academicContextId'), 'context');
      expect(repo.records.single.value('academicEntryId'), 'entry');
      expect(repo.records.single.value('completion'), '이수 완료');
      expect(repo.records.single.value('credits'), '3.125');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'compact list preserves original memo in details and sums only completed courses',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = PersonalRecordRepository(PersonalRecordKind.course);
      await repo.load();
      for (final row in [
        ['완료 과목', '이수 기록', '3'],
        ['예정 과목', '수강 예정', '2'],
        ['진행 과목', '수강 중', '1.5'],
        ['미이수 과목', '미이수', '4'],
      ]) {
        await repo.save(
          PersonalRecord(
            id: row[0],
            values: {
              'title': row[0],
              'term': '2026-1',
              'category': '전공선택',
              'credits': row[2],
              'completion': row[1],
              'detail': '보존할 입력 당시 메모',
            },
          ),
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: universityPathTheme(),
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('course-list-capture'),
              child: Material(
                color: universityPathTheme().scaffoldBackgroundColor,
                child: const CoursePage(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('취득학점 합계 3학점 · 수강 중 1.5학점 · 총 4.5학점'),
        findsOneWidget,
      );
      expect(find.textContaining('보존할 입력 당시 메모'), findsNothing);
      expect(find.text('학점 산입 연결'), findsNothing);
      expect(find.textContaining('이수 완료'), findsWidgets);
      if (const bool.fromEnvironment('COURSE_FLOW_CAPTURE')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('course-list-capture')),
        );
        await tester.runAsync(() async {
          final picture = await boundary.toImage();
          final data = await picture.toByteData(format: ui.ImageByteFormat.png);
          await Directory('output/course-flow').create(recursive: true);
          await File('output/course-flow/list.png')
              .writeAsBytes(data!.buffer.asUint8List());
          picture.dispose();
        });
      }
      await tester.tap(find.text('상세 보기').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('보존할 입력 당시 메모'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'captured course records stay editable without academic-code linking',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gateway = PersonalGateway();
      await tester.pumpWidget(
        remote.scope(gateway, CoursePage(studentApi: gateway.api)),
      );
      await tester.pumpAndSettle();
      expect(find.text('합성 course'), findsOneWidget);
      expect(find.text('기존 과목 일괄 연결'), findsNothing);
      expect(find.text('교육과정 과목 확인'), findsNothing);
      expect(find.text('학점 산입 연결'), findsNothing);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '수정'))
            .onPressed,
        isNotNull,
      );
      expect(
        gateway.calls.any((call) => call.$2.startsWith('me/academic-')),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
