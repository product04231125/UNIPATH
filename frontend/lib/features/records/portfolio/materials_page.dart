import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../shared/app_style.dart';
import '../../../shared/app_typography.dart';
import '../../../shared/widgets/feature_actions.dart';
import '../../../shared/widgets/feature_line.dart';
import '../../../shared/widgets/anchored_select_field.dart';
import '../../../shared/widgets/feature_page.dart';
import '../../../shared/widgets/field_label.dart';
import '../../../shared/widgets/field_requirement.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../../shared/widgets/input_dialog.dart';
import '../../../shared/widgets/responsive_columns.dart';
import '../../auth/guest_preview_scope.dart';
import 'material_repository.dart';

class MaterialsPage extends StatefulWidget {
  const MaterialsPage({
    super.key,
    this.repository,
    this.pickPdf,
    this.exportPdf,
  });
  final MaterialRepository? repository;
  final Future<XFile?> Function()? pickPdf;
  final Future<void> Function(PersonalMaterial)? exportPdf;
  @override
  State<MaterialsPage> createState() => MaterialsPageState();
}

class MaterialsPageState extends State<MaterialsPage> {
  late final _repo = widget.repository ?? MaterialRepository();
  final _title = TextEditingController(),
      _type = TextEditingController(),
      _description = TextEditingController(),
      _query = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _listScroll = ScrollController();
  List<PersonalMaterial> _records = [];
  PersonalMaterial? _editing;
  Uint8List? _pdf;
  String _fileName = '';
  bool _loading = true, _failed = false, _busy = false;
  String? _error, _message;
  bool get dirty =>
      _title.text != (_editing?.title ?? '') ||
      _type.text != (_editing?.type ?? '') ||
      _description.text != (_editing?.description ?? '') ||
      _fileName != (_editing?.fileName ?? '') ||
      !identical(_pdf, _editing?.pdf);
  Future<bool> allowLeave() async =>
      !_busy && (!dirty || await confirmInputDiscard(context));
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _type.dispose();
    _description.dispose();
    _query.dispose();
    _listScroll.dispose();
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

  void _reset([PersonalMaterial? record]) {
    _form.currentState?.reset();
    _editing = record;
    _title.text = record?.title ?? '';
    _type.text = record?.type ?? '';
    _description.text = record?.description ?? '';
    _fileName = record?.fileName ?? '';
    _pdf = record?.pdf;
    setState(() {
      _error = null;
      _message = null;
    });
  }

  Future<void> _pick() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await (widget.pickPdf ?? pickMaterialPdf)();
      if (file == null) return;
      if (await file.length() > MaterialRepository.maxPdfBytes) {
        throw StateError('PDF는 10MB 이하로 선택하세요.');
      }
      final bytes = await file.readAsBytes();
      MaterialRepository.validatePdf(file.name, bytes);
      if (!mounted) return;
      setState(() {
        _pdf = bytes;
        _fileName = file.name;
        if (_title.text.trim().isEmpty) _title.text = file.name;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is StateError
              ? e.message
              : '파일을 읽지 못했습니다. 이전 입력은 유지했습니다. 다시 선택하세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (GuestPreviewScope.isActive(context)) {
      GuestPreviewScope.showBlockedMessage(context);
      return;
    }
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await _repo.save(
        PersonalMaterial(
          id: _editing?.id ?? MaterialRepository.newId(),
          title: _title.text.trim(),
          type: _type.text.trim(),
          description: _description.text.trim(),
          fileName: _fileName,
          pdf: _pdf,
        ),
      );
      if (!mounted) return;
      _reset();
      // A refresh failure must not pretend that a successful save failed.
      try {
        _records = await _repo.load();
      } catch (_) {
        if (mounted) _failed = true;
      }
      if (mounted) setState(() => _message = '자료를 기기에 보관했습니다.');
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is StateError
              ? e.message
              : '자료를 저장하지 못했습니다. 입력과 PDF를 유지했습니다. 다시 시도하세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(PersonalMaterial record) async {
    if (GuestPreviewScope.isActive(context)) {
      GuestPreviewScope.showBlockedMessage(context);
      return;
    }
    if (_busy || !await allowLeave() || !mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${record.title} 삭제'),
        content: const Text(
          '이 기기에 보관한 설명과 PDF를 삭제합니다. 원래 선택한 파일과 기존 성과·지원 문서는 삭제하지 않습니다.',
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
      await _repo.delete(record.id);
      if (!mounted) return;
      _reset();
      try {
        _records = await _repo.load();
      } catch (_) {
        if (mounted) _failed = true;
      }
    } catch (_) {
      if (mounted) setState(() => _error = '삭제하지 못했습니다. 자료를 유지했습니다. 다시 시도하세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _rowHeight = 64.0;
  static const _actionHeight = 36.0;

  double get _rowExtent {
    final scaled = MediaQuery.textScalerOf(context).scale(_rowHeight);
    return scaled < _rowHeight ? _rowHeight : scaled;
  }

  static const _visibleRows = 3;

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

  Widget _cappedList() {
    final rows = _filtered;
    final visible = rows.length < _visibleRows ? rows.length : _visibleRows;
    final overflowing = rows.length > _visibleRows;
    final extent = _rowExtent;
    return SizedBox(
      key: const ValueKey('material-catalog'),
      height: extent * visible,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: Scrollbar(
          controller: _listScroll,
          thumbVisibility: overflowing,
          interactive: true,
          child: ListView.builder(
            controller: _listScroll,
            padding: overflowing
                ? const EdgeInsetsDirectional.only(end: 16)
                : EdgeInsets.zero,
            primary: false,
            itemCount: rows.length,
            itemExtent: extent,
            itemBuilder: (context, index) => _materialRow(rows[index]),
          ),
        ),
      ),
    );
  }

  ButtonStyle _rowActionStyle({bool danger = false}) {
    final base = danger
        ? destructiveButtonStyle(context)
        : OutlinedButton.styleFrom();
    return base.copyWith(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const WidgetStatePropertyAll(Size(0, _actionHeight)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      ),
    );
  }

  Widget _materialRow(PersonalMaterial r) {
    final subtitle = [
      if (r.description.isNotEmpty) r.description,
      if (r.pdf != null)
        '${r.fileName} · ${(r.pdf!.length / 1024).ceil()}KB · 기기 보관'
      else
        '내용 설명 기록',
    ].join(' · ');
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: ValueKey('material-row-${r.id}'),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    r.type.isEmpty ? r.title : '${r.type} · ${r.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  style: _rowActionStyle(),
                  onPressed: _busy
                      ? null
                      : () async {
                          if (await allowLeave() && mounted) _reset(r);
                        },
                  child: const Text('수정'),
                ),
                if (r.pdf != null)
                  OutlinedButton.icon(
                    style: _rowActionStyle(),
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            try {
                              await (widget.exportPdf ?? exportMaterialPdf)(r);
                            } catch (_) {
                              if (mounted) {
                                setState(
                                  () => _error =
                                      'PDF를 내보내지 못했습니다. 보관 자료는 유지했습니다.',
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('PDF 내보내기'),
                  ),
                FilledButton(
                  style: _rowActionStyle(danger: true),
                  onPressed: _busy ? null : () => _delete(r),
                  child: const Text('삭제'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String key,
    String label,
    TextEditingController controller, {
    int lines = 1,
    bool required = false,
  }) {
    final display = fieldRequirementLabel(label, required: required);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: FieldLabel(
        label: display,
        child: Semantics(
          label: display,
          child: TextFormField(
            key: ValueKey('material-$key'),
            controller: controller,
            enabled: !_busy,
            maxLines: lines,
            validator: (value) => required && (value?.trim().isEmpty ?? true)
                ? '$label 입력이 필요합니다.'
                : null,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '내 자료',
    description: 'PDF와 설명을 이 기기에 보관합니다.',
    body: [
      if (_loading)
        const LinearProgressIndicator()
      else if (_failed) ...[
        const FeatureLine.one(text: '자료 목록을 읽지 못했습니다. 저장된 자료를 덮어쓰지 않습니다.'),
        FeatureLine.reload(onPressed: _busy ? null : _load),
      ] else
        ResponsiveColumns(
          enabled: true,
          stretch: true,
          first: SurfaceCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      '자료 목록',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.merge(AppTypography.sectionStyle),
                    ),
                    const SizedBox(width: 8),
                    Text('${_records.length}개'),
                  ],
                ),
                SizedBox(height: FeatureLine.slotGap(context)),
                FieldLabel(
                  label: '제목·종류·설명 검색',
                  child: TextFormField(
                    key: const ValueKey('material-search'),
                    controller: _query,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('${_filtered.length}개 표시 / ${_records.length}개'),
                ),
                if (_records.isEmpty)
                  const FeatureLine.one(
                    text: '등록한 자료가 없습니다. 설명만 기록하거나 PDF를 선택해 등록하세요.',
                  )
                else if (_filtered.isEmpty)
                  const FeatureLine.one(text: '검색에 맞는 자료가 없습니다. 검색어를 바꿔보세요.')
                else
                  _cappedList(),
              ],
            ),
          ),
          second: SurfaceCard(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FeatureLine.section(
                    text: _editing == null ? '자료 등록' : '자료 수정',
                    padTop: false,
                  ),
                  _field('title', '자료 이름', _title, required: true),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: FormField<String>(
                      key: ValueKey(
                        'material-type-state-${_editing?.id ?? 'new'}',
                      ),
                      initialValue: _type.text,
                      validator: (_) => MaterialKinds.isAllowed(_type.text)
                          ? null
                          : '자료 종류를 선택하세요.',
                      builder: (state) => FieldLabel(
                        label: fieldRequirementLabel('자료 종류', required: true),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AnchoredSelectField<String>(
                              key: const ValueKey('material-type'),
                              value: _type.text,
                              label: '자료 종류',
                              externalLabel: true,
                              options: [
                                const SelectOption('', '미선택'),
                                for (final kind in MaterialKinds.all)
                                  SelectOption(kind, kind),
                                if (_type.text.isNotEmpty &&
                                    !MaterialKinds.isAllowed(_type.text))
                                  SelectOption(
                                    _type.text,
                                    '기존 종류 · 네 종류 중 하나를 다시 선택하세요',
                                  ),
                              ],
                              onChanged: (value) {
                                setState(() => _type.text = value);
                                state.didChange(value);
                              },
                            ),
                            if (state.hasError)
                              Text(
                                state.errorText!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _field(
                    'description',
                    '담긴 내용 · 핵심 성과',
                    _description,
                    lines: 4,
                  ),
                  const FeatureLine.one(
                    text: '파일을 첨부하지 않을 때는 어떤 내용인지 설명을 입력하세요.',
                  ),
                  const FeatureLine.one(text: 'PDF 최대 10MB · 전체 50MB.'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _pick,
                        icon: const Icon(Icons.attach_file),
                        label: const Text('PDF 선택'),
                      ),
                      if (_pdf != null)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _pdf = null;
                                  _fileName = '';
                                }),
                          child: const Text('첨부 제외'),
                        ),
                    ],
                  ),
                  if (_pdf != null)
                    FeatureLine.one(
                      text:
                          '$_fileName · ${(_pdf!.length / 1024).ceil()}KB · 등록 후 기기 보관',
                    ),
                  if (_error != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_message != null)
                    Semantics(liveRegion: true, child: Text(_message!)),
                  FeatureActions(
                    children: [
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                if (await allowLeave() && mounted) _reset();
                              },
                        child: const Text('취소'),
                      ),
                      FilledButton(
                        onPressed: _busy ? null : _save,
                        child: Text(
                          _busy
                              ? '처리 중…'
                              : _editing == null
                              ? '자료 등록'
                              : '저장',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}
