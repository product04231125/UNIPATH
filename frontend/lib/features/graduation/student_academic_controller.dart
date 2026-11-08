import 'package:flutter/foundation.dart';

import '../api/student_academic_api.dart';
import '../auth/auth_api.dart';
import '../records/personal_record_repository.dart';

String academicIssue(String issue) =>
    const {
      'profile_incomplete': '설정에서 등록 학교·주학과·입학연도를 저장하세요.',
      'contexts_required': '학업 기준에서 주전공·이수 경로·교육과정을 연결하세요.',
      'profile_context_changed': '프로필이 변경됐습니다. 주전공 연결을 다시 확인하세요.',
      'context_changed': '학업 기준이 변경됐습니다. 적용 내용을 확인하고 전환하세요.',
      'curriculum_unavailable': '적용 교육과정이 게시 상태가 아닙니다. 학업 기준을 확인하세요.',
      'track_inactive': '선택한 이수 경로가 사용 중지됐습니다. 학업 기준을 확인하세요.',
      'context_outside_curriculum': '교육과정의 적용 대상과 일치하지 않습니다.',
      'requirement_withdrawn': '적용 요건이 철회됐습니다. 변경 내용을 확인하세요.',
      'requirement_expired': '적용 요건의 유효기간이 변경됐습니다. 기준을 다시 확인하세요.',
    }[issue] ??
    '학업 기준을 다시 확인하세요.';

String academicStatus(String status) =>
    const {
      'satisfied': '충족',
      'not_satisfied': '미충족',
      'needs_review': '확인 필요',
      'not_applicable': '해당 없음',
      'no_target': '목표 미지정',
      'included': '산입',
      'excluded': '제외',
    }[status] ??
    '확인 필요';

String academicEvidenceReason(String reason) =>
    const {
      'outside_context': '다른 전공에 연결한 기록',
      'confirmed': '확인한 이수 기록',
      'excluded_by_student': '학생이 산입 제외',
      'not_recorded': '수강 예정·수강 중',
      'outside_column': '이 열의 분류·필수 조건과 다름',
      'academic_context_changed': '적용 기준 재확인 필요',
      'column_mapping_required': '학교의 학점 열 연결 필요',
      'record_changed': '수강 기록 변경 후 재확인 필요',
      'curriculum_changed': '교육과정 변경 후 재연결 필요',
      'completion_unconfirmed': '이수 결과 미확인',
      'not_completed': '미이수',
      'multiple_major_policy_required': '전공 간 중복 인정 정책 확인 필요',
      'retake_selection_required': '재수강 중 산입 기록을 선택하세요.',
      'earned_credits_required': '취득학점 미확인',
      'course_link_required': '교육과정 과목 연결 필요',
    }[reason] ??
    '산입 근거를 확인하세요.';

/// An owner-bound screen state. Successful writes are never repeated after a read failure.
class StudentAcademicController extends ChangeNotifier {
  StudentAcademicController(this.api);
  final StudentAcademicApi api;
  AcademicStudentWorkspace? workspace;
  AcademicStudentRequirements? requirements;
  AcademicStudentPreview? preview;
  AcademicStudentProgress? progress;
  bool loading = false, saving = false, loaded = false, _disposed = false;
  int _epoch = 0;
  String? error, message, requestId;
  List<String> fields = [];
  String? _method, _path;
  Map<String, Object?>? _body;
  bool get uncertain => _body != null;
  bool get disabled => loading || saving || uncertain || !loaded;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String? fieldError(String name) =>
      fields.any((f) => f.contains(name)) ? '이 입력 내용을 확인하세요.' : null;
  Future<void> load() async {
    if (_disposed || saving || uncertain) return;
    final epoch = ++_epoch;
    loading = true;
    loaded = false;
    error = null;
    _notify();
    try {
      final results = await Future.wait<Object>([
        api.workspace(),
        api.requirements(),
        api.preview(),
        api.progress(),
      ]);
      if (_disposed || epoch != _epoch) return;
      final w = results[0] as AcademicStudentWorkspace,
          r = results[1] as AcademicStudentRequirements;
      final p = results[2] as AcademicStudentPreview,
          credits = results[3] as AcademicStudentProgress;
      if (w.version != r.version ||
          w.version != p.version ||
          credits.activationId != r.activationId) {
        throw const FormatException('Academic state changed while loading');
      }
      workspace = w;
      requirements = r;
      preview = p;
      progress = credits;
      loaded = true;
    } catch (e) {
      if (!_disposed && epoch == _epoch) _failure(e);
    } finally {
      if (!_disposed && epoch == _epoch) {
        loading = false;
        _notify();
      }
    }
  }

  void _failure(Object e) {
    error = e is AuthFailure ? e.message : '학업 기준을 처리하지 못했습니다. 다시 확인하세요.';
    fields = e is AuthFailure ? e.fields : [];
    requestId = e is AuthFailure ? e.requestId : null;
  }

  Future<bool> send(
    String method,
    String path,
    Map<String, Object?> body,
  ) async {
    if (disabled) return false;
    _method = method;
    _path = path;
    _body = StudentAcademicApi.freeze(body);
    return retry();
  }

  Future<bool> retry() async {
    if (_disposed || saving || _body == null) return false;
    saving = true;
    error = null;
    fields = [];
    _notify();
    bool succeeded = false;
    try {
      await api.write(_method!, _path!, _body!);
      if (_disposed) return false;
      _body = null;
      succeeded = true;
      message = '저장했습니다.';
    } catch (e) {
      if (_disposed) return false;
      _failure(e);
      if (e is AuthFailure &&
          const [400, 401, 403, 404, 409, 422].contains(e.status)) {
        _body = null;
      }
    } finally {
      if (!_disposed) {
        saving = false;
        _notify();
      }
    }
    if (succeeded) await load();
    return succeeded;
  }

  Map<String, Object?> command(int version) => {
    'client_id': PersonalRecord.newId(),
    'expected_version': version,
  };
  Future<bool> activate() => send('POST', 'me/academic-requirements/activate', {
    ...command(preview!.version),
    'expected_digest': preview!.digest,
  });
  Future<bool> respond(
    AcademicStudentDocument doc,
    String itemId,
    bool? value,
    List<AcademicStudentRecord> records,
  ) => send('PUT', 'me/academic-requirements/${doc.id}/responses/$itemId', {
    ...command(doc.response(itemId)?.version ?? 0),
    'activation_id': requirements!.activationId,
    'value': value,
    'records': records.map((r) => r.toReference()).toList(),
  });
  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }
}
