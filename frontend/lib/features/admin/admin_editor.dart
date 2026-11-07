import 'package:flutter/material.dart';

import '../../shared/widgets/external_link_button.dart';
import '../../shared/widgets/feature_line.dart';
import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/responsive_columns.dart';
import '../../shared/widgets/responsive_panels.dart';
import '../../shared/widgets/field_label.dart';
import '../../shared/widgets/field_requirement.dart';
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
    this.onRevokeRequested,
    this.onClosed,
  });
  final AdminRepository repository;
  final String actorId, schoolId;
  final AdminKind kind;
  final AdminRecord? record;
  final bool revoke;
  final bool inline;
  final Widget? list;
  final VoidCallback? onRevokeRequested;
  final VoidCallback? onClosed;
  @override
  State<AdminEditor> createState() => AdminEditorState();
}

class AdminEditorState extends State<AdminEditor> {
  final _form = GlobalKey<FormState>();
  late final List<AdminField> _fields;
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, String> _initial;
  bool _saving = false, _panelBusy = false;
  AdminRecord? _editingRecord;
  AdminRecord? _savedRecord;
  var _executionKey = GlobalKey<AdminRuleExecutionPanelState>();
  final _conditionChanges = ValueNotifier<int>(0);
  bool get _isRule => widget.kind == AdminKind.rule && !widget.revoke;
  bool get _isSchoolKind =>
      widget.kind == AdminKind.institution ||
      widget.kind == AdminKind.department;
  AdminRecord? get _activeRecord =>
      _isSchoolKind ? _editingRecord : _editingRecord ?? widget.record;
  bool get _isCurriculumKind =>
      widget.kind == AdminKind.curriculum ||
      widget.kind == AdminKind.course ||
      widget.kind == AdminKind.curriculumCourse;
  AdminRecord? get _currentRecord =>
      _isCurriculumKind ? _editingRecord : _activeRecord;
  AdminRecord? get activeRecord => _currentRecord;
  bool get _isEditing => _currentRecord != null;
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

  String _defaultValue(AdminField field) {
    if (field.key == 'institutionId') return widget.schoolId;
    if (field.key == 'scopeType') return 'institution';
    return '';
  }

  void _fill(AdminRecord? record) {
    for (final f in _fields) {
      _initial[f.key] = record?.value(f.key) ?? _defaultValue(f);
      _controllers[f.key]!.text = _initial[f.key] ?? '';
    }
    // Form.reset() restores controller fields to the previous build's
    // initialValue and can leave validation using stale text. Clear the
    // error display after the controllers already hold the new values.
    if (_isSchoolKind || _isCurriculumKind) {
      _form.currentState?.clearError();
    }
    _savedRecord = record;
    _executionKey = GlobalKey<AdminRuleExecutionPanelState>();
  }

  void showRecord(AdminRecord record) {
    _editingRecord = record;
    _savedRecord = record;
    _fill(record);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = null;
      _message = null;
    });
  }

  Future<void> loadRecord(AdminRecord record) async {
    if (!mounted) return;
    if (_currentRecord?.id == record.id) {
      _editingRecord = record;
      _savedRecord = record;
      if (!dirty) _fill(record);
      setState(() {});
      return;
    }
    if (!await allowLeave() || !mounted) return;
    _editingRecord = record;
    _fill(record);
    setState(() {
      _saving = false;
      _error = null;
      _message = null;
    });
  }

  void abandonToCreate() {
    _editingRecord = null;
    _fill(null);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = null;
      _message = null;
    });
  }

  Future<void> clearToCreate() async {
    if (!await allowLeave() || !mounted) return;
    abandonToCreate();
  }

  Future<void> _cancel() async {
    if (widget.onClosed != null) {
      if (!await allowLeave() || !mounted) return;
      widget.onClosed!();
      return;
    }
    if (widget.inline) {
      await clearToCreate();
    } else {
      if (mounted) await InputDialog.cancel<String>(context);
    }
  }

  @override
  void initState() {
    super.initState();
    if (_isSchoolKind) _editingRecord = widget.record;
    if (_isCurriculumKind) _editingRecord = widget.record;
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

  String _choiceLabel(AdminRecord record) {
    final label =
        '${record.name}${record.kind.versioned ? ' · v${record.revision}' : ''}';
    if (widget.schoolId.isNotEmpty || record.kind == AdminKind.institution) {
      return label;
    }
    final schoolId = widget.repository.school(record);
    final schoolName = widget.repository.records
        .where((item) => item.id == schoolId)
        .map((item) => item.name)
        .firstOrNull;
    if (schoolName == null || schoolName.isEmpty || schoolName == record.name) {
      return label;
    }
    return '$label · $schoolName';
  }

  /// A selected title-bar school wins. Otherwise the form's school field, or
  /// the school of the department or curriculum the user picked.
  String _resolvedInstitution() {
    if (_controllers.containsKey('institutionId')) {
      return _value('institutionId');
    }
    if (widget.schoolId.isNotEmpty) return widget.schoolId;
    final departmentId = _value('departmentId');
    if (departmentId.isNotEmpty) {
      final department = widget.repository.records
          .where((record) => record.id == departmentId)
          .firstOrNull;
      if (department != null) return widget.repository.school(department);
    }
    final curriculumId = _value('curriculumId');
    if (curriculumId.isNotEmpty) {
      final curriculum = widget.repository.records
          .where((record) => record.id == curriculumId)
          .firstOrNull;
      if (curriculum != null) return widget.repository.school(curriculum);
    }
    return '';
  }

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
          ...?(_isRule ? _rule : _currentRecord)?.values,
          for (final f in _fields) f.key: _value(f.key).trim(),
          if (widget.repository.live && widget.kind != AdminKind.institution)
            'institutionId': _resolvedInstitution(),
        };
        final record =
            (_isRule ? _rule : _currentRecord)?.copy(values: values) ??
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
        } else if (widget.onClosed != null) {
          for (final field in _fields) {
            _initial[field.key] = _value(field.key);
          }
          setState(() {
            _saving = false;
            _message = '저장했습니다.';
          });
        } else if (widget.inline) {
          final edited = _isEditing;
          _editingRecord = null;
          _fill(null);
          setState(() {
            _saving = false;
            _message = edited
                ? '저장했습니다. 다음 내용을 입력할 수 있습니다.'
                : '등록했습니다. 다음 내용을 입력할 수 있습니다.';
          });
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
      editing: _isEditing,
      saving: saving,
      hasContent: () => dirty,
      hasUnsavedChanges: () => dirty,
      title: Text(
        widget.revoke
            ? '관리 범위 회수'
            : '${widget.kind.label} ${_isEditing ? '수정' : '등록'}',
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
        ..._lifecycleButtons(),
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
                : widget.onClosed != null || !widget.inline
                ? '저장'
                : '등록',
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

  bool _isSelect(AdminField field) =>
      field.relation != null || field.options.isNotEmpty || field.key == 'year';

  List<SelectOption<String>> _selectOptions(AdminField field) {
    if (field.key == 'year') {
      return [
        const SelectOption('', '미선택'),
        for (final year in adminYearChoices(
          records: widget.repository.records.where(
            (r) =>
                r.kind == AdminKind.curriculum &&
                widget.repository.canRead(widget.actorId, r),
          ),
          selected: _value(field.key),
        ))
          SelectOption('$year', '$year년'),
      ];
    }
    return [
      const SelectOption('', '미선택'),
      for (final entry in field.options.entries)
        SelectOption(entry.key, entry.value),
      for (final r in _choices(field)) SelectOption(r.id, _choiceLabel(r)),
      if (_value(field.key).isNotEmpty &&
          !field.options.containsKey(_value(field.key)) &&
          !_choices(field).any((r) => r.id == _value(field.key)))
        SelectOption(_value(field.key), '연결 대상 없음 · 다시 선택하세요'),
    ];
  }

  Widget _field(AdminField field) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: !_isSelect(field)
        ? FieldLabel(
            label: fieldRequirementLabel(field.label, required: field.required),
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
                    label: fieldRequirementLabel(
                      field.label,
                      required: field.required,
                    ),
                    searchable: true,
                    searchLabel: field.key == 'year' ? '연도 검색' : '검색',
                    options: _selectOptions(field),
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
      FeatureLine.section(text: title, padTop: false, padBottom: false),
      const SizedBox(height: 8),
      content,
    ],
  );

  /// Full rectangle around the list. Wide layout keeps the list on the left.
  Widget _listRail({required Widget child}) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    const radius = BorderRadius.all(Radius.circular(20));
    return DecoratedBox(
      key: ValueKey('admin-list-panel-${widget.kind.name}'),
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: color),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: child,
        ),
      ),
    );
  }

  /// Scope / leftover identity fields sit beside the list under basic info.
  /// Source, period, rule, and settings fields stay in the full-width block.
  bool _besideDetailsField(AdminField field) => switch (field.key) {
    'departmentId' ||
    'curriculumId' ||
    'userId' ||
    'scopeType' => true,
    'sourceUrl' ||
    'officialUrl' ||
    'documentType' ||
    'ruleId' ||
    'ruleSetId' ||
    'effectiveFrom' ||
    'effectiveTo' ||
    'ruleType' ||
    'definition' ||
    'category' ||
    'required' ||
    'courseId' ||
    'reason' ||
    'accountStatus' => false,
    _ => true,
  };

  Widget _compactDetails(
    List<AdminField> fields, {
    bool pairInNarrowColumn = false,
  }) {
    final rows = <Widget>[];
    final shortFields = <Widget>[];
    void flush() {
      if (shortFields.isEmpty) return;
      if (pairInNarrowColumn) {
        for (var i = 0; i < shortFields.length; i += 2) {
          if (i > 0) rows.add(const SizedBox(height: 24));
          if (i + 1 < shortFields.length) {
            rows.add(
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: shortFields[i]),
                  const SizedBox(width: 24),
                  Expanded(child: shortFields[i + 1]),
                ],
              ),
            );
          } else {
            rows.add(shortFields[i]);
          }
        }
      } else {
        rows.add(ResponsivePanels(children: List.of(shortFields)));
      }
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
    final beside = remaining.where(_besideDetailsField).toList();
    final below = remaining.where((f) => !_besideDetailsField(f)).toList();
    final gap = FeatureLine.slotGap(context);
    final rightColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panel(
          _isEditing ? '수정 기본 정보' : '등록 기본 정보',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final field in basic) _field(field)],
          ),
          key: ValueKey('admin-basic-${widget.kind.name}'),
        ),
        if (beside.isNotEmpty) ...[
          SizedBox(height: gap),
          _panel(
            '적용 범위',
            _compactDetails(beside, pairInNarrowColumn: true),
            key: ValueKey('admin-details-beside-${widget.kind.name}'),
          ),
        ],
      ],
    );
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ResponsiveColumns(
            enabled: true,
            // Keep search/filter fields outside the registration FormState.
            first: _listRail(child: Form(child: widget.list!)),
            second: rightColumn,
          ),
          SizedBox(height: gap),
          _panel(
            '적용 범위·상세',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_lifecycleButtons().isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _lifecycleButtons(),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_isEditing && _activeRecord!.value('sourceUrl').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ExternalLinkButton(
                      url: _activeRecord!.value('sourceUrl'),
                      label: '원문 열기',
                    ),
                  ),
                if (below.isNotEmpty)
                  _compactDetails([
                    for (final group in adminFieldGroups(below).values) ...group,
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
                            : _isEditing
                            ? '저장'
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

  AdminRecord? get _targetRecord {
    final id = _activeRecord?.id;
    if (id == null) return _activeRecord;
    return widget.repository.records.where((r) => r.id == id).firstOrNull ??
        _activeRecord;
  }

  Future<void> _confirmLifecycle(
    String action,
    Future<void> Function() run,
  ) async {
    if (saving) return;
    final record = _targetRecord;
    if (record == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${record.name} · $action'),
        content: Text(
          action == '초안 적용'
              ? 'v${record.revision}의 내용·관리 범위·근거를 검토했습니까?'
              : '대상과 연결 영향을 확인하세요. 참조가 남은 삭제는 차단하고 적용 이력은 보존합니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await run();
      if (!mounted) return;
      if (widget.inline) {
        final updated = _targetRecord;
        if (updated != null) {
          _editingRecord = updated;
          _savedRecord = updated;
        }
        setState(() => _saving = false);
      } else {
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is StateError
              ? error.message
              : '처리하지 못했습니다. 다시 시도하세요.';
        });
      }
    }
  }

  List<Widget> _lifecycleButtons() {
    final record = _targetRecord;
    if (record == null || widget.revoke) return const [];
    return [
      if (record.kind.versioned &&
          record.value('ruleSetId').isEmpty &&
          record.status == 'draft')
        FilledButton.tonal(
          onPressed: saving
              ? null
              : () => _confirmLifecycle(
                  '초안 적용',
                  () => widget.repository.apply(widget.actorId, record.id),
                ),
          child: const Text('검토·적용'),
        ),
      if (record.kind.versioned &&
          record.value('ruleSetId').isEmpty &&
          record.status == 'applied')
        FilledButton.tonal(
          onPressed: saving
              ? null
              : () => _confirmLifecycle(
                  '새 버전 초안',
                  () => widget.repository.newVersion(widget.actorId, record.id),
                ),
          child: const Text('새 버전 초안'),
        ),
      if (record.kind == AdminKind.scope && record.status == 'active')
        OutlinedButton(
          onPressed: saving
              ? null
              : () {
                  if (widget.inline) {
                    widget.onRevokeRequested?.call();
                  } else {
                    InputDialog.cancel<String>(context, 'revoke');
                  }
                },
          child: const Text('범위 회수'),
        ),
    ];
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
