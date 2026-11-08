import 'package:flutter/material.dart';

import 'assistant_api.dart';
import '../api/academic_guidance_models.dart';
import '../api/guidance_api.dart';
import '../api/rule_program_api.dart';
import '../api/rule_program_models.dart';
import '../auth/auth_api.dart';
import '../settings/ai_consent_preferences.dart';
import 'ai_record_catalog.dart';
import '../api/graduation_models.dart';
import '../auth/guidance_asset_gateway.dart';

enum AssistantMode {
  school('학교 질문', AiConsentFeature.schoolQuestion),
  personalized('내 자료로 질문', AiConsentFeature.personalizedQuestion);

  const AssistantMode(this.label, this.feature);
  final String label;
  final AiConsentFeature feature;
}

class AssistantTurn {
  AssistantTurn(
    this.question, {
    this.id = '',
    this.mode = AssistantMode.school,
    this.requestContext,
    this.records = const [],
  });
  final String id;
  final String question;
  final AssistantMode mode;
  final SchoolQueryContext? requestContext;
  final List<GuidanceRecordSelection> records;
  PersonalizedGuidanceResponse? personalized;
  AssistantResult? result;
  AssistantApiException? error;
  bool loading = true;
}

/// Session-only messages. Only the question and explicitly chosen school context
/// are sent; local records and mock authentication are not API credentials.
class AssistantConversation extends ChangeNotifier {
  AssistantConversation({
    AssistantGateway? api,
    this.guidanceApi,
    this.consent,
    this.loadRecords,
    this.registeredOnly = false,
    this.onOpenSettings,
    this.onOpenCareer,
  }) : _api = api ?? AssistantApi() {
    consent?.addListener(_consentChanged);
  }
  final GuidanceApi? guidanceApi;
  final AiConsentPreferences? consent;
  final Future<List<AiRecordOption>> Function()? loadRecords;
  final bool registeredOnly;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenCareer;
  static const criteriaKinds = <String, String>{
    'credits': 'minimum_credits',
    'courses': 'required_courses',
    'volunteer': 'minimum_volunteer_hours',
    'certificate': 'any_certificate',
    'thesis': 'thesis',
    'review': 'manual_review',
  };
  AcademicGuidance? guidance;
  OfficialProgramSelection? guidanceCriteria;
  String? criteriaError;
  bool get showingCriteria => criteriaKinds.containsKey(guidance?.nodeId);
  bool guidanceOpen = false, guidanceLoading = false, auditsLoading = false;
  String? guidanceError, guidanceAuditId;
  List<GraduationAuditHeader> auditOptions = const [];
  int _guidanceGeneration = 0;
  String get guidanceNodeId => guidance?.nodeId ?? 'home';
  String? get guidanceUnavailableReason {
    if (guidanceApi == null) return '학사 안내에 연결할 수 없습니다. 로그인 상태를 확인해 주세요.';
    return null;
  }

  void openCareer() => onOpenCareer?.call();
  Future<void> showGuidance() async {
    guidanceOpen = true;
    notifyListeners();
    await navigateGuidance(guidanceNodeId);
  }

  void closeGuidance() {
    guidanceOpen = false;
    notifyListeners();
  }

  Future<void> navigateGuidance(String id) async {
    if (_disposed || guidanceLoading) return;
    guidanceError = guidanceUnavailableReason;
    if (guidanceError != null) {
      notifyListeners();
      return;
    }
    final generation = ++_guidanceGeneration;
    guidanceLoading = true;
    notifyListeners();
    try {
      final node = await guidanceApi!.node(
        id,
        auditId: id == 'summary' ? guidanceAuditId : null,
      );
      if (_disposed || generation != _guidanceGeneration) return;
      guidance = node;
      guidanceCriteria = null;
      criteriaError = null;
      if (criteriaKinds.containsKey(node.nodeId)) {
        await _loadCriteria(generation);
      }
    } on AuthFailure catch (e) {
      if (!_disposed && generation == _guidanceGeneration) {
        guidanceError = e.status == 404
            ? '학사 안내 API를 찾을 수 없습니다. 서버가 최신 버전으로 실행 중인지 확인해 주세요.'
            : e.message;
      }
    } catch (_) {
      if (!_disposed && generation == _guidanceGeneration) {
        guidanceError = '안내 응답을 확인하지 못했습니다. 다시 시도해 주세요.';
      }
    } finally {
      if (!_disposed && generation == _guidanceGeneration) {
        guidanceLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadCriteria(int generation) async {
    final scope = context;
    if (!contextAvailable ||
        !scope.hasRegisteredSchool ||
        scope.curriculumId == null ||
        scope.admissionYear == null ||
        scope.track == null) {
      criteriaError = '학교·학과·교육과정·입학연도·이수경로를 설정하면 해당 기준을 볼 수 있습니다.';
      return;
    }
    try {
      final selected = OfficialSelectionContext(
        institutionId: scope.institutionId!,
        departmentId: scope.departmentId!,
        curriculumId: scope.curriculumId!,
        admissionYear: scope.admissionYear!,
        track: scope.track!,
      );
      final result = await OfficialProgramApi(guidanceApi!.api)
          .select(selected);
      if (_disposed || generation != _guidanceGeneration) return;
      if (result.context.toJson().toString() != selected.toJson().toString() ||
          result.programs.any(
            (p) =>
                p.institutionId != selected.institutionId ||
                (p.departmentId != null &&
                    p.departmentId != selected.departmentId) ||
                (p.curriculumId != null &&
                    p.curriculumId != selected.curriculumId),
          )) {
        throw const FormatException('Unexpected criteria scope');
      }
      guidanceCriteria = result;
    } catch (_) {
      if (!_disposed && generation == _guidanceGeneration) {
        criteriaError = '학교의 요건 기준을 읽지 못했습니다. 다시 읽거나 설정의 학업 정보를 확인해 주세요.';
      }
    }
  }

  Future<void> refreshAudits() async {
    if (_disposed || auditsLoading || guidanceUnavailableReason != null) return;
    if (!contextAvailable || !context.hasRegisteredSchool) {
      guidanceError = '본인 졸업감사를 보려면 설정에서 등록 학교·학과를 확인해 주세요.';
      notifyListeners();
      return;
    }
    final generation = _guidanceGeneration;
    auditsLoading = true;
    guidanceError = null;
    notifyListeners();
    try {
      final items = await guidanceApi!.audits(context.institutionId!);
      if (_disposed || generation != _guidanceGeneration) return;
      auditOptions = items
          .where(
            (r) =>
                r.context.institutionId == context.institutionId &&
                r.context.departmentId == context.departmentId &&
                r.context.curriculumId == context.curriculumId &&
                r.context.admissionYear == context.admissionYear &&
                r.context.track == context.track,
          )
          .toList();
    } catch (_) {
      if (!_disposed && generation == _guidanceGeneration) {
        guidanceError = '본인 졸업감사 이력을 읽지 못했습니다. 다시 읽어 주세요.';
      }
    } finally {
      if (!_disposed) {
        auditsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> selectAudit(String id) async {
    if (!auditOptions.any((a) => a.id == id) || guidanceLoading) return;
    guidanceAuditId = id;
    await navigateGuidance(guidanceNodeId);
  }

  Future<GuidanceAsset> loadGuidanceAsset(String id) async {
    final allowed =
        guidance?.cards.any(
              (c) =>
                  c.imageAssetId == id || c.sources.any((s) => s.assetId == id),
            ) ==
            true ||
        guidance?.source?.assetId == id;
    if (_disposed || guidanceUnavailableReason != null || !allowed) {
      throw const AuthFailure('현재 안내에 포함된 원문을 선택해 주세요.');
    }
    final generation = _guidanceGeneration;
    final value = await guidanceApi!.asset(id);
    if (_disposed || generation != _guidanceGeneration) {
      throw const AuthFailure('안내 문맥이 변경되었습니다. 원문을 다시 선택해 주세요.');
    }
    return value;
  }

  final AssistantGateway _api;
  final input = TextEditingController();
  final List<AssistantTurn> _turns = [];
  List<AssistantTurn> get turns => List.unmodifiable(_turns);
  SchoolQueryContext context = const SchoolQueryContext();
  bool sending = false;
  bool _disposed = false;
  bool get isClosed => _disposed;
  bool contextAvailable = true;
  void setContextAvailable(bool value) {
    if (contextAvailable == value || _disposed) return;
    contextAvailable = value;
    if (!value) {
      _guidanceGeneration++;
      guidanceLoading = false;
      guidance = null;
      guidanceCriteria = null;
      criteriaError = null;
      guidanceAuditId = null;
      auditOptions = const [];
    }
    _oncePermissions.clear();
    notifyListeners();
  }

  AssistantMode mode = AssistantMode.school;
  List<AiRecordOption> recordOptions = const [];
  final List<AiRecordOption> selectedRecords = [];
  bool recordsLoading = false;
  String? recordsError;
  String? submissionError;
  final _oncePermissions = <AssistantMode>{};
  bool get requiresConsent => registeredOnly;
  bool get permissionLoading => consent?.loading ?? false;
  String? get permissionError => consent?.error;
  bool allowsMode(AssistantMode value) =>
      !requiresConsent || consent?.allows(value.feature) == true;
  void _consentChanged() {
    if (!_disposed) notifyListeners();
  }

  void openSettings() => onOpenSettings?.call();
  void setMode(AssistantMode value) {
    if (sending || _disposed) return;
    mode = value;
    if (value == AssistantMode.personalized) guidanceOpen = false;
    _oncePermissions.clear();
    submissionError = null;
    notifyListeners();
  }

  Future<bool> permit(AssistantMode value, {required bool remember}) async {
    if (_disposed || consent == null) return false;
    await consent!.load();
    if (_disposed || consent!.loadFailed) return false;
    if (remember) return consent!.setAllowed(value.feature, true);
    _oncePermissions.add(value);
    return true;
  }

  Future<void> refreshPermission() async {
    await consent?.retry();
  }

  Future<void> refreshRecords() async {
    if (_disposed || recordsLoading || loadRecords == null) return;
    recordsLoading = true;
    recordsError = null;
    notifyListeners();
    try {
      final next = await loadRecords!();
      if (_disposed) return;
      recordOptions = next;
      final oldCount = selectedRecords.length;
      selectedRecords.removeWhere(
        (old) => !next.any((r) => r.key == old.key && r.version == old.version),
      );
      if (selectedRecords.length != oldCount) {
        recordsError = '변경되거나 삭제된 기록은 다시 선택해 주세요.';
      }
    } catch (_) {
      recordsError = '개인 기록을 읽지 못했습니다. 기존 선택은 유지했습니다. 다시 읽어 주세요.';
    } finally {
      recordsLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  void selectRecord(String key, bool selected) {
    if (_disposed || sending) return;
    _oncePermissions.clear();
    final option = recordOptions.where((r) => r.key == key).firstOrNull;
    if (option == null) return;
    if (selected) {
      if (selectedRecords.any((r) => r.key == key)) return;
      if (selectedRecords.length >= 20) {
        recordsError = '최대 20개까지 선택할 수 있습니다.';
        notifyListeners();
        return;
      }
      selectedRecords.add(option);
    } else {
      selectedRecords.removeWhere((r) => r.key == key);
    }
    notifyListeners();
  }

  int _nextTurnId = 0;
  String? get connectionError => null;
  bool get ready => true;

  void setContext(SchoolQueryContext value) {
    if (_disposed) return;
    if (context.catalogJson().toString() != value.catalogJson().toString()) {
      _guidanceGeneration++;
      guidanceLoading = false;
      guidance = null;
      guidanceCriteria = null;
      criteriaError = null;
      guidanceAuditId = null;
      auditOptions = const [];
    }
    _oncePermissions.clear();
    context = value;
    notifyListeners();
  }

  Future<void> send() async {
    final question = input.text.trim();
    if (question.isEmpty || sending) {
      _oncePermissions.clear();
      return;
    }
    if (_disposed) return;
    final turn = AssistantTurn(
      question,
      id: '${++_nextTurnId}',
      mode: mode,
      requestContext: context,
      records: List.unmodifiable(selectedRecords.map((r) => r.selection)),
    );
    if (!_validate(turn)) return;
    _turns.add(turn);
    await _query(turn);
  }

  Future<void> retry(AssistantTurn turn) async {
    if (sending || !_turns.contains(turn)) return;
    if (!_validate(turn)) return;
    await _query(turn);
  }

  bool _validate(AssistantTurn turn) {
    submissionError = null;
    if (registeredOnly && !contextAvailable) {
      submissionError = '학업 프로필을 읽는 중이거나 읽지 못했습니다. 설정에서 다시 확인해 주세요.';
    } else if (registeredOnly &&
        !(turn.requestContext ?? context).hasRegisteredSchool) {
      submissionError =
          '등록된 학교·학과가 필요합니다. 개인 기준·PDF 질문은 아직 지원하지 않습니다. 설정에서 확인해 주세요.';
    } else if (turn.question.runes.length > 4000) {
      submissionError = '질문은 4,000자 이내로 입력해 주세요.';
    } else if (turn.mode == AssistantMode.personalized &&
        turn.records.isEmpty) {
      submissionError = '질문에 사용할 내 기록을 선택해 주세요.';
    } else if (requiresConsent &&
        !allowsMode(turn.mode) &&
        !_oncePermissions.contains(turn.mode)) {
      submissionError = 'Google 외부 전송 동의를 확인해 주세요.';
    }
    if (submissionError != null) {
      _oncePermissions.clear();
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<void> _query(AssistantTurn turn) async {
    sending = true;
    turn.loading = true;
    turn.result = null;
    turn.personalized = null;
    turn.error = null;
    notifyListeners();
    try {
      _oncePermissions.remove(turn.mode);
      if (turn.mode == AssistantMode.personalized) {
        final saved = turn.requestContext ?? context;
        final api = guidanceApi;
        if (api == null) {
          throw const AssistantApiException(
            '맞춤 안내에 연결할 수 없습니다. 로그인 상태를 확인해 주세요.',
          );
        }
        final result = await api.personalized(
          PersonalizedGuidanceRequest(
            question: turn.question,
            context: GuidanceSchoolContext(
              institutionId: saved.institutionId!,
              departmentId: saved.departmentId!,
              curriculumId: saved.curriculumId,
              admissionYear: saved.admissionYear,
              track: saved.track,
            ),
            records: turn.records,
            externalProcessingConsent: true,
          ),
        );
        if (_disposed) return;
        turn.personalized = result;
        if (result.status == 'grounded' && input.text.trim() == turn.question) {
          input.clear();
        }
        return;
      }
      final result = await _api.query(
        turn.question,
        registeredOnly ? turn.requestContext ?? context : context,
      );
      if (_disposed) return;
      turn.result = result;
      if (result.status == AssistantStatus.grounded ||
          result.status == AssistantStatus.insufficientEvidence) {
        if (input.text.trim() == turn.question) input.clear();
      }
    } on AssistantApiException catch (error) {
      if (_disposed) return;
      turn.error = error;
    } on AuthFailure catch (error) {
      if (_disposed) return;
      turn.error = AssistantApiException(
        error.message,
        fields: error.fields,
        requestId: error.requestId,
      );
    } catch (_) {
      if (_disposed) return;
      turn.error = const AssistantApiException('질의를 처리하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (!_disposed) {
        sending = false;
        turn.loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    consent?.removeListener(_consentChanged);
    _api.close();
    input.dispose();
    super.dispose();
  }
}
