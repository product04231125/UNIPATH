import 'package:flutter/material.dart';

import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/responsive_columns.dart';
import '../../shared/widgets/responsive_panels.dart';
import '../../shared/widgets/field_label.dart';
import '../../shared/widgets/anchored_select_field.dart';
import '../records/personal_record_repository.dart';
import 'admin_models.dart';
import 'admin_fields.dart';
import 'admin_repository.dart';
import 'remote_admin_repository.dart';
import 'admin_rule_execution_panel.dart';

class AdminEditor extends StatefulWidget {
  const AdminEditor({
    super.key,
    required this.repository,
    required this.actorId,
    required this.kind,
    required this.schoolId,
    this.record,
    this.revoke = false,
    this.inline = false,
    this.list,
  });
  final AdminRepository repository;
  final String actorId, schoolId;
  final AdminKind kind;
  final AdminRecord? record;
  final bool revoke;
  final bool inline;
  final Widget? list;
  @override
  State<AdminEditor> createState() => AdminEditorState();
}

class AdminEditorState extends State<AdminEditor> {
  final _form = GlobalKey<FormState>();
  late final List<AdminField> _fields;
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, String> _initial;
  bool _saving = false, _panelBusy = false;
  AdminRecord? _savedRecord;
  var _executionKey = GlobalKey<AdminRuleExecutionPanelState>();
  final _conditionChanges = ValueNotifier<int>(0);
  bool get _isRule => widget.kind == AdminKind.rule && !widget.revoke;
  AdminRecord? get _rule =>
      widget.repository.records
          .where((r) => r.id == _savedRecord?.id)
          .firstOrNull ??
      _savedRecord;
  bool get _metadataLocked => _isRule && _rule?.status == 'applied';
  bool get _metadataDirty =>
      _fields.any((f) => _value(f.key) != (_initial[f.key] ?? ''));
  String? _error, _message;
  bool get saving => _saving || _panelBusy;
  bool get dirty =>
      _metadataDirty || (_executionKey.currentState?.dirty ?? false);
  Future<bool> allowLeave() async {
    if (saving) return false;
    return !dirty || await confirmInputDiscard(context);
  }

  void _reset() {
    for (final f in _fields) {
      _initial[f.key] =
          widget.record?.value(f.key) ??
          (f.key == 'institutionId'
              ? widget.schoolId
              : f.key == 'scopeType'
              ? 'institution'
              : '');
    }
    _savedRecord = widget.record;
    _executionKey = GlobalKey<AdminRuleExecutionPanelState>();
    for (final f in _fields) {
      _controllers[f.key]!.text = _initial[f.key] ?? '';
    }
    _form.currentState?.reset();
    setState(() {
      _saving = false;
      _error = null;
    });
  }

  Future<void> _cancel() async {
    if (widget.inline) {
      if (await allowLeave() && mounted) _reset();
    } else {
      if (mounted) await InputDialog.cancel<void>(context);
    }
  }

  @override
  void initState() {
    super.initState();
    _savedRecord = widget.record;
    _fields = widget.revoke
        ? [const AdminField('reason', '회수 사유', multiline: true)]
        : widget.repository.fields(widget.kind);
    _initial = {
      for (final f in _fields)
        f.key: widget.revoke
            ? ''
            : widget.record?.value(f.key) ??
                  (f.key == 'institutionId'
                      ? widget.schoolId
                      : f.key == 'scopeType'
                      ? 'institution'
                      : ''),
    };
    _controllers = {
      for (final f in _fields)
        f.key: TextEditingController(text: _initial[f.key]),
    };
    if (_isRule) {
      for (final c in _controllers.values) {
        c.addListener(_refreshRule);
      }
    }
  }

  void _refreshRule() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _conditionChanges.dispose();
    super.dispose();
  }

  String _value(String key) => _controllers[key]?.text ?? '';
  Iterable<AdminRecord> _choices(AdminField field) =>
      widget.repository.records.where((r) {
        if (r.kind != field.relation ||
            !widget.repository.canRead(widget.actorId, r)) {
          return false;
        }
        if (r.kind == AdminKind.ruleSet &&
            r.status != 'draft' &&
            r.id != _value(field.key)) {
          return false;
        }
        if (r.kind == AdminKind.account) {
          return r.value('role') != 'super_admin' &&
              r.value('accountStatus') == 'active';
        }
        final school = _value('institutionId').isEmpty
            ? widget.schoolId
            : _value('institutionId');
        if (r.kind != AdminKind.institution &&
            school.isNotEmpty &&
            widget.repository.school(r) != school) {
          return false;
        }
        if (r.kind == AdminKind.curriculum &&
            _value('departmentId').isNotEmpty) {
          return r.value('departmentId') == _value('departmentId');
        }
        return true;
      });
  Future<void> _save() async {
    if (saving || _metadataLocked || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
      _message = null;
    });
    try {
      if (widget.revoke) {
        await widget.repository.revoke(
          widget.actorId,
          widget.record!.id,
          _value('reason'),
        );
      } else {
        final values = {
          ...?(_isRule ? _rule : widget.record)?.values,
          for (final f in _fields) f.key: _value(f.key).trim(),
          if (widget.repository.live && widget.kind != AdminKind.institution)
            'institutionId': _controllers.containsKey('institutionId')
                ? _value('institutionId')
                : widget.schoolId,
        };
        final record =
            (_isRule ? _rule : widget.record)?.copy(values: values) ??
            AdminRecord(
              id: 'mock-${PersonalRecord.newId()}',
              kind: widget.kind,
              values: values,
            );
        if (_isRule && widget.repository is RemoteAdminRepository) {
          _savedRecord = await (widget.repository as RemoteAdminRepository)
              .saveWithResult(widget.actorId, record);
        } else {
          await widget.repository.save(widget.actorId, record);
          if (_isRule) {
            _savedRecord = widget.repository.records
                .where((r) => r.id == record.id)
                .firstOrNull;
          }
        }
      }
      if (mounted) {
        if (_isRule) {
          for (final f in _fields) {
            _initial[f.key] = _value(f.key);
          }
          setState(() {
            _saving = false;
            _message = '요건 설명을 저장했습니다. 아래에서 계산 조건을 이어서 저장하세요.';
          });
        } else if (widget.inline) {
          _reset();
          setState(() => _message = '등록했습니다. 다음 내용을 입력할 수 있습니다.');
        } else {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is StateError
              ? e.message
              : '저장에 실패했습니다. 입력을 유지했으니 다시 시도하세요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.inline && widget.list != null) return _mixedLayout();
    return _shell(
      changes: Listenable.merge([..._controllers.values, _conditionChanges]),
      editing: widget.record != null,
      saving: saving,
      hasContent: () => dirty,
      hasUnsavedChanges: () => dirty,
      title: Text(
        widget.revoke
            ? '관리 범위 회수'
            : '${widget.kind.label} ${widget.record == null ? '등록' : '수정'}',
      ),
      content: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            for (final group in adminFieldGroups(_fields).entries) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12, top: 4),
                child: Semantics(
                  header: true,
                  child: Text(
                    group.key,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              for (final field in group.value) _field(field),
            ],
            if (_isRule) _executionPanel(),
            if (_message != null)
              Semantics(liveRegion: true, child: Text(_message!)),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: saving ? null : _cancel, child: const Text('취소')),
        FilledButton(
          onPressed: saving || _metadataLocked ? null : _save,
          child: Text(
            _saving
                ? '저장 중…'
                : widget.revoke
                ? '범위 회수'
                : _isRule
                ? '요건 설명 저장'
                : widget.inline
                ? '등록'
                : '저장',
          ),
        ),
      ],
    );
  }

  Widget _executionPanel() => AdminRuleExecutionPanel(
    key: _executionKey,
    repository: widget.repository,
    actorId: widget.actorId,
    schoolId: _value('institutionId').isEmpty
        ? widget.schoolId
        : _value('institutionId'),
    ruleType: _value('ruleType'),
    description: _value('definition'),
    rule: _rule,
    metadataDirty: _metadataDirty,
    onChanged: () {
      _conditionChanges.value++;
    },
    onBusy: (busy) {
      if (mounted) setState(() => _panelBusy = busy);
    },
  );

  Widget _field(AdminField field) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: field.relation == null && field.options.isEmpty
        ? FieldLabel(
            label: '${field.label}${field.required ? ' *' : ' (선택)'}',
            child: Semantics(
              label: field.label,
              child: TextFormField(
                key: ValueKey('admin-field-${field.key}'),
                controller: _controllers[field.key],
                enabled: !saving && !_metadataLocked,
                maxLines: field.multiline ? 3 : 1,
                decoration: const InputDecoration(),
                validator: (v) =>
                    field.required && (v == null || v.trim().isEmpty)
                    ? '${field.label}을 입력하세요.'
                    : null,
              ),
            ),
          )
        : FormField<String>(
            initialValue: _value(field.key),
            validator: (v) => field.required && _value(field.key).isEmpty
                ? '${field.label}을 선택하세요.'
                : null,
            builder: (state) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IgnorePointer(
                  ignoring: saving || _metadataLocked,
                  child: AnchoredSelectField<String>(
                    externalLabel: true,
                    key: ValueKey('admin-field-${field.key}'),
                    value: _value(field.key),
                    label: '${field.label}${field.required ? ' *' : ' (선택)'}',
                    options: [
                      const SelectOption('', '미선택'),
                      for (final entry in field.options.entries)
                        SelectOption(entry.key, entry.value),
                      for (final r in _choices(field))
                        SelectOption(
                          r.id,
                          '${r.name}${r.kind.versioned ? ' · v${r.revision}' : ''}',
                        ),
                      if (_value(field.key).isNotEmpty &&
                          !field.options.containsKey(_value(field.key)) &&
                          !_choices(field)
                              .any((r) => r.id == _value(field.key)))
                        SelectOption(_value(field.key), '연결 대상 없음 · 다시 선택하세요'),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _controllers[field.key]!.text = v;
                        if (field.key == 'ruleSetId' && v.isNotEmpty) {
                          final group = widget.repository.records.firstWhere(
                            (r) => r.id == v,
                          );
                          for (final key in [
                            'institutionId',
                            'departmentId',
                            'curriculumId',
                            if (widget.repository.live) ...[
                              'effectiveFrom',
                              'effectiveTo',
                            ],
                          ]) {
                            _controllers[key]!.text = group.value(key);
                          }
                        }
                      });
                      state.didChange(v);
                    },
                  ),
                ),
                if (state.hasError)
                  Text(
                    state.errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
  );

  Widget _panel(String title, Widget content, {Key? key}) => Column(
    key: key,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        header: true,
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      const SizedBox(height: 16),
      content,
    ],
  );

  Widget _compactDetails(List<AdminField> fields) {
    final rows = <Widget>[];
    final shortFields = <Widget>[];
    void flush() {
      if (shortFields.isEmpty) return;
      rows.add(ResponsivePanels(children: List.of(shortFields)));
      shortFields.clear();
    }

    for (final field in fields) {
      if (field.multiline) {
        flush();
        rows.add(_field(field));
      } else {
        shortFields.add(_field(field));
      }
    }
    flush();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  Widget _mixedLayout() {
    final basic = _fields
        .where((f) => f.key == 'name' || f.key == 'institutionId')
        .toList();
    final remaining = _fields.where((f) => !basic.contains(f)).toList();
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ResponsiveColumns(
            enabled: true,
            // Keep search/filter fields outside the registration FormState.
            first: Form(child: widget.list!),
            second: _panel(
              '등록 기본 정보',
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final field in basic) _field(field)],
              ),
              key: ValueKey('admin-basic-${widget.kind.name}'),
            ),
          ),
          const Divider(height: 40),
          _panel(
            '적용 범위·상세',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _compactDetails([
                  for (final group in adminFieldGroups(remaining).values)
                    ...group,
                ]),
                if (_isRule) _executionPanel(),
                if (_message != null)
                  Semantics(liveRegion: true, child: Text(_message!)),
                if (_error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const Divider(height: 24),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: saving ? null : _cancel,
                      child: const Text('취소'),
                    ),
                    FilledButton(
                      onPressed: saving || _metadataLocked ? null : _save,
                      child: Text(
                        _saving
                            ? '저장 중…'
                            : _isRule
                            ? '요건 설명 저장'
                            : '등록',
                      ),
                    ),
                  ],
                ),
              ],
            ),
            key: ValueKey('admin-details-${widget.kind.name}'),
          ),
        ],
      ),
    );
  }

  Widget _shell({
    required Listenable changes,
    required bool editing,
    required bool saving,
    required bool Function() hasContent,
    required bool Function() hasUnsavedChanges,
    required Widget title,
    required Widget content,
    required List<Widget> actions,
  }) {
    if (!widget.inline) {
      return InputDialog(
        changes: changes,
        editing: editing,
        saving: saving,
        hasContent: hasContent,
        hasUnsavedChanges: hasUnsavedChanges,
        title: title,
        content: content,
        actions: actions,
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: DefaultTextStyle(
                style: Theme.of(context).textTheme.titleMedium!,
                child: title,
              ),
            ),
            content,
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }
}
