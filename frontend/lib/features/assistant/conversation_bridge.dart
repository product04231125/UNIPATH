import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'assistant_api.dart';
import 'assistant_conversation.dart';
import 'ai_record_catalog.dart';
import '../api/academic_guidance_models.dart';
import '../api/graduation_models.dart';
import '../api/rule_program_models.dart';
import '../auth/guidance_asset_gateway.dart';

Map<String, dynamic> _contextSnapshot(SchoolQueryContext context) => {
  ...context.toJson(),
  ...context.catalogJson(),
};
SchoolQueryContext _parseContext(Map<String, dynamic> ctx) =>
    SchoolQueryContext(
      institution: ctx['institution'] as String?,
      department: ctx['department'] as String?,
      admissionYear: ctx['admission_year'] as int?,
      track: ctx['track'] as String?,
      institutionId: ctx['institution_id'] as String?,
      departmentId: ctx['department_id'] as String?,
      curriculumId: ctx['curriculum_id'] as String?,
    );

Map<String, dynamic> conversationSnapshot(
  AssistantConversation conversation,
  int revision,
) => {
  'revision': revision,
  'input': conversation.input.text,
  'selection_base': conversation.input.selection.baseOffset,
  'selection_extent': conversation.input.selection.extentOffset,
  'context': _contextSnapshot(conversation.context),
  'registered_only': conversation.registeredOnly,
  'context_available': conversation.contextAvailable,
  'mode': conversation.mode.name,
  'permissions': [
    for (final mode in AssistantMode.values)
      if (conversation.allowsMode(mode)) mode.name,
  ],
  'permission_loading': conversation.permissionLoading,
  'permission_error': conversation.permissionError,
  'records': conversation.recordOptions.map((r) => r.toJson()).toList(),
  'selected_records': conversation.selectedRecords
      .map((r) => r.toJson())
      .toList(),
  'records_loading': conversation.recordsLoading,
  'records_error': conversation.recordsError,
  'submission_error': conversation.submissionError,
  'guidance': conversation.guidance?.toJson(),
  'guidance_criteria': conversation.guidanceCriteria?.toJson(),
  'criteria_error': conversation.criteriaError,
  'guidance_node_id': conversation.guidanceNodeId,
  'guidance_open': conversation.guidanceOpen,
  'guidance_loading': conversation.guidanceLoading,
  'guidance_error': conversation.guidanceError,
  'guidance_unavailable': conversation.guidanceUnavailableReason,
  'guidance_audit_id': conversation.guidanceAuditId,
  'audits_loading': conversation.auditsLoading,
  'audits': conversation.auditOptions.map((a) => a.toJson()).toList(),
  'sending': conversation.sending,
  'turns': [
    for (final t in conversation.turns)
      {
        'id': t.id,
        'question': t.question,
        'loading': t.loading,
        'mode': t.mode.name,
        'request_context': t.requestContext == null
            ? null
            : _contextSnapshot(t.requestContext!),
        'records': t.records.map((r) => r.toJson()).toList(),
        'personalized': t.personalized?.toJson(),
        'result': t.result?.toJson(),
        'error': t.error == null
            ? null
            : {
                'message': t.error!.message,
                'request_id': t.error!.requestId,
                'fields': t.error!.fields,
              },
      },
  ],
};

/// The main window remains the only owner of HTTP requests and conversation.
class ConversationBridge {
  ConversationBridge(this.conversation, this.publish) {
    conversation.addListener(_changed);
    conversation.input.addListener(_changed);
  }
  final AssistantConversation conversation;
  final Future<void> Function(Map<String, dynamic>) publish;
  final Map<String, Map<String, dynamic>> _commands = {};
  int _revision = 0;
  bool _disposed = false;
  final _permissionResults = <String, bool>{};
  Map<String, dynamic> read() => {
    ...conversationSnapshot(conversation, _revision),
    'permission_results': {..._permissionResults},
  };
  void _changed() {
    if (_disposed) return;
    _revision++;
    unawaited(publish(read()).catchError((Object _) {}));
  }

  Map<String, dynamic> command(Map<String, dynamic> command) {
    if (_disposed) throw StateError('Conversation bridge is closed');
    final id = command['command_id'] as String;
    if (_commands.containsKey(id)) return read();
    final action = command['action'] as String;
    if (![
      'input',
      'send',
      'retry',
      'mode',
      'records',
      'select_record',
      'permit',
      'permission_reload',
      'settings',
      'guidance_open',
      'guidance_close',
      'guidance_node',
      'guidance_audits',
      'guidance_audit',
      'career',
    ].contains(action)) {
      throw const FormatException('Unknown conversation command');
    }
    // Remember before starting async work: a lost acknowledgement cannot replay it.
    _commands[id] = command;
    if (command['input'] != null) {
      final text = command['input'] as String;
      conversation.input.value = TextEditingValue(
        text: text,
        selection: TextSelection(
          baseOffset: (command['selection_base'] as int).clamp(-1, text.length),
          extentOffset: (command['selection_extent'] as int).clamp(
            -1,
            text.length,
          ),
        ),
      );
    }
    if (action == 'send') unawaited(conversation.send());
    if (action == 'mode') {
      conversation.setMode(
        AssistantMode.values.byName(command['mode'] as String),
      );
    }
    if (action == 'records') unawaited(conversation.refreshRecords());
    if (action == 'select_record') {
      conversation.selectRecord(
        command['key'] as String,
        command['selected'] as bool,
      );
    }
    if (action == 'permission_reload') {
      unawaited(conversation.refreshPermission());
    }
    if (action == 'settings') conversation.openSettings();
    if (action == 'guidance_open') unawaited(conversation.showGuidance());
    if (action == 'guidance_close') conversation.closeGuidance();
    if (action == 'guidance_node') {
      unawaited(conversation.navigateGuidance(command['node_id'] as String));
    }
    if (action == 'guidance_audits') unawaited(conversation.refreshAudits());
    if (action == 'guidance_audit') {
      unawaited(conversation.selectAudit(command['audit_id'] as String));
    }
    if (action == 'career') conversation.openCareer();
    if (action == 'permit') {
      unawaited(
        conversation
            .permit(
              AssistantMode.values.byName(command['mode'] as String),
              remember: command['remember'] as bool,
            )
            .then(
              (success) {
                _permissionResults[id] = success;
                _changed();
              },
              onError: (Object _) {
                _permissionResults[id] = false;
                _changed();
              },
            ),
      );
    }
    if (action == 'retry') {
      final turns = conversation.turns.where((t) => t.id == command['turn_id']);
      if (turns.isNotEmpty) unawaited(conversation.retry(turns.first));
    }
    return read();
  }

  Future<Map<String, dynamic>> dispatch(Map<String, dynamic> value) async {
    if (value['action'] != 'asset') return command(value);
    if (_disposed) throw StateError('Conversation bridge is closed');
    final id = value['asset_id'] as String;
    final asset = await conversation.loadGuidanceAsset(id);
    if (_disposed) throw StateError('Conversation bridge is closed');
    return {
      ...read(),
      'asset': {
        'id': id,
        'type': asset.contentType,
        'bytes': base64Encode(asset.bytes),
      },
    };
  }

  void dispose() {
    _disposed = true;
    conversation.removeListener(_changed);
    conversation.input.removeListener(_changed);
  }
}

/// A child renders snapshots; it never owns or cancels the owner's HTTP client.
class RemoteConversation extends AssistantConversation {
  RemoteConversation({
    required this.request,
    required Stream<Map<String, dynamic>> changes,
  }) {
    _subscription = changes.listen(_receive);
    input.addListener(_inputChanged);
  }
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>?) request;
  late final StreamSubscription<Map<String, dynamic>> _subscription;
  final List<AssistantTurn> _remoteTurns = [];
  final List<Map<String, dynamic>> _pending = [];
  final String _clientId = DateTime.now().microsecondsSinceEpoch.toString();
  int _sequence = 0;
  int _revision = -1;
  bool _applying = false;
  bool _closed = false;
  bool _ready = false;
  String? _error;
  bool _registeredOnly = false;
  bool _permissionLoading = true;
  String? _permissionError;
  String _remoteGuidanceNode = 'home';
  @override
  String get guidanceNodeId => guidance?.nodeId ?? _remoteGuidanceNode;
  String? _guidanceUnavailable;
  @override
  String? get guidanceUnavailableReason => _guidanceUnavailable;
  final _allowedModes = <AssistantMode>{};
  final _permissionWaiters = <String, Completer<bool>>{};
  @override
  bool get registeredOnly => _registeredOnly;
  @override
  bool get requiresConsent => _registeredOnly;
  @override
  bool get permissionLoading => _permissionLoading;
  @override
  String? get permissionError => _permissionError;
  @override
  bool allowsMode(AssistantMode value) =>
      !_registeredOnly || _allowedModes.contains(value);
  Future<void>? _flushing;
  @override
  List<AssistantTurn> get turns => List.unmodifiable(_remoteTurns);
  @override
  bool get ready => _ready;
  @override
  String? get connectionError => _error;

  Future<void> load() async {
    try {
      await flush();
      if (_pending.isNotEmpty) return;
      _receive(await request(null));
    } catch (_) {
      _failed();
    }
  }

  void _failed() {
    if (_closed) return;
    _error = '메인 창과 연결하지 못했습니다. 작성 내용을 유지하고 다시 연결해 주세요.';
    notifyListeners();
  }

  void _receive(Map<String, dynamic> value) {
    if (_closed || (value['revision'] as int) < _revision) return;
    final rawTurns = value['turns'] as List;
    final parsed = [
      for (final raw in rawTurns)
        _parseTurn(Map<String, dynamic>.from(raw as Map)),
    ];
    final ctx = Map<String, dynamic>.from(value['context'] as Map);
    _revision = value['revision'] as int;
    _remoteTurns
      ..clear()
      ..addAll(parsed);
    context = _parseContext(ctx);
    _registeredOnly = value['registered_only'] == true;
    contextAvailable = value['context_available'] != false;
    mode = AssistantMode.values.byName(value['mode'] as String? ?? 'school');
    _permissionLoading = value['permission_loading'] == true;
    _permissionError = value['permission_error'] as String?;
    _allowedModes
      ..clear()
      ..addAll(
        (value['permissions'] as List? ?? []).map(
          (v) => AssistantMode.values.byName(v as String),
        ),
      );
    recordOptions = (value['records'] as List? ?? [])
        .map(
          (v) => AiRecordOption.fromJson(Map<String, dynamic>.from(v as Map)),
        )
        .toList();
    selectedRecords
      ..clear()
      ..addAll(
        (value['selected_records'] as List? ?? []).map(
          (v) => AiRecordOption.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
      );
    recordsLoading = value['records_loading'] == true;
    recordsError = value['records_error'] as String?;
    submissionError = value['submission_error'] as String?;
    guidance = value['guidance'] == null
        ? null
        : AcademicGuidance.fromJson(
            Map<String, dynamic>.from(value['guidance'] as Map),
          );
    guidanceCriteria = value['guidance_criteria'] == null
        ? null
        : OfficialProgramSelection.fromJson(
            Map<String, dynamic>.from(value['guidance_criteria'] as Map),
          );
    criteriaError = value['criteria_error'] as String?;
    _remoteGuidanceNode = value['guidance_node_id'] as String? ?? 'home';
    guidanceOpen = value['guidance_open'] == true;
    guidanceLoading = value['guidance_loading'] == true;
    guidanceError = value['guidance_error'] as String?;
    _guidanceUnavailable = value['guidance_unavailable'] as String?;
    guidanceAuditId = value['guidance_audit_id'] as String?;
    auditsLoading = value['audits_loading'] == true;
    auditOptions = (value['audits'] as List? ?? [])
        .map(
          (v) => GraduationAuditHeader.fromJson(
            Map<String, dynamic>.from(v as Map),
          ),
        )
        .toList();
    final permissions = Map<String, dynamic>.from(
      value['permission_results'] as Map? ?? {},
    );
    for (final id in _permissionWaiters.keys.toList()) {
      if (permissions.containsKey(id)) {
        _permissionWaiters.remove(id)!.complete(permissions[id] == true);
      }
    }
    sending = value['sending'] as bool;
    // Keep edits whose IPC acknowledgement has not arrived yet.
    if (_pending.isEmpty) {
      _applying = true;
      final text = value['input'] as String;
      input.value = TextEditingValue(
        text: text,
        selection: TextSelection(
          baseOffset: (value['selection_base'] as int).clamp(-1, text.length),
          extentOffset: (value['selection_extent'] as int).clamp(
            -1,
            text.length,
          ),
        ),
      );
      _applying = false;
    }
    _ready = true;
    _error = null;
    notifyListeners();
  }

  AssistantTurn _parseTurn(Map<String, dynamic> raw) {
    final turn = AssistantTurn(
      raw['question'] as String,
      id: raw['id'] as String,
      mode: AssistantMode.values.byName(raw['mode'] as String? ?? 'school'),
      requestContext: raw['request_context'] == null
          ? null
          : _parseContext(
              Map<String, dynamic>.from(raw['request_context'] as Map),
            ),
      records: (raw['records'] as List? ?? [])
          .map(
            (v) => GuidanceRecordSelection.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          )
          .toList(),
    );
    turn.loading = raw['loading'] as bool;
    if (raw['personalized'] != null) {
      turn.personalized = PersonalizedGuidanceResponse.fromJson(
        Map<String, dynamic>.from(raw['personalized'] as Map),
      );
    }
    if (raw['result'] != null) {
      turn.result = AssistantResult.fromJson(
        Map<String, dynamic>.from(raw['result'] as Map),
      );
    }
    if (raw['error'] != null) {
      final error = Map<String, dynamic>.from(raw['error'] as Map);
      turn.error = AssistantApiException(
        error['message'] as String,
        requestId: error['request_id'] as String?,
        fields: List<String>.from(error['fields'] as List),
      );
    }
    return turn;
  }

  void _inputChanged() {
    if (!_applying && _ready && !_closed) _enqueue('input');
  }

  String _enqueue(
    String action, [
    String? turnId,
    Map<String, dynamic> extra = const {},
  ]) {
    final id = '$_clientId-${++_sequence}';
    _pending.add({
      'command_id': id,
      'action': action,
      'input': input.text,
      'selection_base': input.selection.baseOffset,
      'selection_extent': input.selection.extentOffset,
      'turn_id': turnId,
      ...extra,
    });
    unawaited(flush());
    return id;
  }

  @override
  void setMode(AssistantMode value) {
    if (_ready && !sending) _enqueue('mode', null, {'mode': value.name});
  }

  @override
  Future<void> refreshRecords() async {
    if (_ready) {
      _enqueue('records');
      await flush();
    }
  }

  @override
  void selectRecord(String key, bool selected) {
    if (_ready && !sending) {
      _enqueue('select_record', null, {'key': key, 'selected': selected});
    }
  }

  @override
  void openSettings() {
    if (_ready) _enqueue('settings');
  }

  @override
  void openCareer() {
    if (_ready) _enqueue('career');
  }

  @override
  Future<void> showGuidance() async {
    if (_ready) {
      _enqueue('guidance_open');
      await flush();
    }
  }

  @override
  void closeGuidance() {
    if (_ready) _enqueue('guidance_close');
  }

  @override
  Future<void> navigateGuidance(String id) async {
    if (_ready) {
      _enqueue('guidance_node', null, {'node_id': id});
      await flush();
    }
  }

  @override
  Future<void> refreshAudits() async {
    if (_ready) {
      _enqueue('guidance_audits');
      await flush();
    }
  }

  @override
  Future<void> selectAudit(String id) async {
    if (_ready) {
      _enqueue('guidance_audit', null, {'audit_id': id});
      await flush();
    }
  }

  @override
  Future<GuidanceAsset> loadGuidanceAsset(String id) async {
    if (!_ready || _closed) throw StateError('Main conversation unavailable');
    final result = await request({
      'command_id': '$_clientId-${++_sequence}',
      'action': 'asset',
      'asset_id': id,
    });
    if (_closed) throw StateError('Conversation closed');
    final asset = Map<String, dynamic>.from(result['asset'] as Map);
    if (asset['id'] != id ||
        !{'application/pdf', 'image/jpeg'}.contains(asset['type'])) {
      throw const FormatException('Invalid asset');
    }
    return GuidanceAsset(
      base64Decode(asset['bytes'] as String),
      asset['type'] as String,
    );
  }

  @override
  Future<void> refreshPermission() async {
    if (_ready) {
      _enqueue('permission_reload');
      await flush();
    }
  }

  @override
  Future<bool> permit(AssistantMode value, {required bool remember}) async {
    if (!_ready || _closed) return false;
    final id = _enqueue('permit', null, {
      'mode': value.name,
      'remember': remember,
    });
    final completed = Completer<bool>();
    _permissionWaiters[id] = completed;
    try {
      return await completed.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      _permissionWaiters.remove(id);
      _failed();
      return false;
    }
  }

  Future<void> flush() =>
      _flushing ??= _drain().whenComplete(() => _flushing = null);
  Future<void> _drain() async {
    while (_pending.isNotEmpty && !_closed) {
      try {
        final snapshot = await request(_pending.first);
        if (_closed) return;
        _pending.removeAt(0);
        _receive(snapshot);
      } catch (_) {
        _failed();
        return;
      }
    }
  }

  @override
  Future<void> send() async {
    if (!_ready || sending) return;
    _enqueue('send');
    await flush();
  }

  @override
  Future<void> retry(AssistantTurn turn) async {
    if (!_ready || sending) return;
    _enqueue('retry', turn.id);
    await flush();
  }

  Future<bool> prepareClose() async {
    await flush();
    return _pending.isEmpty;
  }

  @override
  void dispose() {
    _closed = true;
    for (final waiter in _permissionWaiters.values) {
      if (!waiter.isCompleted) waiter.complete(false);
    }
    _permissionWaiters.clear();
    _subscription.cancel();
    input.removeListener(_inputChanged);
    super.dispose();
  }
}
