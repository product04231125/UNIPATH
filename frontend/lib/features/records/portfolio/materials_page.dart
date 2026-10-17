import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../shared/app_style.dart';
import '../../../shared/widgets/content_scroll_view.dart';
import '../../../shared/widgets/field_label.dart';
import '../../../shared/widgets/input_dialog.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/responsive_columns.dart';
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
      _description = TextEditingController();
  final _form = GlobalKey<FormState>();
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
        if (_type.text.trim().isEmpty) _type.text = 'PDF';
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

  Widget _field(
    String key,
    String label,
    TextEditingController controller, {
    int lines = 1,
    bool required = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: FieldLabel(
      label: label,
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
  );
  @override
  Widget build(BuildContext context) => ContentScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          title: '내 자료',
          description: '어떤 파일인지, 어떤 내용이 담겼는지 간단히 기록하거나 PDF를 보관하세요.',
        ),
        const Text(
          '이 기기에만 보관합니다. PDF 최대 10MB · 전체 PDF 50MB. 브라우저 데이터 삭제 또는 앱 데이터 삭제 시 사라질 수 있습니다. 민감한 정보가 포함됐는지 확인하세요.',
        ),
        const SizedBox(height: 8),
        const Text(
          'AI 자료 분석은 아직 연결되지 않았습니다. 등록만으로 서버에 전송되거나 AI 분석·학교 공식 판정에 사용되지 않습니다.',
        ),
        const SizedBox(height: 16),
        if (_loading)
          const LinearProgressIndicator()
        else if (_failed) ...[
          const Text('자료 목록을 읽지 못했습니다. 저장된 자료를 덮어쓰지 않습니다.'),
          TextButton(
            onPressed: _busy ? null : _load,
            child: const Text('다시 읽기'),
          ),
        ] else
          ResponsiveColumns(
            enabled: true,
            first: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '자료 ${_records.length}개',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_records.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('등록한 자료가 없습니다. 설명만 기록하거나 PDF를 선택해 등록하세요.'),
                  ),
                for (final r in _records)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            r.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (r.type.isNotEmpty) Text('종류: ${r.type}'),
                          if (r.description.isNotEmpty) Text(r.description),
                          if (r.pdf != null)
                            Text(
                              '${r.fileName} · ${(r.pdf!.length / 1024).ceil()}KB · 기기 보관',
                            )
                          else
                            const Text('내용 설명 기록'),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        if (await allowLeave() && mounted) {
                                          _reset(r);
                                        }
                                      },
                                child: const Text('수정'),
                              ),
                              if (r.pdf != null)
                                OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          setState(() => _busy = true);
                                          try {
                                            await (widget.exportPdf ??
                                                exportMaterialPdf)(r);
                                          } catch (_) {
                                            if (mounted) {
                                              setState(
                                                () => _error = 'PDF를 내보내지 못했습니다. 보관 자료는 유지했습니다.',
                                              );
                                            }
                                          } finally {
                                            if (mounted) {
                                              setState(() => _busy = false);
                                            }
                                          }
                                        },
                                  icon: const Icon(Icons.download_outlined),
                                  label: const Text('PDF 내보내기'),
                                ),
                              FilledButton(
                                style: destructiveButtonStyle(context),
                                onPressed: _busy ? null : () => _delete(r),
                                child: const Text('삭제'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            second: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _editing == null ? '자료 등록' : '자료 수정',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      _field('title', '자료 이름 *', _title, required: true),
                      _field('type', '파일 종류 · 용도 (선택)', _type),
                      _field(
                        'description',
                        '담긴 내용 · 핵심 성과',
                        _description,
                        lines: 4,
                      ),
                      const Text('파일을 첨부하지 않을 때는 어떤 내용인지 설명을 입력하세요.'),
                      const SizedBox(height: 12),
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
                        Text(
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
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
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
                            child: Text(_busy ? '처리 중…' : '자료 등록'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
