import 'package:flutter/material.dart';

import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/input_dialog.dart';
import 'assistant_api.dart';

Future<SchoolQueryContext?> showAssistantContextDialog(
  BuildContext context,
  SchoolQueryContext initial,
) => showInputDialog<SchoolQueryContext>(
  context: context,
  builder: (_) => _ContextForm(initial: initial),
);

class _ContextForm extends StatefulWidget {
  const _ContextForm({required this.initial});
  final SchoolQueryContext initial;
  @override
  State<_ContextForm> createState() => _ContextFormState();
}

class _ContextFormState extends State<_ContextForm> {
  final _form = GlobalKey<FormState>();
  late final _school = TextEditingController(text: widget.initial.institution);
  late final _department = TextEditingController(
    text: widget.initial.department,
  );
  late final _year = TextEditingController(
    text: widget.initial.admissionYear?.toString(),
  );
  late String? _track = widget.initial.track;
  final _changes = ValueNotifier<int>(0);
  @override
  void dispose() {
    _school.dispose();
    _department.dispose();
    _year.dispose();
    _changes.dispose();
    super.dispose();
  }

  String? _value(TextEditingController controller) =>
      controller.text.trim().isEmpty ? null : controller.text.trim();
  @override
  Widget build(BuildContext context) => InputDialog(
    title: const Text('학교 질의 정보'),
    changes: Listenable.merge([_school, _department, _year, _changes]),
    hasContent: () =>
        [_school, _department, _year].any((c) => c.text.trim().isNotEmpty) ||
        _track != null,
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '질문과 아래 정보만 서버에 전송합니다. 개인 기록과 예시 졸업 기준은 전송하지 않습니다. 설정의 학업 정보와 별도로 이 창에서만 사용합니다.',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _school,
            maxLength: 128,
            decoration: const InputDecoration(
              labelText: '학교 (선택)',
              hintText: '예: 경동대학교',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _department,
            maxLength: 128,
            decoration: const InputDecoration(
              labelText: '학과 (선택)',
              hintText: '예: 컴퓨터공학과',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
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
              _changes.value++;
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.of(context).pop(
              SchoolQueryContext(
                institution: _value(_school),
                department: _value(_department),
                admissionYear: int.tryParse(_year.text.trim()),
                track: _track,
              ),
            );
          }
        },
        child: const Text('질의에 사용'),
      ),
    ],
  );
}
