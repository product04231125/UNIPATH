import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../shared/widgets/anchored_select_field.dart';
import '../../../shared/widgets/feature_line.dart';
import '../../../shared/widgets/field_label.dart';
import '../../../shared/widgets/field_requirement.dart';
import '../../../shared/widgets/input_dialog.dart';
import '../../../shared/widgets/work_layout.dart';
import '../../auth/auth_api.dart';
import 'material_repository.dart';

/// `자료 추가`·`자료 수정`: the same input dialog as 활동·자격증 records, opened
/// from the page's `+` or a tile. True once the material is saved.
Future<bool> showMaterialForm({
  required BuildContext context,
  required MaterialRepository repository,
  PersonalMaterial? material,
  Future<XFile?> Function()? pickPdf,
  bool Function()? blocked,
  void Function(PersonalMaterial)? onViewSaved,
}) async =>
    await showInputDialog<bool>(
      context: context,
      builder: (_) => MaterialFormDialog(
        repository: repository,
        material: material,
        pickPdf: pickPdf,
        blocked: blocked,
        onViewSaved: onViewSaved,
      ),
    ) ??
    false;

class MaterialFormDialog extends StatefulWidget {
  const MaterialFormDialog({
    super.key,
    required this.repository,
    this.material,
    this.pickPdf,
    this.blocked,
    this.onViewSaved,
  });

  final MaterialRepository repository;

  /// The material being edited; null adds a new one.
  final PersonalMaterial? material;
  final Future<XFile?> Function()? pickPdf;

  /// True (after telling the student) when saving is not allowed, e.g. 둘러보기.
  final bool Function()? blocked;

  /// Opens the saved PDF; null when the store has no in-app viewer.
  final void Function(PersonalMaterial)? onViewSaved;

  @override
  State<MaterialFormDialog> createState() => _MaterialFormDialogState();
}

class _MaterialFormDialogState extends State<MaterialFormDialog> {
  late final PersonalMaterial? _saved = widget.material;
  late final _title = TextEditingController(text: _saved?.title ?? '');
  late final _description = TextEditingController(
    text: _saved?.description ?? '',
  );
  late final Listenable _changes = Listenable.merge([_title, _description]);
  final _form = GlobalKey<FormState>();
  late String _type = _saved?.type ?? '';
  late String _fileName = _saved?.fileName ?? '';

  /// A newly picked PDF only; a saved one stays where it is kept.
  Uint8List? _pdf;
  bool _busy = false;
  String? _error;

  MaterialRepository get _repo => widget.repository;

  bool get _dirty =>
      _title.text != (_saved?.title ?? '') ||
      _type != (_saved?.type ?? '') ||
      _description.text != (_saved?.description ?? '') ||
      _fileName != (_saved?.fileName ?? '') ||
      _pdf != null;

  bool get _hasContent =>
      _title.text.trim().isNotEmpty ||
      _type.isNotEmpty ||
      _description.text.trim().isNotEmpty ||
      _fileName.isNotEmpty;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
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
        throw StateError('PDF는 8MB 이하로 선택하세요.');
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
    if (_busy || (widget.blocked?.call() ?? false)) return;
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repo.save(
        PersonalMaterial(
          id: _saved?.id ?? MaterialRepository.newId(),
          title: _title.text.trim(),
          type: _type.trim(),
          description: _description.text.trim(),
          fileName: _fileName,
          pdf: _pdf,
          byteCount: _pdf?.length ?? _saved?.byteCount,
          version: _saved?.version ?? 0,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = switch (e) {
            StateError(:final message) => message,
            AuthFailure(:final message) => message,
            _ => '자료를 저장하지 못했습니다. 입력과 PDF를 유지했습니다. 다시 시도하세요.',
          };
        });
      }
    }
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

  Widget _typeField() => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: FormField<String>(
      key: const ValueKey('material-type-state'),
      initialValue: _type,
      validator: (_) => MaterialKinds.isAllowed(_type) ? null : '자료 종류를 선택하세요.',
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnchoredSelectField<String>(
            key: const ValueKey('material-type'),
            value: _type,
            label: fieldRequirementLabel('자료 종류', required: true),
            externalLabel: true,
            options: [
              const SelectOption('', '미선택'),
              for (final kind in MaterialKinds.all) SelectOption(kind, kind),
              // A saved free-text type stays until one of the four is picked.
              if (_type.isNotEmpty && !MaterialKinds.isAllowed(_type))
                SelectOption(_type, '기존 종류 · 네 종류 중 하나를 다시 선택하세요'),
            ],
            onChanged: (value) {
              setState(() => _type = value);
              state.didChange(value);
            },
          ),
          if (state.hasError)
            Text(
              state.errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    return InputDialog(
      changes: _changes,
      editing: saved != null,
      saving: _busy,
      hasContent: () => _hasContent,
      hasUnsavedChanges: () => _dirty,
      title: Text(saved == null ? '자료 추가' : '자료 수정'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field('title', '자료 이름', _title, required: true),
            _typeField(),
            _field('description', '담긴 내용 · 핵심 성과', _description, lines: 4),
            const NoteLine(
              icon: Icons.info_outline,
              text: '파일을 첨부하지 않을 때는 어떤 내용인지 설명을 입력하세요.',
            ),
            const SizedBox(height: 4),
            const NoteLine(
              icon: Icons.picture_as_pdf_outlined,
              text: 'PDF 최대 8MB · 전체 50MB.',
            ),
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
                // The saved PDF (not one just picked): the server renders its pages.
                if (widget.onViewSaved case final view?
                    when saved != null &&
                        saved.hasPdf &&
                        _pdf == null &&
                        _fileName.isNotEmpty)
                  TextButton.icon(
                    key: const ValueKey('material-form-view'),
                    onPressed: () => view(saved),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('PDF 보기'),
                  ),
                if (_fileName.isNotEmpty)
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
            if (_fileName.isNotEmpty)
              FeatureLine.one(
                text:
                    '$_fileName · ${((_pdf?.length ?? saved?.byteCount ?? 0) / 1024).ceil()}KB'
                    '${_pdf == null
                        ? ''
                        : _repo.inAccount
                        ? ' · 저장하면 계정에 보관'
                        : ' · 등록 후 기기 보관'}',
              ),
            if (_error case final error?)
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => InputDialog.cancel<bool>(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(
            _busy
                ? '처리 중…'
                : saved == null
                ? '자료 등록'
                : '저장',
          ),
        ),
      ],
    );
  }
}
