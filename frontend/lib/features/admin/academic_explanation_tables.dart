import 'dart:convert';

import 'package:flutter/material.dart';

import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/field_label.dart';
import '../../shared/widgets/horizontal_scroll_area.dart';
import '../records/personal_record_repository.dart';

class _TableDraft {
  _TableDraft(Map<String, dynamic> data)
    : id = data['id'] as String,
      title = TextEditingController(text: data['title'] as String),
      groupId = data['group_id'] as String?,
      columns = [
        for (final text in data['columns'] as List)
          TextEditingController(text: text as String),
      ],
      rows = [
        for (final row in data['rows'] as List)
          [
            for (final text in row as List)
              TextEditingController(text: text as String),
          ],
      ];
  final String id;
  final TextEditingController title;
  String? groupId;
  final List<TextEditingController> columns;
  final List<List<TextEditingController>> rows;
  final scroll = ScrollController();
  Iterable<TextEditingController> get controllers => [
    title,
    ...columns,
    for (final row in rows) ...row,
  ];
  Map<String, Object?> get json => {
    'id': id,
    'title': title.text,
    'group_id': groupId,
    'columns': [for (final c in columns) c.text],
    'rows': [
      for (final row in rows) [for (final c in row) c.text],
    ],
  };
  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
    scroll.dispose();
  }
}

class AcademicExplanationTables extends StatefulWidget {
  const AcademicExplanationTables({
    super.key,
    required this.initial,
    required this.enabled,
    required this.groups,
    required this.onChanged,
  });
  final List<Map<String, dynamic>> initial;
  final bool enabled;
  final List<SelectOption<String>> groups;
  final VoidCallback onChanged;
  @override
  State<AcademicExplanationTables> createState() =>
      AcademicExplanationTablesState();
}

class AcademicExplanationTablesState extends State<AcademicExplanationTables> {
  final _tables = <_TableDraft>[];
  late final String _initial;
  List<Map<String, dynamic>> get value => [
    for (final table in _tables) Map<String, dynamic>.from(table.json),
  ];
  bool get dirty => jsonEncode(value) != _initial;
  void _changed() {
    if (mounted) setState(() {});
    widget.onChanged();
  }

  void _wire(_TableDraft table) {
    for (final c in table.controllers) {
      c.addListener(_changed);
    }
  }

  @override
  void initState() {
    super.initState();
    for (final raw in widget.initial) {
      final t = _TableDraft(raw);
      _wire(t);
      _tables.add(t);
    }
    _initial = jsonEncode(value);
  }

  @override
  void dispose() {
    for (final table in _tables) {
      table.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('보충 설명 표', style: Theme.of(context).textTheme.titleSmall),
      const Text('시험별 점수 등 규정 표를 작성합니다. 표의 숫자로 취득 여부를 자동 판단하지 않습니다.'),
      for (final table in _tables)
        Padding(
          key: ValueKey(table.id),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FieldLabel(
                label: '표 제목',
                child: TextField(
                  controller: table.title,
                  enabled: widget.enabled,
                  maxLength: 128,
                ),
              ),
              AnchoredSelectField<String>(
                externalLabel: true,
                label: '표를 표시할 영역',
                value: table.groupId ?? '',
                options: [
                  const SelectOption('', '인증 요건 공통'),
                  ...widget.groups,
                  if (table.groupId != null &&
                      !widget.groups.any((g) => g.value == table.groupId))
                    SelectOption(table.groupId!, '삭제된 영역 · 연결 확인'),
                ],
                onChanged: (id) {
                  if (widget.enabled) {
                    setState(() => table.groupId = id.isEmpty ? null : id);
                    widget.onChanged();
                  }
                },
              ),
              if (table.columns.isEmpty)
                const Text('열과 행을 추가해 설명 표를 작성하세요.')
              else
                HorizontalScrollArea(
                  controller: table.scroll,
                  child: Table(
                    defaultColumnWidth: const FixedColumnWidth(180),
                    border: TableBorder.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    children: [
                      TableRow(
                        children: [
                          for (final column in table.columns)
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                children: [
                                  TextField(
                                    controller: column,
                                    enabled: widget.enabled,
                                    decoration: const InputDecoration(
                                      labelText: '열 제목',
                                    ),
                                    maxLength: 128,
                                  ),
                                  if (widget.enabled)
                                    TextButton(
                                      onPressed: () {
                                        final index = table.columns.indexOf(
                                          column,
                                        );
                                        setState(() {
                                          table.columns
                                              .removeAt(index)
                                              .dispose();
                                          for (final row in table.rows) {
                                            row.removeAt(index).dispose();
                                          }
                                        });
                                        widget.onChanged();
                                      },
                                      child: const Text('열 제거'),
                                    ),
                                ],
                              ),
                            ),
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text('행 관리'),
                          ),
                        ],
                      ),
                      for (final row in table.rows)
                        TableRow(
                          children: [
                            for (final cell in row)
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: TextField(
                                  controller: cell,
                                  enabled: widget.enabled,
                                  minLines: 1,
                                  maxLines: 5,
                                  maxLength: 8000,
                                ),
                              ),
                            if (widget.enabled)
                              TextButton(
                                onPressed: () {
                                  setState(() => table.rows.remove(row));
                                  for (final c in row) {
                                    c.dispose();
                                  }
                                  widget.onChanged();
                                },
                                child: const Text('행 제거'),
                              )
                            else
                              const SizedBox.shrink(),
                          ],
                        ),
                    ],
                  ),
                ),
              if (widget.enabled)
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: table.columns.length >= 50
                          ? null
                          : () {
                              setState(() {
                                final col = TextEditingController()
                                  ..addListener(_changed);
                                table.columns.add(col);
                                for (final row in table.rows) {
                                  row.add(
                                    TextEditingController()
                                      ..addListener(_changed),
                                  );
                                }
                              });
                              widget.onChanged();
                            },
                      child: const Text('설명 표 열 추가'),
                    ),
                    OutlinedButton(
                      onPressed:
                          table.columns.isEmpty || table.rows.length >= 100
                          ? null
                          : () {
                              setState(
                                () => table.rows.add([
                                  for (final _ in table.columns)
                                    TextEditingController()
                                      ..addListener(_changed),
                                ]),
                              );
                              widget.onChanged();
                            },
                      child: const Text('설명 표 행 추가'),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() => _tables.remove(table));
                        table.dispose();
                        widget.onChanged();
                      },
                      child: const Text('설명 표 제거'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      if (widget.enabled)
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: _tables.length >= 50
                ? null
                : () {
                    final table = _TableDraft({
                      'id': PersonalRecord.newId(),
                      'title': '',
                      'columns': <String>[],
                      'rows': <Object>[],
                    });
                    _wire(table);
                    setState(() => _tables.add(table));
                    widget.onChanged();
                  },
            child: const Text('보충 설명 표 추가'),
          ),
        ),
    ],
  );
}
