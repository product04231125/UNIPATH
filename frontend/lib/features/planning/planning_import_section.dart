import 'package:flutter/material.dart';

import '../../shared/widgets/input_dialog.dart';
import '../auth/auth_api.dart';
import 'planning_repository.dart';

class PlanningImportSection extends StatelessWidget {
  const PlanningImportSection({super.key, required this.repository});
  final PlanningRepository repository;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextButton.icon(
        onPressed: repository.load,
        icon: const Icon(Icons.refresh),
        label: const Text('서버 자료 다시 불러오기'),
      ),
      if (repository.localPlanningNotice != null)
        Text(repository.localPlanningNotice!),
      if (repository.canImportLocalPlanning)
        OutlinedButton(
          onPressed: () => showInputDialog<void>(
            context: context,
            builder: (_) => _ImportDialog(repository: repository),
          ),
          child: const Text('기기 학업 정보·일정 이전'),
        ),
      const SizedBox(height: 12),
    ],
  );
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.repository});
  final PlanningRepository repository;
  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _changes = ValueNotifier(0);
  bool _confirmed = false, _saving = false;
  String? _error;
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
    title: const Text('기기 학업 정보·일정 이전'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.repository.localPlanningNotice ?? ''),
        const SizedBox(height: 12),
        const Text(
          '현재 로그인한 계정의 학업 정보와 개인 일정만 전송합니다. '
          '수강·활동·경험·자격·포트폴리오와 익명 자료는 전송하지 않습니다. '
          '기존 서버 학업 정보와 기기 원본은 유지합니다.',
        ),
        const SizedBox(height: 12),
        for (final value in widget.repository.localPlanningPreview)
          Align(alignment: Alignment.centerLeft, child: Text(value)),
        const SizedBox(height: 12),
        Text(
          '시간대: ${DateTime.now().timeZoneName} (현재 UTC 오프셋 ${DateTime.now().timeZoneOffset}). '
          '기기 일정을 작성한 당시와 같은 시간대인지 확인해 주세요. '
          '일정은 이 기기의 시간대로 해석하고 UTC 시각으로 전송합니다.',
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('자료 범위와 시간대를 확인했으며 서버 이전에 동의합니다.'),
          value: _confirmed,
          onChanged: _saving
              ? null
              : (value) => setState(() {
                  _confirmed = value == true;
                  _changes.value++;
                }),
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
      await widget.repository.importLocalPlanning(confirmed: _confirmed);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AuthFailure
              ? error.message
              : '이전 결과를 확인하지 못했습니다. 기기 원본은 유지됩니다. 다시 확인해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
