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

  static int _nextId = 0;
  static String newId([String prefix = 'grid']) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';
}

BigInt? _creditThousandths(String text) {
  final value = text.trim();
  if (!RegExp(r'^\d+(?:\.\d{1,3})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  return BigInt.parse(parts.first) * BigInt.from(1000) +
      BigInt.parse(parts.length == 1 ? '0' : parts.last.padRight(3, '0'));
}

num _creditValue(BigInt scaled) {
  final whole = scaled ~/ BigInt.from(1000);
  final fraction = (scaled % BigInt.from(1000)).toString().padLeft(3, '0');
  return num.parse('$whole.$fraction');
}

num? parseCreditNumber(String text) {
  final scaled = _creditThousandths(text);
  if (scaled == null) return null;
  final value = _creditValue(scaled);
  if (!value.isFinite) return null;
  return value == value.roundToDouble() ? value.toInt() : value;
}

num summedLeafCredits(
  GraduationCreditGrid grid,
  GraduationCreditRow row,
  String groupId,
) {
  var total = BigInt.zero;
  for (final column in grid.columns.where((c) => c.groupId == groupId)) {
    final cell = grid.cellFor(row.id, column.id);
    if (cell.kind != GraduationCreditCellKind.number) continue;
    final scaled = _creditThousandths(cell.value ?? '');
    if (scaled != null) total += scaled;
  }
  final value = _creditValue(total);
  return value == value.roundToDouble() ? value.toInt() : value;
}

GraduationCreditGrid copyCreditGrid(
  GraduationCreditGrid source, {
  bool regenerateIds = true,
}) {
  final groupIds = <String, String>{
    for (final group in source.groups)
      group.id: regenerateIds ? GraduationCreditGrid.newId('group') : group.id,
  };
  final columnIds = <String, String>{
    for (final column in source.columns)
      column.id: regenerateIds
          ? GraduationCreditGrid.newId('column')
          : column.id,
  };
  final rowIds = <String, String>{
    for (final row in source.rows)
      row.id: regenerateIds ? GraduationCreditGrid.newId('row') : row.id,
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
      final sourceCell =
          source.cells[GraduationCreditGrid.cellKey(row.id, column.id)];
      if (sourceCell == null) continue;
      final target = copy.cellFor(rowIds[row.id]!, columnIds[column.id]!);
      target.kind = sourceCell.kind;
      target.value = sourceCell.value;
    }
  }
  return copy;
}
