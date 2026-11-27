import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../shared/app_style.dart';
import '../../../shared/widgets/feature_line.dart';
import '../../../shared/widgets/feature_page.dart';
import '../../../shared/widgets/guide_card.dart';
import '../../../shared/widgets/page_actions.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../../shared/app_tones.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/record_tile.dart';
import '../../../shared/widgets/responsive_grid.dart';
import '../../../shared/widgets/tone_chip.dart';
import '../../../shared/widgets/work_layout.dart';
import '../../auth/auth_api.dart';
import '../../auth/guest_preview_scope.dart';
import 'material_form_dialog.dart';
import 'material_preview.dart';
import 'material_repository.dart';

class MaterialsPage extends StatefulWidget {
  const MaterialsPage({
    super.key,
    this.repository,
    this.pickPdf,
    this.exportPdf,
    this.onChanged,
  });
  final MaterialRepository? repository;
  final Future<XFile?> Function()? pickPdf;
  final Future<void> Function(PersonalMaterial, Uint8List)? exportPdf;
  final VoidCallback? onChanged;
  @override
  State<MaterialsPage> createState() => MaterialsPageState();
}

class MaterialsPageState extends State<MaterialsPage> {
  late final MaterialRepository _repo =
      widget.repository ?? DeviceMaterialRepository();
  final _query = TextEditingController();
  List<PersonalMaterial> _records = [];
  bool _loading = true, _failed = false, _busy = false, _formOpen = false;

  /// Input lives in the 자료 추가·수정 dialog, which asks before discarding it.
  Future<bool> allowLeave() async => !_busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final records = await _repo.load();
      if (mounted) _records = records;
    } catch (_) {
      if (mounted) _failed = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  bool _blocked() {
    if (!GuestPreviewScope.isActive(context)) return false;
    GuestPreviewScope.showBlockedMessage(context);
    return true;
  }

  void _notify(String message) =>
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(message)));

  /// Reads the list again after a change; a failed read must not pretend that
  /// the change itself failed.
  Future<void> _refresh() async {
    widget.onChanged?.call();
    try {
      _records = await _repo.load();
    } catch (_) {
      if (mounted) _failed = true;
    }
    if (mounted) setState(() {});
  }

  Future<void> _openForm([PersonalMaterial? material]) async {
    if (_busy || _formOpen || _blocked()) return;
    _formOpen = true;
    final bool saved;
    try {
      saved = await showMaterialForm(
        context: context,
        repository: _repo,
        material: material,
        pickPdf: widget.pickPdf,
        blocked: _blocked,
        onViewSaved: _repo.canPreview ? _view : null,
      );
    } finally {
      _formOpen = false;
    }
    if (saved && mounted) await _refresh();
  }

  Future<void> _delete(PersonalMaterial record) async {
    if (_busy || _blocked()) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${record.title} 삭제'),
        content: Text(
          '${_repo.inAccount ? '계정에' : '이 기기에'} 보관한 설명과 PDF를 삭제합니다. '
          '원래 선택한 파일과 기록·자기소개서·포트폴리오는 삭제하지 않습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: destructiveButtonStyle(context),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _repo.delete(record);
      if (mounted) await _refresh();
    } catch (_) {
      if (mounted) _notify('삭제하지 못했습니다. 자료를 유지했습니다. 다시 시도하세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<PersonalMaterial> get _filtered {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) return _records;
    return _records
        .where(
          (r) => '${r.title} ${r.type} ${r.description}'.toLowerCase().contains(
            query,
          ),
        )
        .toList();
  }

  Future<void> _export(PersonalMaterial r) async {
    setState(() => _busy = true);
    try {
      final bytes = await _repo.pdf(r);
      if (bytes == null) return;
      await (widget.exportPdf ?? exportMaterialPdf)(r, bytes);
    } catch (e) {
      if (mounted) {
        _notify(
          e is AuthFailure ? e.message : 'PDF를 내보내지 못했습니다. 보관 자료는 유지했습니다.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _canView(PersonalMaterial r) => r.hasPdf && _repo.canPreview;

  Future<void> _view(PersonalMaterial r) => showMaterialPreview(
    context,
    repository: _repo,
    material: r,
    onExport: () {
      if (!_busy) _export(r);
    },
  );

  void _edit(PersonalMaterial r) => _openForm(r);

  Widget _materialTile(PersonalMaterial r) {
    final pdf = r.hasPdf;
    final tone = pdf ? AppTone.danger : AppTone.accent;
    return RecordTile(
      key: ValueKey('material-row-${r.id}'),
      icon: pdf ? Icons.picture_as_pdf_outlined : Icons.sticky_note_2_outlined,
      tone: tone,
      title: r.title,
      badges: [if (r.type.isNotEmpty) ToneChip(label: r.type, tone: tone)],
      facts: [
        if (pdf)
          RecordFact(
            Icons.attach_file,
            '${r.fileName} · ${(r.byteCount / 1024).ceil()}KB',
          )
        else
          const RecordFact(Icons.edit_note, '내용 설명 기록'),
        if (!_repo.inAccount)
          const RecordFact(Icons.smartphone_outlined, '이 기기에 보관'),
      ],
      lines: [if (r.description.isNotEmpty) r.description],
      onTap: _busy ? null : () => _edit(r),
      footer: [
        if (_canView(r))
          TextButton.icon(
            key: ValueKey('material-view-${r.id}'),
            onPressed: () => _view(r),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('PDF 보기'),
          ),
      ],
      actions: [
        if (_canView(r))
          RecordAction('PDF 보기', Icons.visibility_outlined, () => _view(r)),
        RecordAction('수정', Icons.edit_outlined, () => _edit(r)),
        if (pdf)
          RecordAction('PDF 내보내기', Icons.download_outlined, () {
            if (!_busy) _export(r);
          }),
        RecordAction(
          '삭제',
          Icons.delete_outline,
          () => _delete(r),
          destructive: true,
        ),
      ],
    );
  }

  Widget _list(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _filtered;
    final search = SizedBox(
      width: 320,
      child: TextFormField(
        key: const ValueKey('material-search'),
        controller: _query,
        enabled: !_busy,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: '제목·종류·설명 검색',
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('자료 목록', style: theme.textTheme.titleMedium),
                  const SizedBox(width: 8),
                  ToneChip(label: '${_records.length}개'),
                ],
              ),
              if (_records.isNotEmpty) search,
            ],
          ),
          if (_records.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${rows.length}개 표시 / ${_records.length}개',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (_repo case AccountMaterialRepository(:final unmovedCount)
              when unmovedCount > 0) ...[
            const SizedBox(height: 8),
            NoteLine(
              key: const ValueKey('materials-unmoved'),
              icon: Icons.warning_amber_outlined,
              text: '이 기기에 남은 자료 $unmovedCount개를 계정으로 옮기지 못했습니다.',
              detail:
                  '8MB를 넘는 PDF이거나 계정 보관 한도(50MB)를 넘었을 수 있습니다. '
                  '다음에 로그인하면 다시 옮깁니다.',
            ),
          ],
          const SizedBox(height: 12),
          if (_records.isEmpty)
            EmptyState(
              icon: Icons.folder_open_outlined,
              title: '등록한 자료가 없습니다',
              message: '설명만 기록하거나 PDF를 선택해 등록하세요.',
              action: OutlinedButton.icon(
                onPressed: _busy ? null : () => _openForm(),
                icon: const Icon(Icons.add),
                label: const Text('첫 자료 추가'),
              ),
            )
          else if (rows.isEmpty)
            const EmptyState(
              icon: Icons.search_off,
              title: '검색에 맞는 자료가 없습니다',
              message: '검색어를 바꿔 보세요.',
            )
          else
            ResponsiveGrid(
              key: const ValueKey('material-catalog'),
              children: [for (final r in rows) _materialTile(r)],
            ),
        ],
      ),
    );
  }

  /// Same header in loading, failure and loaded states so the title never
  /// shifts; the actions wait for the list.
  List<Widget> _headerActions() {
    final ready = !_loading && !_failed && !_busy;
    return [
      if (_repo.inAccount)
        PageMoreMenu(
          key: const Key('materials-more'),
          enabled: ready,
          itemBuilder: (context) => [
            PopupMenuItem<void>(
              onTap: _load,
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.refresh),
                title: Text('다시 읽기'),
              ),
            ),
          ],
        ),
      PageAddButton(
        label: '자료 추가',
        onPressed: ready ? () => _openForm() : null,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '내 자료',
    trailing: _headerActions(),
    body: [
      if (_loading)
        const LinearProgressIndicator()
      else if (_failed) ...[
        const FeatureLine.one(text: '자료 목록을 읽지 못했습니다. 저장된 자료를 덮어쓰지 않습니다.'),
        FeatureLine.reload(onPressed: _busy ? null : _load),
      ] else
        _list(context),
    ],
    below: [
      if (!_loading && !_failed)
        const GuideCard(
          title: '자료 준비',
          lines: [
            '파일 없이 담긴 내용 설명만 기록해도 됩니다',
            'PDF는 한 개 8MB, 전체 50MB까지 보관합니다',
            '채용공고 분석·자기소개서·포트폴리오 작성에서 함께 고릅니다',
          ],
        ),
    ],
  );
}
