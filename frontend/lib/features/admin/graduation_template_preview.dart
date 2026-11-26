import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/widgets/content_scroll_view.dart';
import 'admin_models.dart';
import 'graduation_certification.dart';
import 'graduation_credit_grid.dart';

Future<void> showGraduationTemplatePreview({
  required BuildContext context,
  required String title,
  required Widget child,
}) {
  final size = MediaQuery.sizeOf(context);
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      key: const ValueKey('template-preview-dialog'),
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: math.min(960, size.width - 48),
        height: math.min(640, size.height * 0.8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: ContentScrollView(child: child)),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const ValueKey('template-preview-close'),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('닫기'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class GraduationCreditGridPreview extends StatelessWidget {
  const GraduationCreditGridPreview({
    super.key,
    required this.grid,
    required this.schoolName,
    required this.departments,
  });

  final GraduationCreditGrid grid;
  final String schoolName;
  final List<AdminRecord> departments;

  String get _departmentName =>
      departments.where((d) => d.id == grid.departmentId).firstOrNull?.name ??
      '학과 미선택';

  String _cellText(GraduationCreditCell cell) => switch (cell.kind) {
    GraduationCreditCellKind.number =>
      (cell.value ?? '').trim().isEmpty ? '' : cell.value!.trim(),
    GraduationCreditCellKind.notApplicable => '-',
    GraduationCreditCellKind.empty => '',
  };

  @override
  Widget build(BuildContext context) {
    final year = grid.admissionYear.trim().isEmpty
        ? '입학연도 미입력'
        : '${grid.admissionYear}학년도 입학자';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$schoolName $_departmentName 졸업최소이수학점',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(year),
        const SizedBox(height: 12),
        if (grid.columns.isEmpty && grid.rows.isEmpty)
          const Text('미리볼 열과 행이 없습니다. 표에 열과 이수 경로를 추가하세요.')
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: TableBorder.all(
                color: Theme.of(context).colorScheme.outline,
              ),
              children: [
                TableRow(
                  children: [
                    _header('학과'),
                    _header('구분'),
                    for (final column in grid.columns)
                      _header(
                        grid.groups
                                .where((g) => g.id == column.groupId)
                                .firstOrNull
                                ?.label ??
                            '',
                      ),
                    _header(''),
                  ],
                ),
                TableRow(
                  children: [
                    _header(''),
                    _header(''),
                    for (final column in grid.columns) _header(column.label),
                    _header('비고'),
                  ],
                ),
                for (final row in grid.rows)
                  TableRow(
                    children: [
                      _cell(_departmentName),
                      _cell(row.label),
                      for (final column in grid.columns)
                        _cell(_cellText(grid.cellFor(row.id, column.id))),
                      _cell(row.note),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 72),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    ),
  );

  Widget _cell(String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 48),
      child: Text(text),
    ),
  );
}

class GraduationCertificationPreview extends StatelessWidget {
  const GraduationCertificationPreview({
    super.key,
    required this.draft,
    required this.schoolName,
    required this.departments,
    this.showContext = true,
  });

  final GraduationCertificationDraft draft;
  final String schoolName;
  final List<AdminRecord> departments;
  final bool showContext;

  String get _departmentName =>
      departments.where((d) => d.id == draft.departmentId).firstOrNull?.name ??
      '학과 미선택';

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          showContext ? '$schoolName $_departmentName 졸업자격요건' : '인증 요건',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (draft.groups.isEmpty)
          const Text('미리볼 묶음이 없습니다. 인증 요건에 묶음을 추가하세요.')
        else
          for (final group in draft.groups) _group(context, group, 0),
      ],
    );
  }

  Widget _group(
    BuildContext context,
    GraduationCertificationGroup group,
    int depth,
  ) {
    final choice = switch (group.choice) {
      GraduationCertificationChoice.all => '모두',
      GraduationCertificationChoice.pickOne => '택 1',
      GraduationCertificationChoice.pickN =>
        group.pickCount == null ? '택 미입력' : '택 ${group.pickCount}',
    };
    final title = group.label.trim().isEmpty ? '묶음' : group.label.trim();
    return Padding(
      padding: EdgeInsets.only(left: depth * 16, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$title ($choice)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          for (final item in group.items)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '· ${item.label.trim().isEmpty ? '기준 미입력' : item.label.trim()}'
                '${item.kind == GraduationCertificationKind.text ? '' : ' · ${certificationKindLabel(item.kind)}'}',
              ),
            ),
          if (group.exemptions.any((value) => value.trim().isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '면제: ${group.exemptions.where((value) => value.trim().isNotEmpty).join(', ')}',
              ),
            ),
          for (final child in group.groups) _group(context, child, depth + 1),
        ],
      ),
    );
  }
}
