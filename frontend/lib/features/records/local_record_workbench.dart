import 'package:flutter/material.dart';

import '../../shared/app_style.dart';
import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/content_scroll_view.dart';
import '../../shared/widgets/field_label.dart';
import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/responsive_columns.dart';
import 'personal_record_fields.dart';
import 'personal_record_repository.dart';

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
  bool _loading = true, _saving = false;
  String? _error, _message;
  bool get dirty => _controllers.entries.any(
    (e) => e.value.text != (_editing?.value(e.key) ?? ''),
  );
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
        _controllers.putIfAbsent(f.key, TextEditingController.new);
      }
    } catch (_) {
      if (mounted) _error = '자료를 읽지 못했습니다. 다시 읽기를 눌러주세요.';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _reset([PersonalRecord? record]) {
    _form.currentState?.reset();
    _editing = record;
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
      await _repo.save(
        PersonalRecord(
          id: _editing?.id ?? PersonalRecord.newId(),
          version: _editing?.version,
          values: values,
        ),
      );
      if (mounted) {
        _reset();
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
              label: '${f.label}${f.required ? ' *' : ' (선택)'}',
              child: Semantics(
                label: f.label,
                child: TextFormField(
                  key: ValueKey('record-field-${f.key}'),
                  controller: c,
                  enabled: !_saving,
                  maxLines: f.multiline ? 3 : 1,
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
                    label: '${f.label}${f.required ? ' *' : ' (선택)'}',
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
          ResponsiveColumns(
            enabled: true,
            first: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '등록한 항목 ${_repo.records.length}개',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_repo.records.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('등록된 자료가 없습니다. 입력 영역에서 첫 항목을 추가하세요.'),
                  ),
                for (final r in _repo.records)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            r.value('title'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          for (final f in _fields.where(
                            (f) =>
                                f.key != 'title' && r.value(f.key).isNotEmpty,
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
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        '학업 프로필에 적용했습니다.',
                                                      ),
                                                    ),
                                                  );
                                            }
                                          } catch (_) {
                                            if (mounted) {
                                              setState(
                                                () => _error = '학업 프로필에 적용하지 못했습니다. 다시 시도하세요.',
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
                  ),
              ],
            ),
            second: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${widget.title} ${_editing == null ? '추가' : '수정'}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      if (_message != null) Text(_message!),
                      for (final f in _fields) _input(f),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
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
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
