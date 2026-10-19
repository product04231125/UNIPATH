import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';
import 'package:university_path_frontend/features/api/personal_evaluation_api.dart';
import 'package:university_path_frontend/features/graduation/personal_calculation_controller.dart';
import 'package:university_path_frontend/features/graduation/personal_calculation_draft.dart';
import 'package:university_path_frontend/features/graduation/personal_calculation_page.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';

import 'support/calculation_gateway.dart';
import 'support/personal_workspace_fixture.dart';

Future<PersonalCalculationController> controller(
  CalculationGateway gateway,
) async {
  final result = PersonalCalculationController(gateway.api, ensureOpen: () {})
    ..asOf = '2026-10-19';
  await result.loadCurricula();
  await result.select(fixtureId(PersonalRecordKind.personalCurriculum));
  return result;
}

void main() {
  test('amounts and dates validate exactly without float conversion', () {
    for (final value in ['0', '3.000001', '1000000.000000', '0003.125']) {
      expect(validateCalculationAmount(value), isNull, reason: value);
    }
    for (final value in [
      'NaN',
      'Infinity',
      '-1',
      '1e3',
      '0.0000001',
      '1000000.000001',
      '',
      '9' * 25,
    ]) {
      expect(validateCalculationAmount(value), isNotNull, reason: value);
    }
    expect(validateCalculationDay('2026-02-29'), isNotNull);
    expect(validateCalculationDay('2024-02-29'), isNull);
  });
  test('loading never posts, never interprets saved condition/current values, and pins reviewed versions', () async {
    final gateway = CalculationGateway();
    final c = await controller(gateway);
    addTearDown(c.dispose);
    expect(gateway.posted, isEmpty);
    expect(c.drafts.values.single.kind, 'none');
    await c.calculate();
    final body = gateway.posted.single;
    expect(body['calculations'], isEmpty);
    expect(body['expected_curriculum_version'], 1);
    expect(
      (body['expected_source_versions'] as List).map((v) => v['kind']),
      containsAll(['personal-curricula', 'personal-graduation-rules']),
    );
    expect(body.containsKey('owner_id'), isFalse);
    expect(c.result!.label, PersonalEvaluationSummary.personalLabel);
  });
  test('all five condition forms carry explicit choices and conservative observations', () async {
    final gateway = CalculationGateway()..ruleCount = 5;
    final c = await controller(gateway);
    addTearDown(c.dispose);
    final drafts = c.drafts.values.toList();
    drafts[0]
      ..kind = 'minimum_credits'
      ..allCourses = true;
    drafts[0].values['minimum'] = '3.000001';
    drafts[1].kind = 'required_courses';
    drafts[1].selected.add(
      fixtureId(PersonalRecordKind.personalCurriculumCourse),
    );
    drafts[1]
        .observation(fixtureId(PersonalRecordKind.personalCurriculumCourse))
        .addAll({
          'minimumCredits': '3',
          'minimumGradePoints': '3',
          'comparisonGradeScale': '4.5',
          'points': '3.125',
          'scale': '4.5',
        });
    drafts[2].kind = 'minimum_volunteer_hours';
    drafts[2].values['minimum'] = '3.25';
    drafts[2].selected.add(fixtureId(PersonalRecordKind.activity));
    drafts[3].kind = 'any_certificate';
    drafts[3].selected.add(fixtureId(PersonalRecordKind.credential));
    drafts[4].kind = 'thesis';
    drafts[4].values['thesisType'] = '졸업작품';
    drafts[4].selected.add(fixtureId(PersonalRecordKind.portfolio));
    await c.calculate();
    expect(c.actionError, isNull);
    final rows = gateway.posted.single['calculations'] as List;
    expect((rows[0]['condition'] as Map)['minimum'], '3.000001');
    expect((rows[0]['condition'] as Map)['course_record_ids'], [
      fixtureId(PersonalRecordKind.course),
    ]);
    expect((rows[1]['condition']['grades'] as List).single['points'], '3.125');
    expect(
      (rows[3]['condition']['certificates'] as List).single['possession'],
      'unknown',
    );
    expect(
      (rows[3]['condition']['certificates'] as List).single['validity_known'],
      isFalse,
    );
    expect(
      (rows[4]['condition']['records'] as List).single['completion'],
      'unknown',
    );
    expect(
      (rows[4]['condition']['records'] as List).single['approval'],
      'needs_review',
    );
    expect(
      (gateway.posted.single['expected_source_versions'] as List).length,
      11,
    );
  });
  test('large curriculum pagination does not block an unrelated volunteer calculation', () async {
    final gateway = CalculationGateway()..linkCount = 601;
    final c = await controller(gateway);
    addTearDown(c.dispose);
    expect(c.sourceError, isNull);
    expect(c.sources!.links.length, 601);
    c.drafts.values.single
      ..kind = 'minimum_volunteer_hours'
      ..values['minimum'] = '3.25'
      ..selected.add(fixtureId(PersonalRecordKind.activity));
    await c.calculate();
    expect(c.actionError, isNull);
    final versions = gateway.posted.single['expected_source_versions'] as List;
    expect(versions.length, 3);
    expect(
      versions.any((v) => v['kind'] == 'personal-curriculum-courses'),
      isFalse,
    );
  });
  test(
    'invalid paired grade fields and missing selections never post',
    () async {
      final g = CalculationGateway();
      final c = await controller(g);
      addTearDown(c.dispose);
      final d = c.drafts.values.single..kind = 'required_courses';
      await c.calculate();
      expect(g.posted, isEmpty);
      d.selected.add(fixtureId(PersonalRecordKind.personalCurriculumCourse));
      d.observation(d.selected.single)['minimumGradePoints'] = '3';
      await c.calculate();
      expect(g.posted, isEmpty);
      expect(c.actionError, contains('함께'));
      d.observation(d.selected.single)['comparisonGradeScale'] = '4.5';
      await c.calculate();
      expect(g.posted.length, 1);
    },
  );
  test('explicit empty credit selection remains empty, never uses every record implicitly', () async {
    final g = CalculationGateway();
    final c = await controller(g);
    addTearDown(c.dispose);
    final d = c.drafts.values.single..kind = 'minimum_credits';
    d.values['minimum'] = '0';
    await c.calculate();
    expect(
      g.posted.single['calculations'][0]['condition']['course_record_ids'],
      isEmpty,
    );
    expect(
      (g.posted.single['expected_source_versions'] as List).any(
        (v) => v['kind'] == 'course-records',
      ),
      isFalse,
    );
  });
  test('inclusive rule dates and inactive drafts do not execute', () async {
    final g = CalculationGateway()
      ..ruleFrom = '2026-10-19'
      ..ruleTo = '2026-10-19';
    final c = await controller(g);
    addTearDown(c.dispose);
    final d = c.drafts.values.single..kind = 'minimum_credits';
    d.values['minimum'] = '1';
    await c.calculate();
    expect((g.posted.single['calculations'] as List).length, 1);
    c.newCalculation();
    c.asOf = '2026-10-20';
    await c.calculate();
    expect(g.posted.last['calculations'], isEmpty);
  });
  test('lost response retries exact client ID/body and cannot reload source snapshot', () async {
    final g = CalculationGateway()..loseResponse = true;
    final c = await controller(g);
    addTearDown(c.dispose);
    final d = c.drafts.values.single..kind = 'minimum_credits';
    d.values['minimum'] = '3';
    d.allCourses = true;
    await c.calculate();
    final frozen = jsonEncode(g.posted.single);
    expect(c.actionError, isNotNull);
    expect(c.pending, isNotNull);
    expect(g.saved.length, 1);
    await c.select(fixtureId(PersonalRecordKind.personalCurriculum));
    // Even an accidental in-memory draft edit cannot alter the frozen request.
    d.values['minimum'] = '130';
    await c.calculate();
    expect(jsonEncode(g.posted.last), frozen);
    expect(g.saved.length, 1);
    expect(c.actionError, isNull);
    expect(c.result, isNotNull);
  });
  test('source failures and repeated cursors block calculations without local fallback', () async {
    for (final repeated in [false, true]) {
      final g = CalculationGateway()
        ..repeatSource = repeated
        ..failSources = !repeated;
      final c = await controller(g);
      addTearDown(c.dispose);
      expect(c.sourceError, isNotNull);
      await c.calculate();
      expect(g.posted, isEmpty);
    }
  });
  test('conflict preserves draft, retry key and last result; foreign owner is rejected', () async {
    final g = CalculationGateway()..failWrites = true;
    final c = await controller(g);
    addTearDown(c.dispose);
    c.drafts.values.single
      ..kind = 'minimum_credits'
      ..values['minimum'] = '3';
    await c.calculate();
    expect(c.actionError, contains('버전'));
    expect(c.pending, isNotNull);
    expect(c.drafts.values.single.values['minimum'], '3');
    g.failWrites = false;
    g.badOwner = true;
    await c.calculate();
    expect(c.result, isNull);
    g.badOwner = false;
    await c.calculate();
    expect(c.result, isNotNull);
    expect(g.posted.map((p) => p['client_id']).toSet().length, 1);
  });
  test('history opens immutable details, rejects repeated page, deletion sends captured version', () async {
    final g = CalculationGateway();
    final c = await controller(g);
    addTearDown(c.dispose);
    await c.calculate();
    await c.loadHistory();
    expect(c.history.length, 1);
    await c.openResult(calculationResultId);
    expect(c.result!.id, calculationResultId);
    g.repeatHistory = true;
    await c.loadHistory();
    await c.loadHistory(more: true);
    expect(c.historyError, isNotNull);
    expect(c.history.length, 1);
    await c.remove(c.history.single);
    expect(g.calls.last.$2, contains('expected_version=1'));
    expect(c.history, isEmpty);
    expect(c.result, isNull);
  });
  test('closed workspace prevents queued calculation and logout does not move drafts to another owner', () async {
    final g = CalculationGateway();
    bool closed = false;
    final c = PersonalCalculationController(
      g.api,
      ensureOpen: () {
        if (closed) throw StateError('closed');
      },
    );
    addTearDown(c.dispose);
    await c.loadCurricula();
    await c.select(fixtureId(PersonalRecordKind.personalCurriculum));
    closed = true;
    await c.calculate();
    expect(g.posted, isEmpty);
  });

  testWidgets(
    'five UI condition selectors render on narrow large text without implicit observations or posts',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 520));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gateway = CalculationGateway();
      final c = await controller(gateway);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(body: PersonalCalculationPage(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      for (final entry in personalConditionLabels.entries.where(
        (e) => e.key != 'none',
      )) {
        final picker = find.byWidgetPredicate(
          (w) => w is AnchoredSelectField<String> && w.label == '실행할 계산 조건',
        );
        await tester.ensureVisible(picker);
        await tester.tap(picker);
        await tester.pumpAndSettle();
        final option = find.text(entry.value).last;
        await tester.ensureVisible(option);
        await tester.tap(option);
        await tester.pumpAndSettle();
        expect(c.drafts.values.single.kind, entry.key);
        expect(gateway.posted, isEmpty);
        if (entry.key == 'any_certificate') {
          final choice = find.textContaining('합성 credential').first;
          await tester.ensureVisible(choice);
          await tester.tap(choice);
          await tester.pumpAndSettle();
          expect(find.text('내가 확인한 보유 상태'), findsOneWidget);
          expect(c.drafts.values.single.observations.values.single, isEmpty);
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in [const Size(1440, 900), const Size(480, 520)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'calculation form, conflict and history at $size scale=$scale',
        (tester) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final g = CalculationGateway()..failWrites = true;
          final c = await controller(g);
          addTearDown(c.dispose);
          c.drafts.values.single
            ..kind = 'minimum_credits'
            ..values['minimum'] = '3.125'
            ..allCourses = true;
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(body: PersonalCalculationPage(controller: c)),
            ),
          );
          await tester.pumpAndSettle();
          final save = find.widgetWithText(FilledButton, '계산하고 결과 저장');
          await tester.ensureVisible(save);
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(find.textContaining('입력은 유지됩니다'), findsOneWidget);
          expect(c.drafts.values.single.values['minimum'], '3.125');
          g.failWrites = false;
          final retry = find.widgetWithText(FilledButton, '같은 요청으로 다시 확인');
          await tester.ensureVisible(retry);
          await tester.tap(retry);
          await tester.pumpAndSettle();
          expect(
            find.text(PersonalEvaluationSummary.personalLabel),
            findsNWidgets(2),
          );
          expect(find.text('계산 결과'), findsOneWidget);
          expect(g.posted.map((b) => b['client_id']).toSet().length, 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
