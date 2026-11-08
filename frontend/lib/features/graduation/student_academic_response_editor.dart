import 'dart:convert';

import 'package:flutter/material.dart';

import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/input_dialog.dart';
import '../api/student_academic_api.dart';
import 'student_academic_controller.dart';

Future<void> editStudentAcademicResponse(
  BuildContext context,
  StudentAcademicController controller,
  AcademicStudentDocument document,
  AcademicStudentItem item,
) async {
  final key = GlobalKey<StudentAcademicResponseEditorState>(),
      changes = ValueNotifier<int>(0);
  try {
    await showInputDialog<bool>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: changes,
        builder: (context, _) => InputDialog(
          title: const Text('요건 확인'),
          changes: changes,
          saving: key.currentState?.blocked ?? true,
          hasContent: () => key.currentState?.dirty ?? false,
          content: StudentAcademicResponseEditor(
            key: key,
            controller: controller,
            document: document,
            item: item,
            onChanged: () => changes.value++,
          ),
          actions: [
            TextButton(
              onPressed: (key.currentState?.blocked ?? true)
                  ? null
                  : () => InputDialog.cancel<bool>(context),
              child: const Text('취소'),
            ),
          ],
        ),
      ),
    );
  } finally {
    changes.dispose();
  }
}

class StudentAcademicResponseEditor extends StatefulWidget {
  const StudentAcademicResponseEditor({
    super.key,
    required this.controller,
    required this.document,
    required this.item,
    required this.onChanged,
  });
  final StudentAcademicController controller;
  final AcademicStudentDocument document;
  final AcademicStudentItem item;
  final VoidCallback onChanged;
  @override
  State<StudentAcademicResponseEditor> createState() =>
      StudentAcademicResponseEditorState();
}

class StudentAcademicResponseEditorState
    extends State<StudentAcademicResponseEditor> {
  StudentAcademicController get c => widget.controller;
  bool? _value;
  bool _loading = true;
  bool _recordsReady = false;
  List<AcademicStudentRecord> _records = [];
  final _selected = <String>{};
  String _initial = '';
  String? _error;
  bool get blocked => _loading || c.loading || c.saving || c.uncertain;
  String get _fingerprint => jsonEncode([_value, _selected.toList()..sort()]);
  bool get dirty => _fingerprint != _initial;
  void _changed() {
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onChanged();
    });
  }

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    final previous = widget.document.response(widget.item.id);
    _value = previous?.value;
    _selected.addAll(previous?.records.map((r) => r.identity) ?? []);
    _initial = _fingerprint;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _recordsReady = false;
      _error = null;
    });
    try {
      final records = widget.document.kind == 'certification'
          ? await c.api.records()
          : <AcademicStudentRecord>[];
      if (mounted) {
        setState(() {
          _records = records;
          _recordsReady = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '개인 기록을 읽지 못했습니다. 다시 불러오세요.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _changed();
      }
    }
  }

  Future<void> _save() async {
    final selected = _records
        .where((r) => _selected.contains(r.identity))
        .toList();
    if (selected.length != _selected.length) {
      setState(() => _error = '삭제되거나 조회할 수 없는 기록 연결을 해제하세요.');
      return;
    }
    if (await c.respond(widget.document, widget.item.id, _value, selected) &&
        mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(widget.item.text),
      if (widget.document.response(widget.item.id)?.stale ?? false)
        const Text('기준 또는 연결 기록이 변경됐습니다. 내용을 다시 확인하고 저장하세요.'),
      if (_loading || c.loading || c.saving) const LinearProgressIndicator(),
      if (_error != null || c.error != null)
        Text(
          _error ?? c.error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      AnchoredSelectField<String>(
        label: '내 확인',
        externalLabel: true,
        value: _value == null
            ? 'unknown'
            : _value!
            ? 'yes'
            : 'no',
        options: const [
          SelectOption('unknown', '미확인'),
          SelectOption('yes', 'O · 충족'),
          SelectOption('no', 'X · 미충족'),
        ],
        onChanged: (value) {
          if (!blocked) {
            setState(() => _value = value == 'unknown' ? null : value == 'yes');
          }
        },
      ),
      if (widget.document.kind == 'certification') ...[
        const SizedBox(height: 12),
        const Text('연결할 본인 기록 · 여러 개 선택 가능'),
        if (_records.isEmpty && _error == null)
          const Text('연결할 개인 기록이 없습니다. 기록 없이 O/X만 저장할 수 있습니다.'),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final r in _records)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(r.title),
                    subtitle: Text(
                      const {
                            'course': '수강',
                            'activity': '활동',
                            'credential': '자격',
                            'experience': '경험',
                            'achievement': '성과',
                          }[r.kind] ??
                          r.kind,
                    ),
                    value: _selected.contains(r.identity),
                    onChanged: blocked
                        ? null
                        : (yes) => setState(() {
                            if (_recordsReady) _error = null;
                            if (yes == true) {
                              _selected.add(r.identity);
                            } else {
                              _selected.remove(r.identity);
                            }
                          }),
                  ),
                for (final id in _selected.where(
                  (id) => !_records.any((r) => r.identity == id),
                ))
                  CheckboxListTile(
                    title: const Text('삭제되거나 조회할 수 없는 이전 연결'),
                    value: true,
                    onChanged: blocked
                        ? null
                        : (_) => setState(() {
                            _selected.remove(id);
                            if (_recordsReady) _error = null;
                          }),
                  ),
              ],
            ),
          ),
        ),
        if (c.fieldError('records') case final String error) Text(error),
        const Text('기록을 연결해도 O가 자동 선택되지는 않습니다.'),
        TextButton(
          onPressed: blocked ? null : _load,
          child: const Text('개인 기록 다시 불러오기'),
        ),
      ],
      if (c.uncertain)
        OutlinedButton(
          onPressed: c.saving
              ? null
              : () async {
                  if (await c.retry() && context.mounted) {
                    Navigator.pop(context, true);
                  }
                },
          child: const Text('같은 요청으로 다시 저장'),
        ),
      FilledButton(
        onPressed: blocked || _error != null || !_recordsReady ? null : _save,
        child: const Text('내 확인 저장'),
      ),
    ],
  );
}
