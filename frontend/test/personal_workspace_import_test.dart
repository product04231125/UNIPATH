import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/auth/local_data_owner.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/personal_workspace_importer.dart';
import 'package:university_path_frontend/features/records/personal_workspace_import_section.dart';

import 'support/auth_fixture.dart';
import 'support/personal_gateway.dart';
import 'support/personal_workspace_fixture.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalDataOwner.currentUserId = null;
  });
  tearDown(() => LocalDataOwner.currentUserId = null);
  test(
    'only selected owner local data is reviewed and load never uploads',
    () async {
      await seedLocalWorkspace(otherId);
      final anonymous = PersonalRecordRepository(
        PersonalRecordKind.course,
        owner: const LocalDataOwner(null),
      );
      await anonymous.load();
      await anonymous.save(
        PersonalRecord(
          id: fixtureId(PersonalRecordKind.course),
          values: fixtureValues(PersonalRecordKind.course),
        ),
      );
      LocalDataOwner.currentUserId = otherId;
      final gateway = PersonalGateway();
      final importer = PersonalWorkspaceImporter(
        gateway.api,
        ensureOpen: () {},
      );
      addTearDown(importer.dispose);
      await importer.load();
      expect(importer.failed, isFalse);
      expect(importer.count, 0);
      expect(gateway.calls, isEmpty);
      await seedLocalWorkspace(userId);
      await importer.load();
      expect(importer.count, 10);
      expect(importer.canImport, isTrue);
      expect(gateway.calls, isEmpty);
    },
  );
  test('rejected journal write sends nothing and preserves originals until explicit consent', () async {
    await seedLocalWorkspace(userId);
    final preferences = await SharedPreferences.getInstance();
    final originals = {
      for (final key in preferences.getKeys()) key: preferences.getString(key),
    };
    var allow = false;
    final gateway = PersonalGateway();
    final importer = PersonalWorkspaceImporter(
      gateway.api,
      ensureOpen: () {},
      writer: (key, value) =>
          allow ? preferences.setString(key, value) : Future.value(false),
    );
    addTearDown(importer.dispose);
    await importer.load();
    await expectLater(
      importer.importRecords(confirmed: true, snapshotId: importer.snapshotId!),
      throwsStateError,
    );
    expect(gateway.calls, isEmpty);
    allow = true;
    await expectLater(
      importer.importRecords(
        confirmed: false,
        snapshotId: importer.snapshotId!,
      ),
      throwsStateError,
    );
    expect(gateway.calls, isEmpty);
    await importer.importRecords(
      confirmed: true,
      snapshotId: importer.snapshotId!,
    );
    expect(gateway.calls, hasLength(1));
    expect(importer.completed, isTrue);
    expect(importer.importedRevision.value, 1);
    for (final entry in originals.entries) {
      expect(preferences.getString(entry.key), entry.value);
    }
    final request = gateway.calls.single.$3!;
    expect(request['profile'], isNull);
    expect(request['events'], isEmpty);
    expect(
      (request['course_records'] as List).single['client_id'],
      fixtureId(PersonalRecordKind.course),
    );
  });
  test('dangling relation blocks the whole graph and does not silently discard a record', () async {
    await seedLocalWorkspace(userId);
    final course = PersonalRecordRepository(
      PersonalRecordKind.personalCurriculumCourse,
      owner: const LocalDataOwner(userId),
    );
    await course.load();
    await course.save(
      PersonalRecord(
        id: fixtureId(course.kind),
        values: {...fixtureValues(course.kind), 'curriculumId': 'missing'},
      ),
    );
    final gateway = PersonalGateway();
    final importer = PersonalWorkspaceImporter(gateway.api, ensureOpen: () {});
    addTearDown(importer.dispose);
    await importer.load();
    expect(importer.failed, isFalse);
    expect(importer.issue, contains('연결된 기기 원본이 없습니다'));
    expect(importer.canImport, isFalse);
    expect(gateway.calls, isEmpty);
    await course.load();
    expect(course.records.single.value('curriculumId'), 'missing');
  });
  test(
    'a changed snapshot or closed session cannot submit an earlier review',
    () async {
      await seedLocalWorkspace(userId);
      var closed = false;
      final gateway = PersonalGateway();
      final importer = PersonalWorkspaceImporter(
        gateway.api,
        ensureOpen: () {
          if (closed) throw StateError('closed');
        },
      );
      addTearDown(importer.dispose);
      await importer.load();
      final previous = importer.snapshotId!;
      await importer.load();
      await expectLater(
        importer.importRecords(confirmed: true, snapshotId: previous),
        throwsStateError,
      );
      closed = true;
      await expectLater(
        importer.importRecords(
          confirmed: true,
          snapshotId: importer.snapshotId!,
        ),
        throwsStateError,
      );
      expect(gateway.calls, isEmpty);
    },
  );
  for (final overrides in [
    <String, Object?>{'source_owner_id': otherId},
    <String, Object?>{
      'profile': {'school': 'outside scope'},
    },
    <String, Object?>{'consent_confirmed': false},
  ]) {
    test(
      'invalid owner, scope or consent in journal stays untouched: ${overrides.keys.single}',
      () async {
        final preferences = await SharedPreferences.getInstance();
        final key = const LocalDataOwner(userId)
            .key('university_path.personal_workspace_import.v1');
        final raw = jsonEncode({
          'completed': false,
          'request': {
            'import_id': compositionId,
            'source_owner_id': userId,
            'consent_confirmed': true,
            ...overrides,
          },
        });
        await preferences.setString(key, raw);
        final gateway = PersonalGateway();
        final importer = PersonalWorkspaceImporter(
          gateway.api,
          ensureOpen: () {},
        );
        addTearDown(importer.dispose);
        await importer.load();
        expect(importer.failed, isTrue);
        expect(importer.canImport, isFalse);
        expect(preferences.getString(key), raw);
        expect(gateway.calls, isEmpty);
      },
    );
  }
  for (final size in [const Size(1440, 900), const Size(480, 520)]) {
    testWidgets(
      'whole workspace consent protects source data and stays usable at $size',
      (tester) async {
        await seedLocalWorkspace(userId);
        final gateway = PersonalGateway();
        final importer = PersonalWorkspaceImporter(
          gateway.api,
          ensureOpen: () {},
        );
        addTearDown(importer.dispose);
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PersonalWorkspaceImportSection(importer: importer),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(gateway.calls, isEmpty);
        await tester.tap(find.text('기기 개인 기록 이전'));
        await tester.pumpAndSettle();
        final confirm = find.widgetWithText(FilledButton, '동의하고 이전');
        expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
        await Scrollable.ensureVisible(
          tester.element(find.byType(Checkbox)),
          alignment: .5,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(importer.completed, isTrue);
        expect(gateway.calls, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
