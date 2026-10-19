import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/widgets/input_dialog.dart';
import '../auth/auth_api.dart';
import 'personal_workspace_importer.dart';

class PersonalWorkspaceImportSection extends StatefulWidget {
  const PersonalWorkspaceImportSection({super.key, required this.importer});
  final PersonalWorkspaceImporter importer;
  @override
  State<PersonalWorkspaceImportSection> createState() =>
      _PersonalWorkspaceImportSectionState();
}

class _PersonalWorkspaceImportSectionState
    extends State<PersonalWorkspaceImportSection> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => unawaited(widget.importer.load().catchError((Object _) {}));
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.importer,
    builder: (context, _) {
      final data = widget.importer;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '수강·활동·포트폴리오 자료',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text('새 개인 기록은 본인 계정 서버에 저장합니다. 기존 기기 자료는 동의 전까지 전송하지 않습니다.'),
          if (data.loading)
            const LinearProgressIndicator()
          else if (data.failed)
            const Text('기기 원본을 읽지 못했습니다. 원본은 유지되며 서버 기록은 계속 사용할 수 있습니다.')
          else if (data.issue != null)
            Text(data.issue!)
          else if (data.completed)
            const Text('기기 개인 기록 이전을 확인했습니다. 기기 원본은 보관합니다.')
          else if (data.count == 0)
            const Text('현재 계정의 기기 개인 기록이 없습니다.')
          else
            Text('기기 개인 기록 ${data.count}개가 별도로 있습니다. 목록과 연결을 확인하고 이전할 수 있습니다.'),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: data.loading ? null : _load,
                child: const Text('기기 자료 다시 확인'),
              ),
              if (data.canImport)
                OutlinedButton(
                  onPressed: () => showInputDialog<void>(
                    context: context,
                    builder: (_) => _ImportDialog(
                      importer: data,
                      snapshotId: data.snapshotId!,
                    ),
                  ),
                  child: const Text('기기 개인 기록 이전'),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      );
    },
  );
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.importer, required this.snapshotId});
  final PersonalWorkspaceImporter importer;
  final String snapshotId;
  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  bool _confirmed = false, _saving = false;
  String? _error;
  final _changes = ValueNotifier(0);
  late final List<String> _preview = widget.importer.preview;
  @override
  void dispose() {
    _changes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InputDialog(
    changes: _changes,
    saving: _saving,
    hasContent: () => _confirmed,
    hasUnsavedChanges: () => _confirmed,
    title: const Text('기기 개인 기록 이전'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '현재 계정의 수강·활동·경험·자격·성과·개인 교육과정/과목/규칙·구성·지원 문서를 이전합니다. '
          '제목·기간·수치·메모·작성 본문과 기록 사이의 연결을 함께 전송합니다. 익명·다른 계정 자료와 학업 프로필·일정은 이 요청에 포함하지 않습니다.',
        ),
        const SizedBox(height: 12),
        Text('전송할 개인 기록 ${_preview.length}개'),
        for (final item in _preview) Text(item),
        const SizedBox(height: 12),
        const Text(
          '기존 서버 자료를 덮어쓰거나 기기 원본을 지우지 않습니다. '
          '이전은 학교의 승인·공식 판정·온라인 게시·지원처 제출을 뜻하지 않습니다. '
          '실패하면 같은 요청으로 결과를 다시 확인합니다.',
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _confirmed,
          onChanged: _saving
              ? null
              : (value) => setState(() {
                  _confirmed = value == true;
                  _changes.value++;
                }),
          title: const Text('자료 목록과 전송 범위를 확인했으며 서버 이전에 동의합니다.'),
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => InputDialog.cancel<void>(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: _saving || !_confirmed ? null : _import,
        child: Text(_saving ? '이전 확인 중…' : '동의하고 이전'),
      ),
    ],
  );
  Future<void> _import() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.importer.importRecords(
        confirmed: _confirmed,
        snapshotId: widget.snapshotId,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _error = error is AuthFailure ? '${error.message} 기기 원본은 유지됩니다.' : '이전 결과를 확인하지 못했습니다. 기기 원본은 유지됩니다. 자료를 다시 확인한 뒤 같은 요청으로 재시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
