import 'dart:convert';

import '../records/personal_record_repository.dart';

/// Editor model; the academic workspace adapter owns its wire representation.
enum GraduationCreditCellKind { empty, number, notApplicable }

class GraduationCreditColumnGroup {
  GraduationCreditColumnGroup({
    required this.id,
    required this.label,
    this.parentId,
    this.position = 0,
  });
  final String id;
  String label;
  String? parentId;
  int position;
}

class GraduationCreditColumn {
  GraduationCreditColumn({
    required this.id,
    required this.label,
    this.groupId,
    this.role = 'value',
    this.classificationNodeId,
    this.requirement,
    this.aggregateMembers = const [],
    this.position = 0,
    this.matchMode = 'subtree',
  });
  final String id;
  String label;
  String? groupId;
  String role;
  String? classificationNodeId, requirement;
  List<String> aggregateMembers;
  int position;
  String matchMode;
}

class GraduationCreditRow {
  GraduationCreditRow({
    required this.id,
    required this.label,
    this.note = '',
    this.scope,
  });
  final String id;
  String label;
  String note;
  Map<String, dynamic>? scope;
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

  static String newId([String prefix = 'grid']) => PersonalRecord.newId();
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

List<GraduationCreditColumn> orderedCreditColumns(GraduationCreditGrid grid) {
  final result = <GraduationCreditColumn>[], visited = <String>{};
  void walk(String? parent) {
    final items = <({String id, int position, bool group})>[
      for (final g in grid.groups)
        if (g.parentId == parent) (id: g.id, position: g.position, group: true),
      for (final c in grid.columns)
        if (c.groupId == parent) (id: c.id, position: c.position, group: false),
    ]..sort((a, b) => a.position.compareTo(b.position));
    for (final item in items) {
      if (!visited.add(item.id)) continue;
      if (item.group) {
        walk(item.id);
      } else {
        result.add(grid.columns.firstWhere((c) => c.id == item.id));
      }
    }
  }

  walk(null);
  result.addAll(grid.columns.where((c) => !visited.contains(c.id)));
  return result;
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
          parentId: group.parentId == null ? null : groupIds[group.parentId],
          position: group.position,
        ),
    ],
    columns: [
      for (final column in source.columns)
        GraduationCreditColumn(
          id: columnIds[column.id]!,
          label: column.label,
          groupId: column.groupId == null ? null : groupIds[column.groupId],
          role: column.role,
          classificationNodeId: column.classificationNodeId,
          position: column.position,
          matchMode: column.matchMode,
          requirement: column.requirement,
          aggregateMembers: [
            for (final id in column.aggregateMembers)
              if (columnIds[id] != null) columnIds[id]!,
          ],
        ),
    ],
    rows: [
      for (final row in source.rows)
        GraduationCreditRow(
          id: rowIds[row.id]!,
          label: row.label,
          note: row.note,
          scope: row.scope == null
              ? null
              : Map<String, dynamic>.from(
                  jsonDecode(jsonEncode(row.scope)) as Map,
                ),
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
