import 'package:flutter/foundation.dart';

import '../records/personal_record_repository.dart';
import 'admin_models.dart';
import 'admin_repository.dart';
import 'remote_admin_repository.dart';

/// Composes the existing two API resources without inventing a combined DTO.
/// A partial success is retained so retry cannot create a second course.
class AdminCourseRegistration {
  AdminRecord? _savedCourse;
  Map<String, String>? _savedValues;
  bool _courseUncertain = false, _reloadLink = false;
  AdminRecord? _attemptedLink;

  void reset() {
    _savedCourse = null;
    _savedValues = null;
    _courseUncertain = false;
    _reloadLink = false;
    _attemptedLink = null;
  }

  Future<AdminRecord> save({
    required AdminRepository repository,
    required String actorId,
    required Map<String, String> courseValues,
    required String curriculumId,
    required String category,
    required String requiredCourse,
    AdminRecord? original,
  }) async {
    if (_courseUncertain)
      throw StateError(
        '과목 저장 결과가 불명확합니다. 과목 목록을 다시 읽고 등록된 과목의 수정으로 이어가세요. 자동 재전송하지 않습니다.',
      );
    if (_reloadLink) await repository.load();
    final prior = _savedCourse ?? original;
    final links = repository.records
        .where(
          (r) =>
              r.kind == AdminKind.curriculumCourse &&
              r.value('courseId') == prior?.id &&
              r.value('curriculumId') == curriculumId,
        )
        .toList();
    if (links.length > 1)
      throw StateError('같은 교육과정에 연결이 여러 개 있습니다. 연결 관리에서 확인하세요.');
    Future<AdminRecord> persist(AdminRecord record) async {
      if (repository is RemoteAdminRepository)
        return repository.saveWithResult(actorId, record);
      await repository.save(actorId, record);
      return repository.records.firstWhere((r) => r.id == record.id);
    }

    if (_savedCourse == null || !mapEquals(courseValues, _savedValues)) {
      try {
        _savedCourse = await persist(
          prior?.copy(values: courseValues) ??
              AdminRecord(
                id: 'mock-${PersonalRecord.newId()}',
                kind: AdminKind.course,
                values: courseValues,
              ),
        );
      } catch (error) {
        if (error is StateError &&
            (error is! AdminRequestFailure || error.rejected))
          rethrow;
        _courseUncertain = true;
        throw StateError(
          '과목 저장 결과를 확인하지 못했습니다. 목록을 다시 읽고 등록된 과목의 수정으로 이어가세요. 입력은 유지하며 자동 재전송하지 않습니다.',
        );
      }
      _savedValues = Map.of(courseValues);
    }
    final course = _savedCourse!;
    final oldLink = links.firstOrNull;
    final linkValues = <String, String>{
      ...?oldLink?.values,
      'name': oldLink?.name ?? '${course.name} · 교육과정 연결',
      'institutionId': course.value('institutionId'),
      'curriculumId': curriculumId,
      'courseId': course.id,
      'category': category,
      'required': requiredCourse,
    };
    try {
      if (oldLink == null || !mapEquals(linkValues, oldLink.values)) {
        if (_reloadLink &&
            oldLink != null &&
            oldLink.version != _attemptedLink?.version) {
          throw StateError('교육과정 연결이 변경되었습니다. 연결 관리에서 최신 내용을 확인하세요.');
        }
        _attemptedLink = oldLink;
        await persist(
          oldLink?.copy(values: linkValues) ??
              AdminRecord(
                id: 'mock-${PersonalRecord.newId()}',
                kind: AdminKind.curriculumCourse,
                values: linkValues,
              ),
        );
      }
    } catch (error) {
      _reloadLink = true;
      throw StateError(
        '과목은 저장됐지만 교육과정 연결을 저장하지 못했습니다. 입력을 유지했습니다. 다시 저장하면 연결을 이어서 처리합니다. ${error is StateError ? error.message : ''}',
      );
    }
    _reloadLink = false;
    return course;
  }
}
