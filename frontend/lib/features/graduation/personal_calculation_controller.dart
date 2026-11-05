import 'package:flutter/foundation.dart';

import '../api/personal_evaluation_api.dart';
import '../api/student_api.dart';
import '../api/student_api_models.dart';
import '../auth/auth_api.dart';
import '../records/personal_record_repository.dart';
import 'personal_calculation_draft.dart';

class PersonalCalculationController extends ChangeNotifier {
  PersonalCalculationController(this.student, {required this.ensureOpen})
    : evaluations = PersonalEvaluationApi(
        student.api,
        ownerId: student.ownerId,
      );
  final StudentApi student;
  final PersonalEvaluationApi evaluations;
  final void Function() ensureOpen;
  List<StudentRecord<StudentPersonalCurriculumCreate>> curricula = [];
  PersonalCalculationSources? sources;
  final drafts = <String, PersonalCalculationDraft>{};
  String asOf = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  List<PersonalEvaluationSummary> history = [];
  String? nextCursor, sourceError, historyError, actionError;
  PersonalEvaluation? result;
  PersonalEvaluationRequest? pending;
  bool loading = false, historyLoading = false, busy = false, _closed = false;
  bool get locked => loading || busy || pending != null;
  bool get hasDraft => drafts.values.any((d) => d.hasInput);
  final _historyCursors = <String>{};
  void _check() {
    if (_closed) throw StateError('Calculation workspace is closed');
    ensureOpen();
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }

  static String message(Object error) => switch (error) {
    AuthFailure(status: 409) =>
      '자료 버전이나 재시도 내용이 달라졌습니다. 입력은 유지됩니다. 이력을 확인하고 자료를 다시 불러온 뒤 새 계산을 준비하세요.',
    AuthFailure(status: 422) =>
      '계산 조건과 자료 연결을 확인하세요. 선택 개수·수치·서로 다른 규칙의 관찰 값도 확인해 주세요. 입력은 유지됩니다.',
    AuthFailure(status: 401) => '다시 로그인해 주세요. 기존 계산을 자동으로 새 계정에 전송하지 않습니다.',
    AuthFailure(status: 403) =>
      '현재 로그인 계정이 이 작업 공간과 다르거나 권한이 없습니다. 다시 로그인해 주세요.',
    AuthFailure(status: 404) => '선택한 자료나 결과가 삭제되었거나 접근할 수 없습니다. 다시 불러와 확인하세요.',
    AuthFailure(status: 429) => '요청이 많습니다. 잠시 후 같은 요청으로 다시 시도하세요.',
    FormatException(:final message) => message,
    _ => '서버 확인에 실패했습니다. 입력과 기존 결과를 보존했습니다. 다시 시도하세요.',
  };

  Future<List<StudentRecord<T>>> _all<T extends StudentPayload>(
    StudentResource<T> resource, {
    String? curriculumId,
  }) async {
    final rows = <StudentRecord<T>>[], ids = <String>{}, cursors = <String>{};
    String? cursor;
    do {
      _check();
      final page = await student.list(
        resource,
        curriculumId: curriculumId,
        cursor: cursor,
      );
      _check();
      for (final row in page.items) {
        if (!ids.add(row.id)) {
          throw const FormatException('자료 목록이 반복됩니다. 다시 불러오세요.');
        }
        rows.add(row);
      }
      cursor = page.nextCursor;
      if (cursor != null && !cursors.add(cursor)) {
        throw const FormatException('목록의 다음 페이지가 반복됩니다.');
      }
    } while (cursor != null);
    return List.unmodifiable(rows);
  }

  Future<void> loadCurricula() async {
    if (locked) return;
    loading = true;
    sourceError = null;
    sources = null;
    drafts.clear();
    _notify();
    try {
      curricula = await _all(StudentResources.personalCurricula);
    } catch (e) {
      sourceError = message(e);
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> select(String id) async {
    if (locked) return;
    loading = true;
    sourceError = null;
    _notify();
    try {
      _check();
      final curriculum = await student.get(
        StudentResources.personalCurricula,
        id,
      );
      final rules = await _all(
        StudentResources.graduationRules,
        curriculumId: id,
      );
      final links = await _all(
        StudentResources.curriculumCourses,
        curriculumId: id,
      );
      if (rules.any((r) => r.data.curriculumId != id) ||
          links.any((r) => r.data.curriculumId != id)) {
        throw const FormatException('다른 교육과정 자료가 반환되었습니다.');
      }
      final courses = await _all(StudentResources.courseRecords);
      final activities = await _all(StudentResources.activityRecords);
      final credentials = await _all(StudentResources.credentialRecords);
      final achievements = await _all(StudentResources.achievementRecords);
      _check();
      sources = PersonalCalculationSources(
        curriculum: curriculum,
        rules: rules,
        links: links,
        courses: courses,
        activities: activities,
        credentials: credentials,
        achievements: achievements,
      );
      drafts.clear();
      for (final rule in rules) {
        drafts[rule.id] = PersonalCalculationDraft();
      }
      result = null;
      actionError = null;
    } catch (e) {
      sourceError = message(e);
    } finally {
      loading = false;
      _notify();
    }
  }

  PersonalEvaluationRequest _request() {
    final snapshot = sources;
    if (snapshot == null || sourceError != null) {
      throw const FormatException('자료를 먼저 성공적으로 불러오세요.');
    }
    final dayError = validateCalculationDay(asOf);
    if (dayError != null) throw FormatException(dayError);
    final active = snapshot.rules
        .where((r) => snapshot.active(r, asOf))
        .toList();
    if (active.length > 100) {
      throw const FormatException('활성 규칙은 100개 이내로 정리해 주세요.');
    }
    final calculations = <PersonalRuleCalculation>[];
    final versions = <String, PersonalSourceVersion>{};
    void pin<T extends StudentPayload>(
      String kind,
      Iterable<StudentRecord<T>> rows,
    ) {
      for (final r in rows) {
        versions['$kind/${r.id}'] = PersonalSourceVersion(
          kind: kind,
          recordId: r.id,
          version: r.version,
        );
      }
    }

    pin('personal-curricula', [snapshot.curriculum]);
    pin('personal-graduation-rules', active);
    for (final rule in active) {
      final condition = drafts[rule.id]!.condition(snapshot);
      if (condition == null) continue;
      calculations.add(
        PersonalRuleCalculation(
          ruleId: rule.id,
          expectedVersion: rule.version,
          condition: condition,
        ),
      );
      switch (condition) {
        case PersonalCreditCondition(:final courseRecordIds):
          pin(
            'personal-curriculum-courses',
            snapshot.links.where(
              (r) => courseRecordIds!.contains(r.data.courseRecordId),
            ),
          );
          pin(
            'course-records',
            snapshot.courses.where((r) => courseRecordIds!.contains(r.id)),
          );
        case PersonalCourseCondition(:final courses):
          pin(
            'personal-curriculum-courses',
            snapshot.links.where(
              (r) => courses.any((course) => course.curriculumCourseId == r.id),
            ),
          );
          final recordIds = snapshot.links
              .where((r) => courses.any((c) => c.curriculumCourseId == r.id))
              .map((r) => r.data.courseRecordId)
              .toSet();
          pin(
            'course-records',
            snapshot.courses.where((r) => recordIds.contains(r.id)),
          );
        case PersonalVolunteerCondition(:final activityIds):
          pin(
            'activity-records',
            snapshot.activities.where((r) => activityIds.contains(r.id)),
          );
        case PersonalCertificateCondition(:final certificates):
          pin(
            'credential-records',
            snapshot.credentials.where(
              (r) => certificates.any((c) => c.credentialId == r.id),
            ),
          );
        case PersonalThesisCondition(:final records):
          pin(
            'achievement-records',
            snapshot.achievements.where(
              (r) => records.any((c) => c.achievementId == r.id),
            ),
          );
      }
    }
    if (versions.length > 2000) {
      throw const FormatException('계산에 고정하는 자료 버전은 2000개 이내여야 합니다.');
    }
    return PersonalEvaluationRequest(
      curriculumId: snapshot.curriculum.id,
      expectedCurriculumVersion: snapshot.curriculum.version,
      clientId: PersonalRecord.newId(),
      asOf: asOf,
      calculations: List.unmodifiable(calculations),
      expectedSourceVersions: List.unmodifiable(versions.values),
    );
  }

  Future<void> calculate() async {
    if (busy || loading) return;
    actionError = null;
    try {
      _check();
      pending ??= _request();
    } catch (e) {
      actionError = message(e);
      _notify();
      return;
    }
    busy = true;
    _notify();
    try {
      final value = await evaluations.create(pending!);
      _check();
      if (value.clientId != pending!.clientId ||
          value.curriculumId != pending!.curriculumId) {
        throw const FormatException('요청과 다른 계산 결과가 반환되었습니다.');
      }
      result = value;
      // Preserve this exact request until the user explicitly starts a new
      // calculation; retrying a lost response must never create a new result.
      history = [value, ...history.where((r) => r.id != value.id)];
    } catch (e) {
      actionError = message(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  void newCalculation() {
    if (busy || loading) return;
    pending = null;
    actionError = null;
    _notify();
  }

  Future<void> loadHistory({bool more = false}) async {
    if (historyLoading) return;
    final cursor = more ? nextCursor : null;
    if (more && cursor == null) return;
    historyLoading = true;
    historyError = null;
    _notify();
    try {
      _check();
      final page = await evaluations.list(cursor: cursor, limit: 20);
      _check();
      final ids = page.items.map((r) => r.id).toSet();
      if (ids.length != page.items.length ||
          (more &&
              page.nextCursor != null &&
              _historyCursors.contains(page.nextCursor)) ||
          (cursor != null && page.nextCursor == cursor) ||
          (more && history.any((r) => ids.contains(r.id)))) {
        throw const FormatException('계산 이력 페이지가 반복됩니다. 목록을 다시 불러오세요.');
      }
      history = [
        ...(more ? history : <PersonalEvaluationSummary>[]),
        ...page.items,
      ];
      nextCursor = page.nextCursor;
      if (!more) _historyCursors.clear();
      if (nextCursor != null) _historyCursors.add(nextCursor!);
    } catch (e) {
      historyError = message(e);
    } finally {
      historyLoading = false;
      _notify();
    }
  }

  Future<void> openResult(String id) async {
    if (busy) return;
    busy = true;
    actionError = null;
    _notify();
    try {
      _check();
      final value = await evaluations.get(id);
      _check();
      if (value.id != id) throw const FormatException('선택한 이력과 다른 결과입니다.');
      result = value;
    } catch (e) {
      actionError = message(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> remove(PersonalEvaluationSummary value) async {
    if (busy) return;
    busy = true;
    actionError = null;
    _notify();
    try {
      _check();
      await evaluations.remove(value.id, expectedVersion: value.version);
      _check();
      history = history.where((r) => r.id != value.id).toList();
      if (result?.id == value.id) result = null;
    } catch (e) {
      actionError = message(e);
    } finally {
      busy = false;
      _notify();
    }
  }
}
