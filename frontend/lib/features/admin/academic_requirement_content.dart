import 'graduation_certification.dart';
import 'graduation_credit_grid.dart';

/// Maps the validated academic API payload to the existing feature editor models.
GraduationCreditGrid creditGridFromAcademic(Map<String, dynamic> content) {
  final grid = GraduationCreditGrid(admissionYear: '', departmentId: '');
  for (final raw in content['headers'] as List) {
    final h = Map<String, dynamic>.from(raw as Map);
    if (h['role'] == 'group') {
      grid.groups.add(
        GraduationCreditColumnGroup(
          id: h['id'] as String,
          label: h['label'] as String,
          parentId: h['parent_id'] as String?,
          position: h['position'] as int,
        ),
      );
    } else {
      grid.columns.add(
        GraduationCreditColumn(
          id: h['id'] as String,
          label: h['label'] as String,
          groupId: h['parent_id'] as String?,
          position: h['position'] as int,
          role: h['role'] as String,
          classificationNodeId: h['classification_node_id'] as String?,
          requirement: h['requirement'] as String?,
          matchMode: h['match_mode'] as String? ?? 'subtree',
          aggregateMembers: List<String>.from(
            h['aggregate_members'] as List? ?? [],
          ),
        ),
      );
    }
  }
  for (final raw in content['rows'] as List) {
    final row = Map<String, dynamic>.from(raw as Map);
    grid.rows.add(
      GraduationCreditRow(
        id: row['id'] as String,
        label: row['label'] as String,
        note: row['note'] as String? ?? '',
        scope: row['scope'] == null
            ? null
            : Map<String, dynamic>.from(row['scope'] as Map),
      ),
    );
  }
  for (final raw in content['cells'] as List) {
    final cell = Map<String, dynamic>.from(raw as Map);
    final value = grid.cellFor(
      cell['row_id'] as String,
      cell['header_id'] as String,
    );
    value.kind = switch (cell['state']) {
      'number' => GraduationCreditCellKind.number,
      'not_applicable' => GraduationCreditCellKind.notApplicable,
      _ => GraduationCreditCellKind.empty,
    };
    value.value = cell['value']?.toString();
  }
  return grid;
}

Map<String, Object?> creditGridToAcademic(GraduationCreditGrid grid) {
  final cells = <Map<String, Object?>>[];
  for (final row in grid.rows) {
    for (final col in grid.columns) {
      final cell = grid.cellFor(row.id, col.id);
      if (cell.kind == GraduationCreditCellKind.number &&
          parseCreditNumber(cell.value ?? '') == null) {
        throw FormatException('${row.label} / ${col.label}의 학점을 확인하세요.');
      }
      cells.add({
        'row_id': row.id,
        'header_id': col.id,
        'state': switch (cell.kind) {
          GraduationCreditCellKind.empty => 'empty',
          GraduationCreditCellKind.number => 'number',
          GraduationCreditCellKind.notApplicable => 'not_applicable',
        },
        'value': cell.kind == GraduationCreditCellKind.number
            ? cell.value
            : null,
      });
    }
  }
  return {
    'kind': 'credit_table',
    'headers': [
      for (final group in grid.groups)
        {
          'id': group.id,
          'parent_id': group.parentId,
          'label': group.label,
          'position': group.position,
          'role': 'group',
        },
      for (final col in grid.columns)
        {
          'id': col.id,
          'parent_id': col.groupId,
          'label': col.label,
          'position': col.position,
          'role': col.role,
          'classification_node_id': col.classificationNodeId,
          'requirement': col.requirement,
          'match_mode': col.matchMode,
          'aggregate_members': col.aggregateMembers,
        },
    ],
    'rows': [
      for (final row in grid.rows)
        {
          'id': row.id,
          'label': row.label,
          'note': row.note,
          'scope': row.scope,
        },
    ],
    'cells': cells,
  };
}

GraduationCertificationDraft certificationFromAcademic(
  Map<String, dynamic> content,
) {
  GraduationCertificationGroup group(Map<String, dynamic> value) =>
      GraduationCertificationGroup(
        id: value['id'] as String,
        label: value['label'] as String,
        choice: GraduationCertificationChoice.values.firstWhere(
          (c) => c.name == value['choice'],
        ),
        pickCount: value['pick_count'] as int?,
        scope: value['scope'] == null
            ? null
            : Map<String, dynamic>.from(value['scope'] as Map),
        exemptions: List<String>.from(value['exemptions'] as List? ?? []),
        items: [
          for (final raw in value['items'] as List)
            GraduationCertificationItem(
              id: raw['id'] as String,
              label: raw['label'] as String,
              kind: GraduationCertificationKind.values.firstWhere(
                (k) => k.name == raw['kind'],
              ),
              scope: raw['scope'] == null
                  ? null
                  : Map<String, dynamic>.from(raw['scope'] as Map),
            ),
        ],
        groups: [
          for (final raw in value['groups'] as List)
            group(Map<String, dynamic>.from(raw as Map)),
        ],
      );
  return GraduationCertificationDraft(
    departmentId: '',
    groups: [
      for (final raw in content['groups'] as List)
        group(Map<String, dynamic>.from(raw as Map)),
    ],
  );
}

Map<String, Object?> certificationToAcademic(
  GraduationCertificationDraft draft, {
  List<Map<String, dynamic>> tables = const [],
}) {
  Map<String, Object?> group(GraduationCertificationGroup value) => {
    'id': value.id,
    'label': value.label,
    'choice': value.choice.name,
    'pick_count': value.pickCount,
    'scope': value.scope,
    'exemptions': value.exemptions,
    'items': [
      for (final item in value.items)
        {
          'id': item.id,
          'label': item.label,
          'kind': item.kind.name,
          'scope': item.scope,
        },
    ],
    'groups': [for (final child in value.groups) group(child)],
  };
  return {
    'kind': 'certification',
    'groups': [for (final root in draft.groups) group(root)],
    'tables': tables,
  };
}
