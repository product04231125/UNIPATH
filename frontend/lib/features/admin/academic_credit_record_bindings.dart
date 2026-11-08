import 'package:flutter/material.dart';

import '../../shared/widgets/input_dialog.dart';
import '../records/personal_record_repository.dart';
import 'academic_workspace_api.dart';
import 'academic_write_controller.dart';

Future<void> editCreditRecordBindings(
  BuildContext context,
  AcademicWorkspaceApi api,
  String school,
  Map<String, dynamic> revision,
) => showInputDialog<void>(
  context: context,
  builder: (_) => _BindingsDialog(api: api, school: school, revision: revision),
);

class _BindingsDialog extends StatefulWidget {
  const _BindingsDialog({
    required this.api,
    required this.school,
    required this.revision,
  });
  final AcademicWorkspaceApi api;
  final String school;
  final Map<String, dynamic> revision;
  @override
  State<_BindingsDialog> createState() => _BindingsDialogState();
}

class _BindingsDialogState extends State<_BindingsDialog> {
  late final AcademicWriteController writer;
  late final List<Map<String, dynamic>> headers;
  final inputs = <String, TextEditingController>{};
  int version = 0;
  bool loading = true, loaded = false, dirty = false;
  String? error, message;
  String get path =>
      'admin/academic/requirement-revisions/${widget.revision['id']}/record-bindings';
  @override
  void initState() {
    super.initState();
    writer = AcademicWriteController(widget.api, widget.school)
      ..addListener(changed);
    headers = List<Map<String, dynamic>>.from(
      widget.revision['content']['headers'] as List,
    );
    final parents = headers.map((h) => h['parent_id']).toSet();
    for (final h in headers.where(
      (h) => h['role'] != 'group' && !parents.contains(h['id']),
    )) {
      inputs[h['id'] as String] = TextEditingController();
    }
    load();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void adopt(Map<String, dynamic> value) {
    if (value['institution_id'] != widget.school ||
        value['requirement_revision_id'] != widget.revision['id']) {
      throw const FormatException('Credit binding scope mismatch');
    }
    final bindings = Map<String, dynamic>.from(value['bindings'] as Map);
    for (final entry in inputs.entries) {
      entry.value.text = List<String>.from(bindings[entry.key] as List? ?? [])
          .join(', ');
    }
    version = value['version'] as int;
    loaded = true;
    dirty = false;
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = (await widget.api.transport.request('GET', path))!;
      if (mounted) setState(() => adopt(value));
    } catch (_) {
      if (mounted) setState(() => error = '연결 정보를 읽지 못했습니다. 다시 불러오세요.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> save() async {
    final body = <String, Object?>{
      'client_id': PersonalRecord.newId(),
      'expected_version': version,
      'bindings': {
        for (final entry in inputs.entries)
          if (entry.value.text.trim().isNotEmpty)
            entry.key: entry.value.text
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
      },
    };
    final result = await writer.send('PUT', path, body);
    if (result != null && mounted) {
      setState(() {
        adopt(result);
        message = '성적표 이수구분 연결을 저장했습니다.';
      });
    }
  }

  String label(String id) {
    final labels = <String>[];
    var current = id;
    while (current.isNotEmpty) {
      final header = headers.firstWhere((h) => h['id'] == current);
      labels.insert(0, header['label'] as String);
      current = header['parent_id'] as String? ?? '';
    }
    return labels.join(' / ');
  }

  @override
  void dispose() {
    writer.dispose();
    for (final c in inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InputDialog(
    title: const Text('성적표 이수구분 연결'),
    saving: loading || writer.busy || writer.uncertain,
    hasUnsavedChanges: () => dirty,
    hasContent: () => inputs.values.any((c) => c.text.trim().isNotEmpty),
    changes: Listenable.merge([...inputs.values, writer]),
    editing: true,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('각 열에 산입할 성적표 이수구분을 쉼표로 구분합니다. 목표 학점과 적용 기준 본문은 변경하지 않습니다.'),
        if (loading || writer.busy) const LinearProgressIndicator(),
        if (error != null || writer.error != null) Text(error ?? writer.error!),
        if (message != null) Text(message!),
        TextButton(
          onPressed: loading || writer.busy || writer.uncertain
              ? null
              : () async {
                  if (!dirty || await confirmInputDiscardAllowsLeave(context)) {
                    await load();
                  }
                },
          child: const Text('연결 다시 불러오기'),
        ),
        for (final input in inputs.entries)
          TextField(
            controller: input.value,
            enabled: loaded && !loading && !writer.busy && !writer.uncertain,
            decoration: InputDecoration(
              labelText: label(input.key),
              hintText: '예: 전공필수, 전공선택',
            ),
            onChanged: (_) => setState(() => dirty = true),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: loading || writer.busy || writer.uncertain
            ? null
            : () => InputDialog.cancel<void>(context),
        child: const Text('닫기'),
      ),
      if (writer.uncertain)
        FilledButton(
          onPressed: writer.busy
              ? null
              : () async {
                  final result = await writer.retry();
                  if (result != null && mounted) setState(() => adopt(result));
                },
          child: const Text('같은 요청으로 다시 저장'),
        )
      else
        FilledButton(
          onPressed: loaded && !loading && !writer.busy ? save : null,
          child: const Text('이수구분 연결 저장'),
        ),
    ],
  );
}
