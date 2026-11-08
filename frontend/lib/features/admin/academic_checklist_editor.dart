import 'dart:convert';

import 'package:flutter/material.dart';

import '../../shared/widgets/anchored_select_field.dart';
import '../records/personal_record_repository.dart';
import 'academic_scope_dialog.dart';

class _Line {
  _Line(Map<String, dynamic> input)
    : id = input['id'] as String,
      text = TextEditingController(text: input['text'] as String),
      scope = input['scope'] == null
          ? null
          : Map<String, dynamic>.from(input['scope'] as Map);
  final String id;
  final TextEditingController text;
  Map<String, dynamic>? scope;
}

class AcademicChecklistEditor extends StatefulWidget {
  const AcademicChecklistEditor({
    super.key,
    required this.initial,
    required this.enabled,
    required this.departments,
    required this.tracks,
    required this.onChanged,
  });
  final Map<String, dynamic> initial;
  final bool enabled;
  final List<SelectOption<String>> departments;
  final List<Map<String, dynamic>> tracks;
  final VoidCallback onChanged;
  @override
  State<AcademicChecklistEditor> createState() =>
      AcademicChecklistEditorState();
}

class AcademicChecklistEditorState extends State<AcademicChecklistEditor> {
  final _lines = <_Line>[];
  late final String _initial;
  Map<String, Object?> get content => {
    'kind': 'checklist',
    'lines': [
      for (final line in _lines)
        {'id': line.id, 'text': line.text.text, 'scope': line.scope},
    ],
  };
  bool get dirty => jsonEncode(content) != _initial;
  void _changed() {
    if (mounted) setState(() {});
    widget.onChanged();
  }

  void _add(Map<String, dynamic> input) {
    final line = _Line(input);
    line.text.addListener(_changed);
    _lines.add(line);
  }

  @override
  void initState() {
    super.initState();
    for (final raw in widget.initial['lines'] as List) {
      _add(Map<String, dynamic>.from(raw as Map));
    }
    _initial = jsonEncode(content);
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.text.dispose();
    }
    super.dispose();
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _lines.length) return;
    setState(() => _lines.insert(target, _lines.removeAt(index)));
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '한 줄 요건 ${_lines.length}개',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      if (_lines.isEmpty) const Text('작성한 문장이 없습니다. 한 줄 요건을 추가하세요.'),
      for (final line in _lines)
        Padding(
          key: ValueKey(line.id),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.enabled)
                TextField(
                  key: ValueKey('checklist-text-${line.id}'),
                  controller: line.text,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 8000,
                  decoration: InputDecoration(
                    labelText: '요건 ${_lines.indexOf(line) + 1}',
                  ),
                )
              else
                Text('${_lines.indexOf(line) + 1}. ${line.text.text}'),
              if (widget.enabled)
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () async {
                        final selected = await editAcademicScope(
                          context: context,
                          title: '이 문장의 적용 대상',
                          initial: line.scope,
                          departments: widget.departments,
                          tracks: widget.tracks,
                        );
                        if (selected != null && mounted) {
                          setState(() => line.scope = selected.scope);
                          widget.onChanged();
                        }
                      },
                      child: Text(
                        line.scope == null ? '적용 대상: 공통 사용' : '별도 적용 대상',
                      ),
                    ),
                    IconButton(
                      tooltip: '요건 위로',
                      onPressed: _lines.indexOf(line) == 0
                          ? null
                          : () => _move(_lines.indexOf(line), -1),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      tooltip: '요건 아래로',
                      onPressed: _lines.indexOf(line) == _lines.length - 1
                          ? null
                          : () => _move(_lines.indexOf(line), 1),
                      icon: const Icon(Icons.arrow_downward),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() => _lines.remove(line));
                        line.text.dispose();
                        widget.onChanged();
                      },
                      child: const Text('문장 제거'),
                    ),
                  ],
                )
              else if (line.scope != null)
                const Text('이 문장은 별도 적용 범위를 사용합니다.'),
            ],
          ),
        ),
      if (widget.enabled)
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () {
              setState(() => _add({'id': PersonalRecord.newId(), 'text': ''}));
              widget.onChanged();
            },
            child: const Text('한 줄 요건 추가'),
          ),
        ),
    ],
  );
}
