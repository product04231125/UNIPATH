import 'package:flutter/material.dart';

import '../../shared/app_style.dart';
import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/content_scroll_view.dart';
import '../../shared/widgets/field_label.dart';
import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/responsive_columns.dart';
import '../../shared/widgets/responsive_panels.dart';
import 'personal_record_fields.dart';
import 'personal_record_repository.dart';
import '../graduation/personal_requirement_panel.dart';

/// Student-owned local records. No administrator repository or server role.
class LocalRecordWorkbench extends StatefulWidget {
  const LocalRecordWorkbench({
    super.key,
    required this.kind,
    required this.title,
    required this.fieldsLoader,
    this.validateValues,
    this.onUse,
    this.repository,
  });
  final PersonalRecordKind kind;
  final PersonalRecordRepository? repository;
  final String title;
  final Future<List<PersonalRecordField>> Function() fieldsLoader;
  final Future<String?> Function(Map<String, String>)? validateValues;
  final Future<void> Function(PersonalRecord)? onUse;
  @override
  State<LocalRecordWorkbench> createState() => LocalRecordWorkbenchState();
}

class LocalRecordWorkbenchState extends State<LocalRecordWorkbench> {
  late final _repo = widget.repository ?? PersonalRecordRepository(widget.kind);
  final _form = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  List<PersonalRecordField> _fields = [];
  PersonalRecord? _editing;
  var _rulePanel = GlobalKey<PersonalRequirementPanelState>();
  bool get _isRule => widget.kind == PersonalRecordKind.personalGraduationRule;
  bool _loading = true, _saving = false;
  String? _error, _message;
  bool get _metadataDirty => _controllers.entries.any(
    (e) => e.value.text != (_editing?.value(e.key) ?? ''),
  );
  bool get dirty => _metadataDirty || (_rulePanel.currentState?.dirty ?? false);
  Future<bool> allowLeave() async =>
      !_saving && (!dirty || await confirmInputDiscard(context));
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _repo.load();
      final fields = await widget.fieldsLoader();
      if (!mounted) return;
      _fields = fields;
      for (final f in fields) {
        _controllers.putIfAbsent(f.key, () {
          final c = TextEditingController();
          if (_isRule) {
            c.addListener(() {
              if (mounted) setState(() {});
            });
          }
          return c;
        });
      }
    } catch (_) {
      if (mounted) _error = '자료를 읽지 못했습니다. 다시 읽기를 눌러주세요.';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _reset([PersonalRecord? record]) {
    _form.currentState?.reset();
    _editing = record;
    _rulePanel = GlobalKey<PersonalRequirementPanelState>();
    for (final e in _controllers.entries) {
      e.value.text = record?.value(e.key) ?? '';
    }
    setState(() {
      _error = null;
      _message = null;
    });
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    if (_isRule && !(_rulePanel.currentState?.validateForMetadata() ?? false)) {
      return;
    }
    final values = {
      ...?_editing?.values,
      for (final e in _controllers.entries) e.key: e.value.text.trim(),
    };
    final error = personalRecordCrossError(values);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final linkError = await widget.validateValues?.call(values);
      if (linkError != null) throw StateError(linkError);
      final id = _editing?.id ?? PersonalRecord.newId();
      await _repo.save(
        PersonalRecord(id: id, version: _editing?.version, values: values),
      );
      if (mounted) {
        if (_isRule) {
          _editing = _repo.records.where((r) => r.id == id).first;
        } else {
          _reset();
        }
        setState(
          () => _message =
              '개인 자료를 ${_repo.isServerBacked ? '계정 서버' : '기기'}에 저장했습니다.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is StateError
              ? e.message
              : '저장하지 못했습니다. 입력을 유지했으니 다시 시도하세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(PersonalRecord record) async {
    if (_saving || !await allowLeave() || !mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${record.value('title')} 삭제'),
        content: Text(
          _repo.isServerBacked
              ? '계정 서버의 이 자료를 삭제합니다. 다른 자료가 참조 중이면 연결을 먼저 해제해야 합니다.'
              : '이 개인 자료만 삭제합니다. 연결된 과목·규칙·다른 기록은 유지되며 연결 대상을 다시 확인해야 합니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: destructiveButtonStyle(context),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await _repo.delete(record.id, expectedVersion: record.version);
      if (mounted) _reset();
    } catch (_) {
      if (mounted) setState(() => _error = '삭제하지 못했습니다. 자료를 유지했습니다. 다시 시도하세요.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _input(PersonalRecordField f) {
    final c = _controllers[f.key]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: f.options.isEmpty
          ? FieldLabel(
              label:
                  '${_isRule && f.key == 'condition' ? '요건 설명' : f.label}${f.required ? ' *' : ' (선택)'}',
              child: Semantics(
                label: f.label,
                child: TextFormField(
                  key: ValueKey('record-field-${f.key}'),
                  controller: c,
                  enabled: !_saving,
                  maxLines: _isRule && f.key == 'condition'
                      ? 1
                      : f.multiline
                      ? 3
                      : 1,
                  validator: f.validate,
                  keyboardType: f.type == PersonalFieldType.number
                      ? TextInputType.number
                      : TextInputType.text,
                ),
              ),
            )
          : FormField<String>(
              key: ValueKey('local-select-validation-${f.key}-${_editing?.id}'),
              validator: (_) => f.validate(c.text),
              builder: (state) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnchoredSelectField<String>(
                    externalLabel: true,
                    key: ValueKey('record-select-${f.key}'),
                    value: c.text,
                    label:
                        '${_isRule && f.key == 'condition' ? '요건 설명' : f.label}${f.required ? ' *' : ' (선택)'}',
                    options: [
                      const SelectOption('', '미선택'),
                      for (final value in f.options.where((v) => v.isNotEmpty))
                        SelectOption(value, f.optionLabels[value] ?? value),
                      if (c.text.isNotEmpty && !f.options.contains(c.text))
                        SelectOption(c.text, '연결 대상 없음 · 다시 선택하세요'),
                    ],
                    onChanged: (value) {
                      if (_saving) return;
                      setState(() {
                        c.text = value;
                        if (f.mirrorKey != null && value.isNotEmpty) {
                          _controllers[f.mirrorKey]?.text =
                              f.optionLabels[value] ?? '';
                        }
                      });
                      state.didChange(value);
                    },
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
  }

  Widget _list() => KeyedSubtree(
    key: ValueKey('personal-list-${widget.kind.name}'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Semantics(
              header: true,
              child: Text('목록', style: Theme.of(context).textTheme.titleMedium),
            ),
            Text('등록한 항목 ${_repo.records.length}개'),
          ],
        ),
        const Divider(height: 32),
        if (_repo.records.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 36),
            child: Column(
              children: [
                Icon(Icons.list_alt_outlined, size: 32),
                SizedBox(height: 12),
                Text('등록된 자료가 없습니다.'),
                SizedBox(height: 8),
                Text(
                  '입력 영역에서 첫 항목을 추가하면 이 목록에 표시됩니다.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        for (final r in _repo.records) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  r.value('title'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final f in _fields.where(
                  (f) => f.key != 'title' && r.value(f.key).isNotEmpty,
                ))
                  Text(
                    '${f.label}: ${f.options.isEmpty ? r.value(f.key) : f.optionLabels[r.value(f.key)] ?? '연결 대상 없음 · 다시 선택하세요'}',
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () async {
                              if (await allowLeave() && mounted) {
                                _reset(r);
                              }
                            },
                      child: const Text('수정'),
                    ),
                    if (widget.onUse != null)
                      OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () async {
                                setState(() => _saving = true);
                                try {
                                  await widget.onUse!(r);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('학업 프로필에 적용했습니다.'),
                                      ),
                                    );
                                  }
                                } catch (_) {
                                  if (mounted) {
                                    setState(
                                      () => _error =
                                          '학업 프로필에 적용하지 못했습니다. 다시 시도하세요.',
                                    );
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _saving = false);
                                  }
                                }
                              },
                        child: const Text('학업 프로필로 사용'),
                      ),
                    FilledButton(
                      style: destructiveButtonStyle(context),
                      onPressed: _saving ? null : () => _delete(r),
                      child: const Text('삭제'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
        ],
      ],
    ),
  );

  Widget _section(String title, Widget child, {required Key key}) => Column(
    key: key,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        header: true,
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      const SizedBox(height: 16),
      child,
    ],
  );

  Widget _details(List<PersonalRecordField> fields) {
    fields = fields
        .where(
          (f) =>
              !_isRule ||
              ![
                'ruleType',
                'requiredValue',
                'currentValue',
                'unit',
              ].contains(f.key),
        )
        .toList();
    final short = fields
        .where((f) => !f.multiline && f.type != PersonalFieldType.url)
        .toList();
    final long = fields.where(
      (f) => f.multiline || f.type == PersonalFieldType.url,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsivePanels(children: [for (final f in short) _input(f)]),
        for (final f in long) _input(f),
      ],
    );
  }

  Widget _workbench() {
    final relation = switch (widget.kind) {
      PersonalRecordKind.personalDepartment => 'schoolId',
      PersonalRecordKind.personalCurriculum =>
        _fields.any((f) => f.key == 'schoolId') ? 'schoolId' : 'school',
      PersonalRecordKind.personalCurriculumCourse ||
      PersonalRecordKind.personalGraduationRule => 'curriculumId',
      _ => '',
    };
    final basic = _fields
        .where((f) => f.key == 'title' || f.key == relation)
        .toList();
    final details = _fields.where((f) => !basic.contains(f)).toList();
    return Card(
      key: ValueKey('personal-frame-${widget.kind.name}'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ResponsiveColumns(
                enabled: true,
                first: _list(),
                second: _section(
                  '${widget.title} ${_editing == null ? '추가' : '수정'}',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [for (final f in basic) _input(f)],
                  ),
                  key: ValueKey('personal-basic-${widget.kind.name}'),
                ),
              ),
              const Divider(height: 40),
              _section(
                '적용 범위·상세',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _details(details),
                    if (_isRule)
                      PersonalRequirementPanel(
                        key: _rulePanel,
                        curriculumId: _controllers['curriculumId']?.text ?? '',
                        rule: _editing,
                        metadataDirty: _metadataDirty,
                        onBusy: (busy) {
                          if (mounted) setState(() => _saving = busy);
                        },
                        onChanged: (draft) {
                          if (draft.kind != 'none') {
                            _controllers['ruleType']!.text = draft.kind;
                          }
                          _controllers['requiredValue']!.text =
                              draft.values['minimum'] ?? '';
                          _controllers['unit']!.text =
                              draft.kind == 'minimum_credits'
                              ? '학점'
                              : draft.kind == 'minimum_volunteer_hours'
                              ? '시간'
                              : '';
                        },
                      ),
                    if (_message != null)
                      Semantics(liveRegion: true, child: Text(_message!)),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
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
                          onPressed: _saving
                              ? null
                              : () async {
                                  if (await allowLeave() && mounted) _reset();
                                },
                          child: const Text('취소'),
                        ),
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          child: Text(_saving ? '저장 중…' : '내 기록에 저장'),
                        ),
                      ],
                    ),
                  ],
                ),
                key: ValueKey('personal-details-${widget.kind.name}'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext buildContext) => ContentScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: widget.title,
          description: '내가 직접 관리하는 개인 학업 정보 · 학교 공식 데이터나 졸업 판정이 아닙니다.',
        ),
        if (_loading)
          const LinearProgressIndicator()
        else if (_fields.isEmpty) ...[
          Text(_error ?? '입력 항목을 읽지 못했습니다.'),
          TextButton(onPressed: _load, child: const Text('다시 읽기')),
        ] else
          _workbench(),
      ],
    ),
  );
}
