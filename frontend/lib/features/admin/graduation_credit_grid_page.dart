import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/digits_only_hint.dart';
import '../../shared/widgets/feature_line.dart';
import '../../shared/widgets/field_label.dart';
import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/surface_card.dart';
import 'admin_models.dart';
import 'graduation_credit_grid.dart';
import 'graduation_template_preview.dart';

class GraduationCreditGridPage extends StatefulWidget {
  const GraduationCreditGridPage({
    super.key,
    required this.schoolName,
    required this.departments,
    this.initial,
    this.scrollable = false,
  });

  final String schoolName;
  final List<AdminRecord> departments;
  final GraduationCreditGrid? initial;
  final bool scrollable;

  @override
  State<GraduationCreditGridPage> createState() =>
      GraduationCreditGridPageState();
}

class GraduationCreditGridPageState extends State<GraduationCreditGridPage> {
  late GraduationCreditGrid _grid;
  late final TextEditingController _year;
  final _groupLabels = <String, TextEditingController>{};
  final _columnLabels = <String, TextEditingController>{};
  final _rowLabels = <String, TextEditingController>{};
  final _rowNotes = <String, TextEditingController>{};
  final _cellValues = <String, TextEditingController>{};
  var _copied = false;
  late final String _initial;

  @override
  void initState() {
    super.initState();
    _grid = widget.initial != null
        ? copyCreditGrid(widget.initial!, regenerateIds: false)
        : GraduationCreditGrid(
            admissionYear: '',
            departmentId: widget.departments.firstOrNull?.id ?? '',
          );
    _year = TextEditingController(text: _grid.admissionYear);
    _year.addListener(() {
      _grid.admissionYear = _year.text.trim();
      setState(() {});
    });
    _syncControllers();
    _initial = _fingerprint;
  }

  @override
  void dispose() {
    _year.dispose();
    for (final controller in [
      ..._groupLabels.values,
      ..._columnLabels.values,
      ..._rowLabels.values,
      ..._rowNotes.values,
      ..._cellValues.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String get _fingerprint => jsonEncode([
    _grid.admissionYear,
    _grid.departmentId,
    [
      for (final g in _grid.groups) [g.id, g.label],
    ],
    [
      for (final c in _grid.columns) [c.id, c.label, c.groupId],
    ],
    [
      for (final r in _grid.rows)
        [
          r.id,
          r.label,
          r.note,
          [
            for (final c in _grid.columns)
              [
                _grid.cellFor(r.id, c.id).kind.name,
                _grid.cellFor(r.id, c.id).value,
              ],
          ],
        ],
    ],
  ]);

  bool get dirty => _fingerprint != _initial;

  Future<bool> allowLeave() async =>
      !dirty || await confirmInputDiscardAllowsLeave(context);

  void _syncControllers() {
    _bind(_groupLabels, [for (final group in _grid.groups) group.id], (id) {
      final group = _grid.groups.firstWhere((g) => g.id == id);
      return TextEditingController(text: group.label)..addListener(() {
        group.label = _groupLabels[id]!.text;
        setState(() {});
      });
    });
    _bind(_columnLabels, [for (final column in _grid.columns) column.id], (id) {
      final column = _grid.columns.firstWhere((c) => c.id == id);
      return TextEditingController(text: column.label)..addListener(() {
        column.label = _columnLabels[id]!.text;
        setState(() {});
      });
    });
    _bind(_rowLabels, [for (final row in _grid.rows) row.id], (id) {
      final row = _grid.rows.firstWhere((r) => r.id == id);
      return TextEditingController(text: row.label)..addListener(() {
        row.label = _rowLabels[id]!.text;
        setState(() {});
      });
    });
    _bind(_rowNotes, [for (final row in _grid.rows) row.id], (id) {
      final row = _grid.rows.firstWhere((r) => r.id == id);
      return TextEditingController(text: row.note)..addListener(() {
        row.note = _rowNotes[id]!.text;
        setState(() {});
      });
    });
    _bind(
      _cellValues,
      [
        for (final row in _grid.rows)
          for (final column in _grid.columns)
            GraduationCreditGrid.cellKey(row.id, column.id),
      ],
      (key) {
        final parts = key.split('/');
        final cell = _grid.cellFor(parts[0], parts[1]);
        return TextEditingController(
          text: cell.kind == GraduationCreditCellKind.number
              ? (cell.value ?? '')
              : '',
        )..addListener(() {
          if (cell.kind == GraduationCreditCellKind.number) {
            cell.value = _cellValues[key]!.text;
            setState(() {});
          }
        });
      },
    );
  }

  void _bind(
    Map<String, TextEditingController> map,
    List<String> ids,
    TextEditingController Function(String id) create,
  ) {
    for (final id in map.keys.toList()) {
      if (!ids.contains(id)) map.remove(id)?.dispose();
    }
    for (final id in ids) {
      map.putIfAbsent(id, () => create(id));
    }
  }

  void _addGroup() {
    setState(() {
      final group = GraduationCreditColumnGroup(
        id: GraduationCreditGrid.newId('group'),
        label: '',
      );
      _grid.groups.add(group);
      _grid.columns.add(
        GraduationCreditColumn(
          id: GraduationCreditGrid.newId('column'),
          label: '',
          groupId: group.id,
        ),
      );
      _syncControllers();
    });
  }

  void _addColumn({String? groupId}) {
    setState(() {
      _grid.columns.add(
        GraduationCreditColumn(
          id: GraduationCreditGrid.newId('column'),
          label: '',
          groupId: groupId,
        ),
      );
      _syncControllers();
    });
  }

  void _addRow() {
    setState(() {
      _grid.rows.add(
        GraduationCreditRow(id: GraduationCreditGrid.newId('row'), label: ''),
      );
      _syncControllers();
    });
  }

  void _removeColumn(GraduationCreditColumn column) {
    setState(() {
      _grid.columns.remove(column);
      _grid.cells.removeWhere((key, _) => _cellColumnId(key) == column.id);
      final groupId = column.groupId;
      if (groupId != null &&
          _grid.columns.every((other) => other.groupId != groupId)) {
        _grid.groups.removeWhere((group) => group.id == groupId);
      }
      _syncControllers();
    });
  }

  void _removeGroup(String groupId) {
    setState(() {
      final columnIds = {
        for (final column in _grid.columns)
          if (column.groupId == groupId) column.id,
      };
      _grid.columns.removeWhere((column) => column.groupId == groupId);
      _grid.groups.removeWhere((group) => group.id == groupId);
      _grid.cells.removeWhere(
        (key, _) => columnIds.contains(_cellColumnId(key)),
      );
      _syncControllers();
    });
  }

  void _removeRow(GraduationCreditRow row) {
    setState(() {
      _grid.rows.remove(row);
      _grid.cells.removeWhere((key, _) => key.startsWith('${row.id}/'));
      _syncControllers();
    });
  }

  String _cellColumnId(String key) {
    final slash = key.indexOf('/');
    return slash < 0 ? '' : key.substring(slash + 1);
  }

  bool _firstInGroup(GraduationCreditColumn column) {
    final groupId = column.groupId;
    if (groupId == null) return false;
    return _grid.columns.firstWhere((other) => other.groupId == groupId).id ==
        column.id;
  }

  Widget _removeButton({required Key key, required VoidCallback onPressed}) =>
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: key,
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: onPressed,
          child: const Text('제거'),
        ),
      );

  void _copyYear() {
    setState(() {
      _grid = copyCreditGrid(_grid);
      _copied = true;
      _year.text = _grid.admissionYear;
      _syncControllers();
    });
  }

  void _setKind(
    GraduationCreditRow row,
    GraduationCreditColumn column,
    GraduationCreditCellKind kind,
  ) {
    setState(() {
      final cell = _grid.cellFor(row.id, column.id);
      cell.kind = kind;
      if (kind != GraduationCreditCellKind.number) {
        cell.value = null;
        _cellValues[GraduationCreditGrid.cellKey(row.id, column.id)]?.clear();
      }
      _syncControllers();
    });
  }

  String? _mismatch(GraduationCreditRow row, GraduationCreditColumn column) {
    if (column.groupId != null) return null;
    final cell = _grid.cellFor(row.id, column.id);
    if (cell.kind != GraduationCreditCellKind.number) return null;
    final entered = parseCreditNumber(cell.value ?? '');
    if (entered == null) return null;
    final matchingGroup = _grid.groups
        .where((group) => group.label == column.label)
        .firstOrNull;
    if (matchingGroup == null) return null;
    final sum = summedLeafCredits(_grid, row, matchingGroup.id);
    if (sum == 0 || sum == entered) return null;
    return '잎 칸 합 $sum과 입력한 ${column.label} $entered이 다릅니다. 문서 숫자는 그대로 둡니다.';
  }

  @override
  Widget build(BuildContext context) {
    final body = SurfaceCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FeatureLine.section(
            text: '학점표',
            padTop: false,
            padBottom: false,
          ),
          const SizedBox(height: 8),
          const Text(
            '입학연도마다 열과 이수 경로 행을 직접 만듭니다. 숫자는 문서에 적힌 값이며, 화면이 소계를 계산하거나 졸업을 판정하지 않습니다.',
          ),
          Text('학교: ${widget.schoolName}'),
          const SizedBox(height: 12),
          FieldLabel(
            label: '학과',
            child: widget.departments.isEmpty
                ? const Text('현재 학교에 등록된 학과가 없습니다. 학교·학과 메뉴에서 학과를 먼저 등록하세요.')
                : AnchoredSelectField<String>(
                    key: const ValueKey('credit-grid-department'),
                    externalLabel: true,
                    value: _grid.departmentId,
                    label: '학과',
                    options: [
                      for (final department in widget.departments)
                        SelectOption(department.id, department.name),
                    ],
                    onChanged: (id) => setState(() => _grid.departmentId = id),
                  ),
          ),
          const SizedBox(height: 12),
          FieldLabel(
            label: '입학연도',
            child: TextFormField(
              key: const ValueKey('credit-grid-year'),
              controller: _year,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: digitsOnlyDecoration(
                context,
                base: const InputDecoration(hintText: '2026'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: const ValueKey('credit-grid-add-group'),
                onPressed: _addGroup,
                child: const Text('열 묶음 추가'),
              ),
              OutlinedButton(
                key: const ValueKey('credit-grid-add-column'),
                onPressed: () => _addColumn(),
                child: const Text('독립 열 추가'),
              ),
              OutlinedButton(
                key: const ValueKey('credit-grid-add-row'),
                onPressed: _addRow,
                child: const Text('이수 경로 행 추가'),
              ),
              OutlinedButton(
                key: const ValueKey('credit-grid-copy-year'),
                onPressed: _grid.columns.isEmpty && _grid.rows.isEmpty
                    ? null
                    : _copyYear,
                child: const Text('이 표를 다른 연도로 복사'),
              ),
              OutlinedButton(
                key: const ValueKey('credit-grid-preview'),
                onPressed: () => showGraduationTemplatePreview(
                  context: context,
                  title: '학점표 미리보기',
                  child: GraduationCreditGridPreview(
                    grid: _grid,
                    schoolName: widget.schoolName,
                    departments: widget.departments,
                  ),
                ),
                child: const Text('미리보기'),
              ),
            ],
          ),
          if (_copied)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('열과 행을 복사했습니다. 입학연도와 칸 숫자만 고치면 됩니다.'),
            ),
          const SizedBox(height: 16),
          if (_grid.columns.isEmpty && _grid.rows.isEmpty)
            const Text('열 묶음이나 이수 경로 행을 추가해 표를 만드세요. 학교마다 열 이름이 다를 수 있습니다.')
          else
            SurfaceCard(child: _table()),
          const SizedBox(height: 12),
          const Text('저장은 연결되지 않았습니다. 학점표는 현재 실행 규칙 API의 학점 조건 하나에 넣을 수 없습니다.'),
          const SizedBox(height: 8),
          const FilledButton(onPressed: null, child: Text('학점표 저장 불가 · 연결 전')),
        ],
      ),
    );
    if (!widget.scrollable) return body;
    return SingleChildScrollView(child: body);
  }

  Widget _table() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: TableBorder.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        children: [
          TableRow(
            children: [
              const Padding(padding: EdgeInsets.all(8), child: Text('열 묶음')),
              for (final column in _grid.columns)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: column.groupId == null
                      ? const Text('독립 열')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              key: ValueKey(
                                'credit-grid-group-${column.groupId}',
                              ),
                              controller: _groupLabels[column.groupId],
                              decoration: const InputDecoration(
                                isDense: true,
                                hintText: '교양 과목',
                              ),
                            ),
                            if (_firstInGroup(column))
                              _removeButton(
                                key: ValueKey(
                                  'credit-grid-remove-group-${column.groupId}',
                                ),
                                onPressed: () => _removeGroup(column.groupId!),
                              ),
                          ],
                        ),
                ),
              const Padding(padding: EdgeInsets.all(8), child: Text('비고')),
            ],
          ),
          TableRow(
            children: [
              const Padding(padding: EdgeInsets.all(8), child: Text('이수 경로')),
              for (final column in _grid.columns)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: ValueKey('credit-grid-column-${column.id}'),
                        controller: _columnLabels[column.id],
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: '기초교양',
                        ),
                      ),
                      if (column.groupId != null && _firstInGroup(column))
                        TextButton(
                          key: ValueKey(
                            'credit-grid-add-leaf-${column.groupId}',
                          ),
                          onPressed: () => _addColumn(groupId: column.groupId),
                          child: const Text('같은 묶음 열 추가'),
                        ),
                      _removeButton(
                        key: ValueKey('credit-grid-remove-column-${column.id}'),
                        onPressed: () => _removeColumn(column),
                      ),
                    ],
                  ),
                ),
              const Padding(padding: EdgeInsets.all(8), child: Text('문서 비고')),
            ],
          ),
          for (final row in _grid.rows)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: ValueKey('credit-grid-row-${row.id}'),
                        controller: _rowLabels[row.id],
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: '단일전공',
                        ),
                      ),
                      _removeButton(
                        key: ValueKey('credit-grid-remove-row-${row.id}'),
                        onPressed: () => _removeRow(row),
                      ),
                    ],
                  ),
                ),
                for (final column in _grid.columns)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: _cellEditor(row, column),
                  ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    key: ValueKey('credit-grid-note-${row.id}'),
                    controller: _rowNotes[row.id],
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '다른전공 병행이수',
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cellEditor(GraduationCreditRow row, GraduationCreditColumn column) {
    final cell = _grid.cellFor(row.id, column.id);
    final key = GraduationCreditGrid.cellKey(row.id, column.id);
    final mismatch = _mismatch(row, column);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _kindChip(row, column, GraduationCreditCellKind.empty, '비어 있음'),
            _kindChip(row, column, GraduationCreditCellKind.number, '숫자'),
            _kindChip(
              row,
              column,
              GraduationCreditCellKind.notApplicable,
              '해당 없음',
            ),
          ],
        ),
        if (cell.kind == GraduationCreditCellKind.number)
          TextField(
            key: ValueKey('credit-grid-cell-$key'),
            controller: _cellValues[key],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              TextInputFormatter.withFunction((oldValue, newValue) =>
                RegExp(r'^\d*(?:\.\d{0,3})?$').hasMatch(newValue.text)
                  ? newValue : oldValue),
            ],
            decoration: InputDecoration(
              isDense: true,
              hintText: '7.5',
              helperText: '소수 셋째 자리까지',
              errorText: (cell.value ?? '').isNotEmpty && parseCreditNumber(cell.value!) == null
                ? '0 이상의 학점을 입력하세요.' : null,
            ),
          )
        else
          Text(
            cell.kind == GraduationCreditCellKind.notApplicable
                ? '해당 없음'
                : '비어 있음',
            key: ValueKey('credit-grid-cell-$key'),
          ),
        if (mismatch != null)
          Text(
            mismatch,
            key: ValueKey('credit-grid-mismatch-$key'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }

  Widget _kindChip(
    GraduationCreditRow row,
    GraduationCreditColumn column,
    GraduationCreditCellKind kind,
    String label,
  ) {
    return FilterChip(
      key: ValueKey(
        'credit-grid-kind-${GraduationCreditGrid.cellKey(row.id, column.id)}-${kind.name}',
      ),
      selected: _grid.cellFor(row.id, column.id).kind == kind,
      label: Text(label),
      onSelected: (_) => _setKind(row, column, kind),
    );
  }
}
