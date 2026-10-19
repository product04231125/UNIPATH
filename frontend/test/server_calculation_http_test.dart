import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/personal_evaluation_api.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/graduation/personal_calculation_controller.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/remote_personal_record_repository.dart';

import 'support/personal_workspace_fixture.dart';

class LostCalculationResponse implements ApiGateway {
  LostCalculationResponse(this.inner);
  final ApiGateway inner;
  final bodies = <String>[];
  bool lose = true;
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    if (method == 'POST' && path == 'me/personal-evaluations') {
      bodies.add(jsonEncode(body));
    }
    final value = await inner.request(method, path, body);
    if (method == 'POST' && path == 'me/personal-evaluations' && lose) {
      lose = false;
      throw const AuthFailure('Synthetic lost response after actual commit');
    }
    return value;
  }
}

Future<Map<PersonalRecordKind, String>> seedCalculationRecords(
  StudentApi api, {
  int rules = 5,
}) async {
  final ids = <PersonalRecordKind, String>{};
  for (final kind in [
    PersonalRecordKind.course,
    PersonalRecordKind.activity,
    PersonalRecordKind.credential,
    PersonalRecordKind.portfolio,
    PersonalRecordKind.personalCurriculum,
    PersonalRecordKind.personalCurriculumCourse,
    PersonalRecordKind.personalGraduationRule,
  ]) {
    final repo = RemotePersonalRecordRepository(api, kind, ensureOpen: () {});
    await repo.load();
    final values = fixtureValues(kind);
    if (kind == PersonalRecordKind.personalCurriculumCourse ||
        kind == PersonalRecordKind.personalGraduationRule) {
      values['curriculumId'] = ids[PersonalRecordKind.personalCurriculum]!;
    }
    if (kind == PersonalRecordKind.personalCurriculumCourse) {
      values['courseRecordId'] = ids[PersonalRecordKind.course]!;
    }
    if (kind == PersonalRecordKind.personalGraduationRule) {
      values['curriculumCourseId'] =
          ids[PersonalRecordKind.personalCurriculumCourse]!;
      values['relatedRecord'] =
          'portfolio/${ids[PersonalRecordKind.portfolio]}';
    }
    await repo.save(PersonalRecord(id: PersonalRecord.newId(), values: values));
    ids[kind] = repo.records.single.id;
    if (kind == PersonalRecordKind.personalGraduationRule) {
      for (var i = 1; i < rules; i++) {
        await repo.save(
          PersonalRecord(
            id: PersonalRecord.newId(),
            values: {...values, 'title': '합성 계산 조건 $i', 'ruleCode': 'TEST$i'},
          ),
        );
      }
    }
  }
  return ids;
}

void main() {
  const base = String.fromEnvironment('CALCULATION_TEST_BASE_URL');
  Future<(AuthApi, StudentApi)> connect() async {
    final uri = Uri.parse(base);
    expect(uri.scheme, 'http');
    expect(['localhost', '127.0.0.1'], contains(uri.host));
    final auth = AuthApi(baseUrl: uri, cookieMode: false);
    addTearDown(auth.close);
    final user = await auth.authenticate(
      email: 'calculation-${PersonalRecord.newId()}@example.test',
      password: 'synthetic calculation password 2026',
      displayName: '합성 계산 HTTP 검증',
    );
    return (auth, StudentApi(auth.forOwner(user.id), ownerId: user.id));
  }

  test('real controller computes all five conditions, captures versions, preserves immutable history and deletes only results', () async {
    final (auth, api) = await connect();
    final ids = await seedCalculationRecords(api);
    final c = PersonalCalculationController(api, ensureOpen: () {})
      ..asOf = '2026-10-19';
    addTearDown(c.dispose);
    await c.loadCurricula();
    await c.select(ids[PersonalRecordKind.personalCurriculum]!);
    expect(c.sourceError, isNull);
    final drafts = c.drafts.values.toList();
    drafts[0]
      ..kind = 'minimum_credits'
      ..allCourses = true
      ..values['minimum'] = '3.000001';
    drafts[1]
      ..kind = 'required_courses'
      ..selected.add(ids[PersonalRecordKind.personalCurriculumCourse]!);
    drafts[1]
        .observation(ids[PersonalRecordKind.personalCurriculumCourse]!)
        .addAll({
          'minimumCredits': '3',
          'minimumGradePoints': '3',
          'comparisonGradeScale': '4.5',
          'points': '3.125',
          'scale': '4.5',
        });
    drafts[2]
      ..kind = 'minimum_volunteer_hours'
      ..values['minimum'] = '3.25'
      ..selected.add(ids[PersonalRecordKind.activity]!);
    drafts[3]
      ..kind = 'any_certificate'
      ..selected.add(ids[PersonalRecordKind.credential]!);
    drafts[4]
      ..kind = 'thesis'
      ..values['thesisType'] = '졸업작품'
      ..selected.add(ids[PersonalRecordKind.portfolio]!);
    await c.calculate();
    expect(c.actionError, isNull);
    final first = c.result!;
    expect(first.status, PersonalEvaluationStatus.notSatisfied);
    expect(first.results[0].deficit, '0.000001');
    expect(first.results[1].status, PersonalEvaluationStatus.satisfied);
    expect(first.results[2].status, PersonalEvaluationStatus.satisfied);
    expect(first.results[3].status, PersonalEvaluationStatus.needsReview);
    expect(first.results[4].status, PersonalEvaluationStatus.needsReview);
    c.newCalculation();
    drafts[0].values['minimum'] = '3';
    drafts[3].observation(ids[PersonalRecordKind.credential]!).addAll({
      'possession': 'held',
      'validityKnown': 'true',
    });
    drafts[4].observation(ids[PersonalRecordKind.portfolio]!).addAll({
      'completion': 'completed',
      'approval': 'approved',
    });
    drafts[4].values['acceptedGrades'] = 'A';
    await c.calculate();
    expect(c.actionError, isNull);
    final second = c.result!;
    expect(second.status, PersonalEvaluationStatus.satisfied);
    expect(
      second.results.every(
        (r) => r.status == PersonalEvaluationStatus.satisfied,
      ),
      isTrue,
    );
    await api.patch(
      StudentResources.courseRecords,
      ids[PersonalRecordKind.course]!,
      expectedVersion: 1,
      changes: {'credits': '2'},
    );
    c.newCalculation();
    await c.calculate();
    expect(c.actionError, contains('버전'));
    expect(c.result!.id, second.id);
    await c.openResult(first.id);
    expect(c.result!.status, PersonalEvaluationStatus.notSatisfied);
    expect(c.result!.results[0].deficit, '0.000001');
    await c.openResult(second.id);
    expect(c.result!.status, PersonalEvaluationStatus.satisfied);
    expect(
      c.result!.sourceVersions
          .singleWhere((v) => v.kind == 'course-records')
          .version,
      1,
    );
    // Historical detail remains available after original process/rules/links are deleted.
    for (final row in c.sources!.rules) {
      await api.remove(
        StudentResources.graduationRules,
        row.id,
        expectedVersion: row.version,
      );
    }
    await api.remove(
      StudentResources.curriculumCourses,
      ids[PersonalRecordKind.personalCurriculumCourse]!,
      expectedVersion: 1,
    );
    await api.remove(
      StudentResources.personalCurricula,
      ids[PersonalRecordKind.personalCurriculum]!,
      expectedVersion: 1,
    );
    await c.loadHistory();
    expect(c.history.length, 2);
    for (final value in c.history.toList()) {
      await c.openResult(value.id);
      expect(c.actionError, isNull);
      await c.remove(value);
      expect(c.actionError, isNull);
    }
    await c.loadHistory();
    expect(c.history, isEmpty);
    expect(
      (await api.get(
        StudentResources.courseRecords,
        ids[PersonalRecordKind.course]!,
      )).version,
      2,
    );
    expect((await api.list(StudentResources.activityRecords)).items.length, 1);
    await auth.logout();
    await c.calculate();
    expect(c.actionError, isNotNull);
  }, skip: base.isEmpty);
  test('real committed response loss retries the same request without duplicate result', () async {
    final (auth, api) = await connect();
    final ids = await seedCalculationRecords(api, rules: 1);
    final gateway = LostCalculationResponse(api.api);
    final c = PersonalCalculationController(
      StudentApi(gateway, ownerId: api.ownerId),
      ensureOpen: () {},
    )..asOf = '2026-10-19';
    addTearDown(c.dispose);
    await c.loadCurricula();
    await c.select(ids[PersonalRecordKind.personalCurriculum]!);
    c.drafts.values.single
      ..kind = 'minimum_credits'
      ..allCourses = true
      ..values['minimum'] = '3';
    await c.calculate();
    expect(c.actionError, isNotNull);
    expect((await c.evaluations.list()).items.length, 1);
    await c.calculate();
    expect(c.actionError, isNull);
    expect(c.result!.status, PersonalEvaluationStatus.satisfied);
    expect(gateway.bodies.length, 2);
    expect(gateway.bodies[0], gateway.bodies[1]);
    expect((await c.evaluations.list()).items.length, 1);
    await auth.logout();
  }, skip: base.isEmpty);
}
