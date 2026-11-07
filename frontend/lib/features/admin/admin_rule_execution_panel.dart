import 'dart:convert';

import 'package:flutter/material.dart';

import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/feature_actions.dart';
import '../../shared/widgets/feature_line.dart';
import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/responsive_panels.dart';
import '../../shared/widgets/field_label.dart';
import '../../shared/widgets/field_requirement.dart';
import '../api/rule_program_api.dart';
import '../api/rule_program_models.dart';
import '../auth/auth_api.dart';
import '../graduation/personal_calculation_draft.dart';
import 'admin_models.dart';
import 'admin_repository.dart';
import 'remote_admin_repository.dart';
import 'admin_requirement_draft.dart';

class AdminRuleExecutionPanel extends StatefulWidget {
  const AdminRuleExecutionPanel({
    super.key,
    required this.repository,
    required this.actorId,
    required this.schoolId,
    required this.ruleType,
    required this.description,
    required this.rule,
    required this.metadataDirty,
    required this.onBusy,
    required this.onChanged,
  });
  final AdminRepository repository;
  final String actorId, schoolId, ruleType, description;
  final AdminRecord? rule;
  final bool metadataDirty;
  final ValueChanged<bool> onBusy;
  final VoidCallback onChanged;
  @override
  State<AdminRuleExecutionPanel> createState() =>
      AdminRuleExecutionPanelState();
}

class AdminRuleExecutionPanelState extends State<AdminRuleExecutionPanel> {
  final _form = GlobalKey<FormState>();
  final _values = <String, String>{};
  final _drafts = <String, AdminRequirementDraft>{};
  final _lines = <TextEditingController>[TextEditingController()];
  List<OfficialProgramHeader> _programs = [];
  OfficialProgramView? _existing;
  String _programId = '';
  bool _busy = false, _uncertain = false, _conflict = false, _reloaded = false;
  int _revision = 0, _inputRevision = 0;
  String? _error, _message;
  List<String> _serverFields = [];
  late String _initial;
  AdminRequirementDraft get draft =>
      _drafts.putIfAbsent(widget.ruleType, AdminRequirementDraft.new);
  ApiGateway? get _gateway => widget.repository is RemoteAdminRepository
      ? (widget.repository as RemoteAdminRepository).api
      : null;
  AdminRecord? get rule =>
      widget.repository.records
          .where((r) => r.id == widget.rule?.id)
          .firstOrNull ??
      widget.rule;
  AdminRecord? get parent => (rule?.value('ruleSetId').isNotEmpty ?? false)
      ? widget.repository.records
            .where((r) => r.id == rule!.value('ruleSetId'))
            .firstOrNull
      : rule;
  bool get ready =>
      parent?.status == 'applied' &&
      rule?.status == 'applied' &&
      (parent!.kind != AdminKind.ruleSet ||
          widget.repository.records
              .where(
                (r) =>
                    r.kind == AdminKind.rule &&
                    r.value('ruleSetId') == parent!.id,
              )
              .every((r) => r.status == 'applied'));
  String get _fingerprint => jsonEncode({
    'values': {
      for (final e in _values.entries)
        if (e.value.isNotEmpty) e.key: e.value,
    },
    'drafts': {
      for (final e in _drafts.entries)
        if (e.value.values.values.any((v) => v.isNotEmpty) ||
            e.value.selected.isNotEmpty ||
            e.value.observations.values.any(
              (v) => v.values.any((s) => s.isNotEmpty),
            ) ||
            !e.value.approval)
          e.key: {
            'values': e.value.values,
            'selected': e.value.selected.toList()..sort(),
            'observations': e.value.observations,
            'references': e.value.referenceVersions,
            'approval': e.value.approval,
          },
    },
    'lines': [for (final line in _lines) line.text],
  });
  bool get dirty => _fingerprint != _initial;
  bool get saving => _busy;
  @override
  void initState() {
    super.initState();
    draft;
    _initial = _fingerprint;
  }

  @override
  void dispose() {
    _revision++;
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _replaceLines(List<String> lines) {
    for (final line in _lines) {
      line.dispose();
    }
    _lines
      ..clear()
      ..addAll([
        for (final line in lines.isEmpty ? const [''] : lines)
          TextEditingController(text: line),
      ]);
  }

  @override
  void didUpdateWidget(AdminRuleExecutionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final contextChanged =
        oldWidget.repository != widget.repository ||
        oldWidget.actorId != widget.actorId ||
        oldWidget.schoolId != widget.schoolId;
    final ruleChanged = oldWidget.rule?.id != widget.rule?.id;
    if (!contextChanged && !ruleChanged) return;
    // A newly saved rule replaces an empty id with the server id in the same
    // session. Keep the typed execution input; only a school/actor/repository
    // switch is a different target.
    _revision++;
    if (contextChanged) {
      _inputRevision++;
      _values.clear();
      _drafts.clear();
      _replaceLines(const ['']);
    }
    _programs = [];
    _programId = '';
    _existing = null;
    _uncertain = false;
    _conflict = false;
    _reloaded = false;
    _error = null;
    _message = null;
    _serverFields = [];
    if (contextChanged) {
      draft;
      _initial = _fingerprint;
    }
  }

  void _ensure() {
    final target =
        rule ??
        AdminRecord(
          id: '',
          kind: AdminKind.rule,
          values: {'institutionId': widget.schoolId},
        );
    if (!mounted ||
        !widget.repository.active(widget.actorId) ||
        !widget.repository.canWrite(widget.actorId, target)) {
      throw const AuthFailure(
        '관리 권한이 변경되었습니다. 다시 로그인하거나 자료를 읽어주세요.',
        status: 403,
      );
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    final revision = _revision;
    setState(() {
      _busy = true;
      _error = null;
      _serverFields = [];
    });
    widget.onBusy(true);
    try {
      _ensure();
      await action();
      if (!mounted || revision != _revision) return;
      _ensure();
    } catch (e) {
      if (mounted && revision == _revision) {
        _error = e is AuthFailure
            ? e.message
            : e is FormatException
            ? e.message
            : e is StateError
            ? e.message
            : '처리하지 못했습니다. 입력을 유지했습니다. 다시 읽거나 재시도하세요.';
        if (e is AuthFailure) {
          _serverFields = e.fields;
          if (e.status == 401 || e.status == 403) {
            _programs = [];
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusy(false);
      }
    }
  }

  Future<void> _load() => _run(() async {
    final api = _gateway;
    if (api == null) return;
    final revision = _revision;
    final programs = <OfficialProgramHeader>[];
    final seen = <String>{};
    String? cursor;
    if (ready) {
      do {
        final page = await OfficialProgramAdminApi(api).list(
          institutionId: widget.schoolId,
          ruleSetId: parent!.kind == AdminKind.ruleSet ? parent!.id : null,
          ruleId: parent!.kind == AdminKind.rule ? parent!.id : null,
          status: 'draft',
          cursor: cursor,
        );
        _ensure();
        if (revision != _revision) return;
        programs.addAll(
          page.items.where(
            (p) =>
                p.institutionId == widget.schoolId &&
                p.status == 'draft' &&
                p.sourceVersion == parent!.version &&
                (p.ruleSetId ?? p.ruleId) == parent!.id,
          ),
        );
        cursor = page.nextCursor;
        if (cursor != null && !seen.add(cursor)) {
          throw const FormatException('실행 초안 목록이 반복됩니다. 다시 읽어주세요.');
        }
      } while (cursor != null);
    }
    _programs = programs;
    _reloaded = true;
    _message = _uncertain || _conflict
        ? '서버 목록을 읽었습니다. 저장된 초안을 선택해 내용을 확인하세요.'
        : '실행 초안 목록을 읽었습니다.';
  });
  Future<void> _selectProgram(String id) async {
    if (_busy || (id == _programId && !_uncertain && !_conflict)) return;
    final revision = _revision;
    if (id.isNotEmpty && dirty && !await confirmInputDiscardAllowsLeave(context)) return;
    if (!mounted || revision != _revision) return;
    await _run(() async {
      if (id.isEmpty) {
        _existing = null;
        _programId = '';
        _uncertain = false;
        _conflict = false;
        return;
      }
      final value = await OfficialProgramAdminApi(_gateway!).get(id);
      if (!mounted || revision != _revision) return;
      _ensure();
      if (value.status != 'draft' ||
          value.sourceVersion != parent!.version ||
          (value.ruleSetId ?? value.ruleId) != parent!.id ||
          value.institutionId != widget.schoolId) {
        throw const FormatException('현재 요건의 실행 초안이 아닙니다. 다시 선택하세요.');
      }
      final entry = value.rules.where((r) => r.ruleId == rule!.id).firstOrNull;
      _values.addAll({
        'yearFrom': '${value.admissionYearFrom}',
        'yearTo': '${value.admissionYearTo}',
        'tracks': value.tracks.join(', '),
      });
      final condition = entry?.condition;
      _replaceLines(
        condition is OfficialManualCriterion
            ? condition.instruction.split('\n')
            : const [''],
      );
      _inputRevision++;
      _existing = value;
      _programId = id;
      _uncertain = false;
      _conflict = false;
      _initial = _fingerprint;
      _message = '실행 초안을 불러왔습니다. 다른 요건의 조건은 유지합니다.';
    });
  }

  Future<void> _apply() async {
    if (_busy || parent == null || widget.metadataDirty) return;
    final revision = _revision;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('요건을 검토·적용할까요?'),
        content: Text(
          parent!.kind == AdminKind.ruleSet
              ? '이 규칙 묶음의 모든 요건을 함께 적용합니다.'
              : '저장한 요건 설명을 적용합니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('검토·적용'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted || revision != _revision) return;
    await _run(() async {
      await widget.repository.apply(widget.actorId, parent!.id);
      if (!mounted || revision != _revision) return;
      _message = '요건이 적용되었습니다. 이제 실행 조건 초안을 저장할 수 있습니다.';
    });
  }

  bool validateForMetadata() => _form.currentState?.validate() ?? true;
  Future<void> _save() => _run(() async {
    final revision = _revision;
    if (!ready ||
        widget.metadataDirty ||
        _gateway == null ||
        _uncertain ||
        _conflict) {
      return;
    }
    if (!(_form.currentState?.validate() ?? false)) return;
    final from = int.parse(_values['yearFrom']!);
    final to = int.parse(_values['yearTo']!);
    if (to < from || to - from >= 200) {
      throw const FormatException('적용 입학연도는 순서대로 200년 미만 범위로 입력하세요.');
    }
    final tracks = (_values['tracks'] ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (tracks.isEmpty ||
        tracks.length > 32 ||
        tracks.toSet().length != tracks.length ||
        tracks.any((s) => s.length > 64)) {
      throw const FormatException('적용할 학생 구분을 중복 없이 1~32개 입력하세요. 각 64자 이내입니다.');
    }
    final lines = [
      for (final line in _lines)
        if (line.text.trim().isNotEmpty) line.text.trim(),
    ];
    final instruction = lines.join('\n');
    if (lines.isEmpty || lines.length > 32 || instruction.length > 500) {
      throw const FormatException('규정 줄을 1~32개 입력하세요. 전체를 500자 이내로 적으세요.');
    }
    final condition = OfficialManualCriterion(
      kind: 'manual_review',
      instruction: instruction,
    );
    final entry = OfficialProgramRuleInput(
      ruleId: rule!.id,
      expectedVersion: rule!.version,
      condition: condition,
      evidenceChunkIds: const [],
    );
    final old = _existing;
    if (old != null &&
        (old.sourceVersion != parent!.version || old.status != 'draft')) {
      throw const FormatException('원본 요건이나 실행 초안이 바뀌었습니다. 다시 읽어주세요.');
    }
    final rules = [
      if (old != null)
        for (final r in old.rules.where((r) => r.ruleId != rule!.id))
          OfficialProgramRuleInput(
            ruleId: r.ruleId,
            expectedVersion: r.sourceVersion,
            condition: r.condition,
            evidenceChunkIds: r.evidence.map((e) => e.chunkId).toList(),
          ),
      entry,
    ];
    try {
      final api = OfficialProgramAdminApi(_gateway!);
      final saved = old == null
          ? await api.create(
              OfficialProgramCreate(
                admissionYearFrom: from,
                admissionYearTo: to,
                tracks: tracks,
                rules: rules,
                ruleSetId: parent!.kind == AdminKind.ruleSet
                    ? parent!.id
                    : null,
                ruleId: parent!.kind == AdminKind.rule ? parent!.id : null,
                expectedSourceVersion: parent!.version,
              ),
            )
          : await api.replace(
              old.id,
              OfficialProgramReplace(
                admissionYearFrom: from,
                admissionYearTo: to,
                tracks: tracks,
                rules: rules,
                expectedVersion: old.version,
              ),
            );
      if (!mounted || revision != _revision) return;
      _ensure();
      if (saved.status != 'draft' ||
          (saved.ruleSetId ?? saved.ruleId) != parent!.id ||
          saved.institutionId != widget.schoolId ||
          saved.sourceVersion != parent!.version ||
          !saved.rules.any(
            (r) => r.ruleId == rule!.id && r.sourceVersion == rule!.version,
          )) {
        throw const FormatException('요청과 다른 실행 초안입니다. 서버 목록을 다시 확인하세요.');
      }
      _existing = saved;
      _programId = saved.id;
      _initial = _fingerprint;
      _message = '한 줄 요건을 저장했습니다. 아직 승인되지 않았습니다.';
    } on AuthFailure catch (e) {
      if (!mounted || revision != _revision) return;
      _reloaded = false;
      _uncertain = e.status == null || e.status! >= 500;
      _conflict = e.status == 409;
      rethrow;
    } on FormatException {
      if (!mounted || revision != _revision) return;
      _reloaded = false;
      _uncertain = true;
      rethrow;
    }
  });
  Widget _text(
    Map<String, String> values,
    String key,
    String label, {
    bool required = true,
    bool number = false,
    bool year = false,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: FieldLabel(
      label: fieldRequirementLabel(label, required: required),
      child: Semantics(
        label: label,
        child: TextFormField(
          key: ValueKey(
            'execution-$key-${identityHashCode(values)}-$_inputRevision',
          ),
          initialValue: values[key] ?? '',
          enabled: !_busy && !_uncertain && !_conflict,
          decoration: InputDecoration(
            hintText: hint,
            errorText:
                _serverFields.any(
                  (f) =>
                      f.split('.').last ==
                          (const {
                                'yearFrom': 'admission_year_from',
                                'yearTo': 'admission_year_to',
                                'minimumCredits': 'minimum_credits',
                                'minimumGradePoints': 'minimum_grade_points',
                                'comparisonGradeScale':
                                    'comparison_grade_scale',
                                'thesisType': 'thesis_type',
                                'acceptedGrades': 'accepted_grades',
                              }[key] ??
                              key) ||
                      key == 'minimum' && f.endsWith('.minimum'),
                )
                ? '서버에서 이 입력을 확인해 달라고 요청했습니다.'
                : null,
          ),
          keyboardType: number || year
              ? TextInputType.number
              : TextInputType.text,
          onChanged: (v) {
            setState(() => values[key] = v);
            widget.onChanged();
          },
          validator: (v) => year
              ? (RegExp(r'^[1-9]\d{3}$').hasMatch(v?.trim() ?? '')
                    ? null
                    : '네 자리 입학연도를 입력하세요.')
              : number
              ? validateCalculationAmount(v, optional: !required)
              : (required && (v?.trim().isEmpty ?? true)
                    ? '$label 입력이 필요합니다.'
                    : (v?.length ?? 0) >
                          (key == 'tracks'
                              ? 2080
                              : key == 'acceptedGrades'
                              ? 2580
                              : 128)
                    ? '입력 길이를 확인하세요.'
                    : null),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (rule != null && !widget.repository.canRead(widget.actorId, rule!)) {
      return const Text('현재 계정으로 이 요건을 관리할 수 없습니다.');
    }
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 24),
          FeatureLine.section(
            text: '한 줄 요건',
            trailing: _gateway == null
                ? null
                : FeatureLine.reload(
                    onPressed: _busy ? null : _load,
                    label: '초안 다시 읽기',
                  ),
          ),
          const Text(
            '학교, 학과, 입학연도에 해당하는 규정 문장을 줄로 적습니다. 학점, 활동, 자격 숫자는 각 메뉴에서 확인합니다.',
          ),
          for (var index = 0; index < _lines.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('execution-line-$index'),
                      controller: _lines[index],
                      enabled: !_busy && !_uncertain && !_conflict,
                      decoration: InputDecoration(
                        hintText: '규정 문장',
                        errorText: _serverFields.isEmpty
                            ? null
                            : '서버에서 이 입력을 확인해 달라고 요청했습니다.',
                      ),
                      onChanged: (_) {
                        setState(() {});
                        widget.onChanged();
                      },
                    ),
                  ),
                  TextButton(
                    key: ValueKey('execution-line-remove-$index'),
                    onPressed: _busy || _uncertain || _conflict
                        ? null
                        : () {
                            setState(() {
                              if (_lines.length == 1) {
                                _lines.first.clear();
                              } else {
                                _lines.removeAt(index).dispose();
                              }
                            });
                            widget.onChanged();
                          },
                    child: const Text('제거'),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('execution-line-add'),
              onPressed: _busy || _uncertain || _conflict || _lines.length >= 32
                  ? null
                  : () {
                      setState(() => _lines.add(TextEditingController()));
                      widget.onChanged();
                    },
              child: const Text('줄 추가'),
            ),
          ),
          if (_gateway == null)
            const Text('한 줄 요건 저장은 로그인한 관리자 계정에서 사용할 수 있습니다.'),
          if (rule == null || widget.metadataDirty)
            const Text('요건 설명을 먼저 저장하세요. 한 줄 요건은 별도로 저장됩니다.'),
          if (rule != null && !ready && !widget.metadataDirty) ...[
            const Text(
              '실행 조건 API에는 적용된 요건이 필요합니다. 규칙 묶음에 속하면 묶음 전체를 함께 적용합니다.',
            ),
            OutlinedButton(
              onPressed: _busy || _gateway == null ? null : _apply,
              child: const Text('요건 검토·적용'),
            ),
          ],
          if (_gateway != null) ...[
            const SizedBox(height: 12),
            ResponsivePanels(
              children: [
                _text(_values, 'yearFrom', '적용 입학연도 시작', year: true),
                _text(_values, 'yearTo', '적용 입학연도 종료', year: true),
              ],
            ),
            _text(_values, 'tracks', '이 조건을 적용할 학생', hint: '예: 단일전공, 복수전공'),
            if (_busy) const LinearProgressIndicator(),
            AnchoredSelectField<String>(
              externalLabel: true,
              value: _programId,
              label: '저장 위치',
              options: [
                const SelectOption('', '새로 저장'),
                for (final p in _programs)
                  SelectOption(
                    p.id,
                    '${p.name} · v${p.version} · ${p.admissionYearFrom}~${p.admissionYearTo}',
                  ),
                if (_programId.isNotEmpty &&
                    !_programs.any((p) => p.id == _programId))
                  SelectOption(_programId, '현재 저장한 실행 초안'),
              ],
              onChanged: (id) {
                if (!_busy) _selectProgram(id);
              },
            ),
            if (_uncertain || _conflict) ...[
              const Text(
                '저장 결과나 버전이 불명확합니다. 서버 목록을 다시 읽고 기존 초안을 선택해 확인하세요. 자동 재전송하지 않습니다.',
              ),
              TextButton(
                onPressed: _busy || !_reloaded
                    ? null
                    : () async {
                        if (!await confirmInputDiscardAllowsLeave(context) || !mounted) {
                          return;
                        }
                        setState(() {
                          _existing = null;
                          _programId = '';
                          _uncertain = false;
                          _conflict = false;
                        });
                      },
                child: const Text('저장 목록 확인 후 새 초안 준비'),
              ),
            ],
            FeatureActions(
              children: [
                FilledButton(
                  onPressed:
                      _busy ||
                          !ready ||
                          widget.metadataDirty ||
                          _uncertain ||
                          _conflict
                      ? null
                      : _save,
                  child: const Text('한 줄 요건 저장'),
                ),
              ],
            ),
          ],
          if (_error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_message != null)
            Semantics(liveRegion: true, child: Text(_message!)),
        ],
      ),
    );
  }
}
