import 'package:flutter/material.dart';

import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/input_dialog.dart';
import 'assistant_api.dart';

class SchoolQueryContextForm extends StatefulWidget {
  const SchoolQueryContextForm({
    super.key,
    required this.initial,
    required this.onSave,
    required this.onCancel,
    this.enabled = true,
  });
  final SchoolQueryContext initial;
  final Future<void> Function(SchoolQueryContext) onSave;
  final VoidCallback onCancel;
  final bool enabled;
  @override
  State<SchoolQueryContextForm> createState() => _ContextFormState();
}

class _ContextFormState extends State<SchoolQueryContextForm> {
  final _form = GlobalKey<FormState>();
  late final _school = TextEditingController(text: widget.initial.institution);
  late final _department = TextEditingController(
    text: widget.initial.department,
  );
  late final _year = TextEditingController(
    text: widget.initial.admissionYear?.toString(),
  );
  late String? _track = widget.initial.track;
  bool _saving = false;
  bool _dirty = false;
  String? _error;
  bool _confirming = false;

  Future<void> _cancel() async {
    if (_saving || _confirming || !widget.enabled) return;
    final changed =
        _school.text != (widget.initial.institution ?? '') ||
        _department.text != (widget.initial.department ?? '') ||
        _year.text != (widget.initial.admissionYear?.toString() ?? '') ||
        _track != widget.initial.track;
    if (changed) {
      _confirming = true;
      final discard = await confirmInputDiscard(context);
      _confirming = false;
      if (!discard) return;
    }
    if (mounted && !_saving && widget.enabled) widget.onCancel();
  }

  @override
  void dispose() {
    _school.dispose();
    _department.dispose();
    _year.dispose();

    super.dispose();
  }

  String? _value(TextEditingController controller) =>
      controller.text.trim().isEmpty ? null : controller.text.trim();
  @override
  Widget build(BuildContext context) => ExcludeFocus(
    excluding: _saving || !widget.enabled,
    child: IgnorePointer(
      ignoring: _saving || !widget.enabled,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '테스트용 설정창',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const Text(
              '설정과 같은 학교 정보를 사용합니다. 저장 후 질문을 보낼 때 질문과 아래 정보만 전송합니다. 개인 기록과 예시 졸업 기준은 전송하지 않습니다.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              onChanged: (_) => _dirty = true,
              controller: _school,
              maxLength: 128,
              decoration: const InputDecoration(
                labelText: '학교 (선택)',
                hintText: '예: 경동대학교',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              onChanged: (_) => _dirty = true,
              controller: _department,
              maxLength: 128,
              decoration: const InputDecoration(
                labelText: '학과 (선택)',
                hintText: '예: 컴퓨터공학과',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              onChanged: (_) => _dirty = true,
              controller: _year,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '입학연도 (선택)',
                hintText: '예: 2026',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return null;
                final year = int.tryParse(value.trim());
                return year == null || year < 1000 || year > 9999
                    ? '네 자리 입학연도를 입력해 주세요.'
                    : null;
              },
            ),
            const SizedBox(height: 16),
            AnchoredSelectField<String?>(
              value: _track,
              label: '이수경로 (선택)',
              options: [
                const SelectOption(null, '미입력'),
                const SelectOption('single_major', '단일전공'),
                const SelectOption('double_major', '복수전공'),
                if (_track != null &&
                    !['single_major', 'double_major'].contains(_track))
                  SelectOption(_track, _track!),
              ],
              onChanged: (value) {
                setState(() => _track = value);
                _dirty = true;
              },
            ),

            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _saving ? null : _cancel,
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '저장 중…' : '질의에 사용'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final value = SchoolQueryContext(
      institution: _value(_school),
      department: _value(_department),
      admissionYear: int.tryParse(_year.text.trim()),
      track: _track,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(value);
      if (mounted) setState(() => _dirty = false);
    } catch (_) {
      if (mounted) setState(() => _error = '저장하지 못했습니다. 입력을 유지했으니 다시 시도하세요.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void didUpdateWidget(covariant SchoolQueryContextForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty && !_saving) {
      _school.text = widget.initial.institution ?? '';
      _department.text = widget.initial.department ?? '';
      _year.text = widget.initial.admissionYear?.toString() ?? '';
      _track = widget.initial.track;
    }
  }
}
