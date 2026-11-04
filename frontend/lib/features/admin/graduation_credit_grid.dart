/// Local credit-table draft. Not a rule-programs DTO.
enum GraduationCreditCellKind { empty, number, notApplicable }

class GraduationCreditColumnGroup {
  GraduationCreditColumnGroup({required this.id, required this.label});
  final String id;
  String label;
}

class GraduationCreditColumn {
  GraduationCreditColumn({required this.id, required this.label, this.groupId});
  final String id;
  String label;
  String? groupId;
}

class GraduationCreditRow {
  GraduationCreditRow({required this.id, required this.label, this.note = ''});
  final String id;
  String label;
  String note;
}

class GraduationCreditCell {
  GraduationCreditCell({
    this.kind = GraduationCreditCellKind.empty,
    this.value,
  });
  GraduationCreditCellKind kind;
  String? value;
}

class GraduationCreditGrid {
  GraduationCreditGrid({
    required this.admissionYear,
    required this.departmentId,
    List<GraduationCreditColumnGroup>? groups,
    List<GraduationCreditColumn>? columns,
    List<GraduationCreditRow>? rows,
    Map<String, GraduationCreditCell>? cells,
  }) : groups = groups ?? [],
       columns = columns ?? [],
       rows = rows ?? [],
       cells = cells ?? {};

  String admissionYear;
  String departmentId;
  final List<GraduationCreditColumnGroup> groups;
  final List<GraduationCreditColumn> columns;
  final List<GraduationCreditRow> rows;
  final Map<String, GraduationCreditCell> cells;

  static String cellKey(String rowId, String columnId) => '$rowId/$columnId';

  GraduationCreditCell cellFor(String rowId, String columnId) =>
      cells.putIfAbsent(cellKey(rowId, columnId), GraduationCreditCell.new);

  static String newId([String prefix = 'grid']) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';
}

int? parseCreditNumber(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  return int.tryParse(trimmed);
}

int summedLeafCredits(
  GraduationCreditGrid grid,
  GraduationCreditRow row,
  String groupId,
) {
  var total = 0;
  var any = false;
  for (final column in grid.columns.where((c) => c.groupId == groupId)) {
    final cell = grid.cellFor(row.id, column.id);
    if (cell.kind != GraduationCreditCellKind.number) continue;
    final value = parseCreditNumber(cell.value ?? '');
    if (value == null) continue;
    any = true;
    total += value;
  }
  return any ? total : 0;
}

GraduationCreditGrid copyCreditGrid(GraduationCreditGrid source) {
  final groupIds = <String, String>{
    for (final group in source.groups)
      group.id: GraduationCreditGrid.newId('group'),
  };
  final columnIds = <String, String>{
    for (final column in source.columns)
      column.id: GraduationCreditGrid.newId('column'),
  };
  final rowIds = <String, String>{
    for (final row in source.rows) row.id: GraduationCreditGrid.newId('row'),
  };
  final copy = GraduationCreditGrid(
    admissionYear: source.admissionYear,
    departmentId: source.departmentId,
    groups: [
      for (final group in source.groups)
        GraduationCreditColumnGroup(
          id: groupIds[group.id]!,
          label: group.label,
        ),
    ],
    columns: [
      for (final column in source.columns)
        GraduationCreditColumn(
          id: columnIds[column.id]!,
          label: column.label,
          groupId: column.groupId == null ? null : groupIds[column.groupId],
        ),
    ],
    rows: [
      for (final row in source.rows)
        GraduationCreditRow(
          id: rowIds[row.id]!,
          label: row.label,
          note: row.note,
        ),
    ],
  );
  for (final row in source.rows) {
    for (final column in source.columns) {
      final sourceCell = source.cellFor(row.id, column.id);
      final target = copy.cellFor(rowIds[row.id]!, columnIds[column.id]!);
      target.kind = sourceCell.kind;
      target.value = sourceCell.value;
    }
  }
  return copy;
}
