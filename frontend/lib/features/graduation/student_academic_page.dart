import 'package:flutter/material.dart';

import '../../shared/widgets/feature_page.dart';
import '../../shared/widgets/surface_card.dart';
import '../admin/academic_credit_preview.dart';
import '../admin/academic_requirement_content.dart';
import '../admin/graduation_template_preview.dart';
import '../api/student_academic_api.dart';
import '../auth/guest_preview_scope.dart';
import '../planning/planning_repository.dart';
import 'student_academic_contexts.dart';
import 'student_academic_controller.dart';
import 'student_academic_record_search.dart';
import 'student_academic_history.dart';

class StudentAcademicPage extends StatefulWidget {
  const StudentAcademicPage({
    super.key,
    required this.api,
    required this.profile,
    this.onLegacy,
    this.onPersonal,
    this.onOpenSettings,
    this.recordSearch,
  });
  final StudentAcademicApi api;
  final PlanningProfile profile;
  final AcademicRecordSearchRepository? recordSearch;
  final VoidCallback? onLegacy, onPersonal, onOpenSettings;
  @override
  State<StudentAcademicPage> createState() => _StudentAcademicPageState();
}

class _StudentAcademicPageState extends State<StudentAcademicPage> {
  late StudentAcademicController c;
  late AcademicRecordSearchRepository _recordSearch;
  String _tab = 'checklist';
  String? _responseItem;
  bool get _guest => GuestPreviewScope.isActive(context);
  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    _recordSearch =
        widget.recordSearch ?? AcademicRecordSearchRepository(widget.api);
    c = StudentAcademicController(widget.api)..addListener(_changed);
    c.load();
  }

  @override
  void didUpdateWidget(covariant StudentAcademicPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api.ownerId != widget.api.ownerId) {
      c.dispose();
      _init();
    } else if (oldWidget.profile.version != widget.profile.version &&
        !c.uncertain &&
        !c.saving) {
      c.load();
    }
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<void> _contexts() async {
    await editStudentAcademicContexts(context, widget.api, widget.profile);
    if (mounted) await c.load();
  }

  Future<void> _activate() async {
    final p = c.preview;
    if (p == null || p.issues.isNotEmpty) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('확인한 기준으로 적용할까요?'),
        content: Text(
          '${p.documents.length}개 요건을 적용합니다. 변경된 문장·범위·기준은 다시 확인하며 이전 기록은 보존됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('적용'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) await c.activate();
  }

  Widget _item(AcademicStudentDocument d, AcademicStudentItem item) {
    final response = d.response(item.id);
    final blocked =
        c.disabled ||
        _guest ||
        !d.usable ||
        c.requirements!.issues.any(
          (issue) =>
              issue != 'requirement_withdrawn' &&
              issue != 'requirement_expired',
        );
    Future<void> respond(bool? value) async {
      setState(() => _responseItem = '${d.id}/${item.id}');
      await c.respond(d, item.id, value, []);
    }

    final active = _responseItem == '${d.id}/${item.id}';
    return Padding(
      key: ValueKey('academic-item-${item.id}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(item.text),
          if (d.nodeContexts[item.id] case final ids?)
            Text('적용: ${_contextLabels(ids)}'),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (response?.value == null) const Text('미확인'),
              if (response?.stale == true) const Text('재확인 필요'),
              if (response?.previousValue != null)
                Text('이전 확인: ${response!.previousValue! ? 'O' : 'X'}'),
              for (final value in const [true, false])
                ChoiceChip(
                  key: ValueKey('academic-response-${item.id}-$value'),
                  label: Text(value ? 'O · 충족' : 'X · 미충족'),
                  selected: response?.value == value,
                  onSelected: blocked ? null : (_) => respond(value),
                ),
              TextButton(
                onPressed:
                    blocked ||
                        (response?.value == null && response?.stale != true)
                    ? null
                    : () => respond(null),
                child: const Text('초기화'),
              ),
            ],
          ),
          if (active && c.saving) const Text('저장 중…'),
          if (active && c.error != null)
            Text(
              c.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (!_guest)
            StudentAcademicRecordSearch(
              key: ValueKey(
                'academic-search-${widget.api.ownerId}-${d.id}-${item.id}',
              ),
              repository: _recordSearch,
            ),
        ],
      ),
    );
  }

  Widget _group(
    AcademicStudentDocument d,
    AcademicStudentGroup group,
    int depth,
  ) => Padding(
    padding: EdgeInsets.only(left: depth == 0 ? 0 : 16, top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${group.label} · ${group.choiceLabel} · ${academicStatus(d.groupResults[group.id] ?? 'needs_review')}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        ...group.items.map((i) => _item(d, i)),
        ...group.groups.map((g) => _group(d, g, depth + 1)),
        for (final text in group.exemptions) Text('면제 안내: $text'),
      ],
    ),
  );
  Widget _credit(AcademicStudentDocument d) {
    String number(String value) => value.contains('.')
        ? value
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '')
        : value;
    final grid = creditGridFromAcademic(d.content),
        cells = c.progress?.tables[d.id] ?? [];
    final displayRows = <AcademicCreditDisplayRow>[];
    for (final row in grid.rows) {
      final rowCells = {
        for (final cell in cells.where((v) => v.rowId == row.id))
          cell.headerId: cell,
      };
      if (rowCells.isEmpty) continue;
      for (final metric in const [
        '기준학점',
        '취득학점',
        '수강 중 학점',
        '취득 + 수강 중',
        '부족학점',
      ]) {
        displayRows.add(
          AcademicCreditDisplayRow(
            label: '${row.label}\n$metric',
            emphasized: metric == '취득학점' || metric == '부족학점',
            note: metric == '기준학점' ? row.note : '',
            values: {
              for (final col in grid.columns)
                col.id: () {
                  final cell = rowCells[col.id];
                  if (cell == null) return '—';
                  if (cell.status == 'not_applicable') return '해당 없음';
                  final value = switch (metric) {
                    '기준학점' => cell.target,
                    '취득학점' => cell.earned,
                    '수강 중 학점' => cell.inProgress,
                    '취득 + 수강 중' => cell.earnedWithInProgress,
                    _ => cell.remaining,
                  };
                  if (value == null) {
                    return metric == '기준학점' ||
                            (metric == '부족학점' && cell.target == null)
                        ? '—'
                        : '확인 필요';
                  }
                  return '${number(value)}${metric != '기준학점' && cell.status == 'needs_review' ? '*' : ''}';
                }(),
            },
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AcademicCreditPreview(
          grid: grid,
          displayRows: cells.isEmpty ? null : displayRows,
        ),
        const SizedBox(height: 8),
        const Text('단위: 학점 · 부족학점은 현재 취득학점 기준'),
        if (cells.any((cell) => cell.status == 'needs_review'))
          const Text('확인 필요: 분류나 산입 자료가 부족합니다. *는 확인된 학점만 표시한 값입니다.'),
        if (cells.isEmpty) const Text('학점 집계 결과를 불러오지 못했습니다. 다시 불러오기를 눌러주세요.'),
        ExpansionTile(
          title: const Text('산입 내역'),
          children: [
            for (final cell in cells)
              ExpansionTile(
                title: Text(
                  '${grid.rows.where((r) => r.id == cell.rowId).firstOrNull?.label ?? ''} / ${grid.columns.where((v) => v.id == cell.headerId).firstOrNull?.label ?? ''} · ${academicStatus(cell.status)}',
                ),
                subtitle: const Text('산입·제외·확인 필요 과목'),
                children: [
                  for (final issue in cell.issues)
                    Text(academicEvidenceReason(issue)),
                  if (cell.evidence.isEmpty && cell.issues.isEmpty)
                    const Text('산입할 수강 기록이 없습니다.'),
                  for (final e in cell.evidence)
                    ListTile(
                      dense: true,
                      title: Text(e.title),
                      subtitle: Text(
                        '${academicStatus(e.state)} · ${academicEvidenceReason(e.reason)}${e.credits == null ? '' : ' · ${e.state == 'included' ? '산입' : '참고·미산입'} ${e.credits}학점'}',
                      ),
                    ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  String _contextLabels(List<String> ids) =>
      (c.workspace?.contexts
                  .where((v) => ids.contains(v.id))
                  .map((v) => v.label) ??
              [])
          .join(' / ');
  Widget _previewDocument(AcademicStudentDocument d) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${d.name} · ${d.revision}판',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text('적용: ${_contextLabels(d.contextIds)}'),
        if (d.effectiveFrom != null || d.effectiveTo != null)
          Text(
            '적용 기간: ${d.effectiveFrom ?? "제한 없음"} ~ ${d.effectiveTo ?? "제한 없음"}',
          ),
        if (d.kind == 'checklist')
          ...d.lines.map(
            (line) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '${line.text}\n적용: ${_contextLabels(d.nodeContexts[line.id] ?? d.contextIds)}',
              ),
            ),
          ),
        if (d.kind == 'certification')
          GraduationCertificationPreview(
            draft: certificationFromAcademic(d.content),
            schoolName: widget.profile.school,
            departments: const [],
            showContext: false,
          ),
        if (d.kind == 'credit_table')
          AcademicCreditPreview(grid: creditGridFromAcademic(d.content)),
        for (final table in d.tables) ...[
          Text(table.title),
          for (final row in table.rows)
            Text(
              [
                for (var i = 0; i < row.length; i++)
                  '${table.columns[i]}: ${row[i]}',
              ].join(' · '),
            ),
        ],
      ],
    ),
  );
  Widget _document(AcademicStudentDocument d) => SurfaceCard(
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${d.name} · ${d.revision}판${d.status == 'withdrawn' ? ' · 철회됨' : ''}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            (c.workspace?.contexts
                        .where((v) => d.contextIds.contains(v.id))
                        .map((v) => v.label) ??
                    [])
                .join(' / '),
          ),
          if (d.kind == 'checklist') ...d.lines.map((line) => _item(d, line)),
          if (d.kind == 'certification') ...[
            ...d.groups.map((group) => _group(d, group, 0)),
            for (final table in d.tables)
              ExpansionTile(
                title: Text(table.title),
                children: [
                  for (final row in table.rows)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        [
                          for (var index = 0; index < row.length; index++)
                            '${table.columns[index]}: ${row[index]}',
                        ].join(' · '),
                      ),
                    ),
                ],
              ),
          ],
          if (d.kind == 'credit_table') _credit(d),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final requirements = c.requirements, preview = c.preview;
    final docs =
        requirements?.documents.where((d) => d.kind == _tab).toList() ?? [];
    return FeaturePage(
      title: '졸업 요건',
      description: '내 학업 기준의 요건과 진행 상황을 확인합니다.',
      body: [
        Wrap(
          spacing: 8,
          children: [
            if (widget.onLegacy != null)
              OutlinedButton(
                onPressed: c.saving || c.uncertain ? null : widget.onLegacy,
                child: const Text('기존 졸업 감사·이력'),
              ),
            if (widget.onPersonal != null)
              OutlinedButton(
                onPressed: c.saving || c.uncertain ? null : widget.onPersonal,
                child: const Text('개인 기준 계산·이력'),
              ),
            OutlinedButton(
              onPressed: c.disabled
                  ? null
                  : () => showStudentAcademicHistory(context, widget.api),
              child: const Text('적용 기준·내 확인 이력'),
            ),
          ],
        ),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.profile.school,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (c.workspace != null)
                ...c.workspace!.contexts.map(
                  (v) => Text(
                    '${v.primary ? '주전공' : '추가 전공'} · ${v.label} · ${v.curriculum}',
                  ),
                ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: c.disabled || _guest ? null : _contexts,
                    child: const Text('학업 기준 설정'),
                  ),
                  TextButton(
                    onPressed: c.saving || c.uncertain ? null : c.load,
                    child: const Text('다시 불러오기'),
                  ),
                ],
              ),
              if (c.loading || c.saving) const LinearProgressIndicator(),
              if (c.error != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    c.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (c.message != null) Text(c.message!),
              if (c.uncertain)
                OutlinedButton(
                  onPressed: c.saving ? null : c.retry,
                  child: const Text('같은 요청으로 다시 저장'),
                ),
              for (final issue in {
                ...?requirements?.issues,
                ...?preview?.issues,
              })
                Text(academicIssue(issue)),
              if (widget.onOpenSettings != null &&
                  ((requirements?.issues.contains('profile_incomplete') ??
                          false) ||
                      widget.profile.departmentId == null ||
                      widget.profile.admissionYear == null))
                TextButton(
                  onPressed: widget.onOpenSettings,
                  child: const Text('프로필 설정으로'),
                ),
            ],
          ),
        ),
        if (c.loaded && preview != null)
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  requirements?.activationId == null ? '적용 기준 확인' : '기준 변경 확인',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (preview.changes.isEmpty)
                  Text(
                    requirements?.activationId == null
                        ? '내 대상에 맞는 게시 요건 ${preview.documents.length}개'
                        : '새로 적용할 요건 변경이 없습니다.',
                  ),
                for (final change in preview.changes)
                  Text(
                    '${const {'added': '추가', 'removed': '제외', 'changed': '변경'}[change.kind]} · ${change.name} · ${change.detail}',
                  ),
                for (final update in preview.curriculumUpdates) Text(update),
                if (preview.documents.isNotEmpty)
                  Material(
                    type: MaterialType.transparency,
                    child: ExpansionTile(
                      title: const Text('새 기준 본문·적용 대상 보기'),
                      children: preview.documents
                          .map(_previewDocument)
                          .toList(),
                    ),
                  ),
                if (preview.documents.isEmpty && preview.issues.isEmpty)
                  const Text('현재 대상에 게시된 요건이 없습니다.'),
                if ((requirements?.activationId == null ||
                        preview.changes.isNotEmpty ||
                        requirements!.issues.isNotEmpty) &&
                    (preview.documents.isNotEmpty ||
                        requirements?.activationId != null))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      onPressed:
                          c.disabled || _guest || preview.issues.isNotEmpty
                          ? null
                          : _activate,
                      child: const Text('확인한 기준 적용'),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in const {
              'checklist': '한 줄 요건',
              'credit_table': '학점표',
              'certification': '인증 요건',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _tab == entry.key,
                onSelected: c.saving
                    ? null
                    : (_) => setState(() => _tab = entry.key),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (c.loaded && requirements?.activationId == null)
          const Text('위에서 적용할 기준을 확인하세요.')
        else if (c.loaded && docs.isEmpty)
          const Text('현재 적용 기준에는 이 종류의 요건이 없습니다.'),
        for (final d in docs)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _document(d),
          ),
      ],
    );
  }
}
