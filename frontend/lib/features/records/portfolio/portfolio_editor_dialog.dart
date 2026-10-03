import 'package:flutter/material.dart';

import '../../../shared/widgets/anchored_select_field.dart';
import '../personal_record_repository.dart';
import 'portfolio_workspace_repository.dart';

class PortfolioEditorDialog extends StatefulWidget {
  const PortfolioEditorDialog({
    super.key,
    required this.repository,
    required this.isDocument,
    this.composition,
    this.document,
  });
  final PortfolioWorkspaceRepository repository;
  final bool isDocument;
  final PortfolioComposition? composition;
  final ApplicationDocument? document;
  @override
  State<PortfolioEditorDialog> createState() => _PortfolioEditorDialogState();
}

class _PortfolioEditorDialogState extends State<PortfolioEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _description, _target, _role, _body;
  late List<String> _selected;
  late PortfolioAudience _audience;
  late String _type;
  late bool _reviewed;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.composition;
    final d = widget.document;
    _title = TextEditingController(text: c?.title ?? d?.title ?? '');
    _description = TextEditingController(text: c?.description ?? '');
    _target = TextEditingController(text: d?.target ?? '');
    _role = TextEditingController(text: d?.role ?? '');
    _body = TextEditingController(text: d?.body ?? '');
    _selected = [...c?.sources ?? d?.sources ?? []];
    _audience = c?.audience ?? PortfolioAudience.private;
    _reviewed = c?.reviewed ?? false;
    _type = d?.type ?? '이력서';
  }

  @override
  void dispose() {
    for (final controller in [_title, _description, _target, _role, _body]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (_reviewed) setState(() => _reviewed = false);
  }

  Widget _field(
    TextEditingController controller,
    String key,
    String label, {
    bool required = false,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      key: ValueKey('portfolio-$key'),
      controller: controller,
      enabled: !_saving,
      maxLines: maxLines,
      onChanged: (_) => _changed(),
      decoration: InputDecoration(
        labelText: '$label${required ? ' *' : ' (선택)'}',
      ),
      validator: required
          ? (value) =>
                value == null || value.trim().isEmpty ? '$label을 입력하세요.' : null
          : null,
    ),
  );

  void _select(String ref, bool selected) => setState(() {
    if (selected) {
      _selected.add(ref);
    } else {
      _selected.remove(ref);
    }
    _reviewed = false;
  });

  void _move(int from, int to) => setState(() {
    final ref = _selected.removeAt(from);
    _selected.insert(to, ref);
    _reviewed = false;
  });

  Future<void> _importFacts() async {
    final facts = [
      for (final ref in _selected)
        if (widget.repository.sources[ref] != null)
          widget.repository.sources[ref]!.text,
    ].join('\n\n');
    if (facts.isEmpty) {
      setState(() => _error = '가져올 경험·성과 기록을 먼저 선택하세요.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('선택한 기록을 본문에 추가'),
        content: const Text(
          '선택한 개인 기록의 현재 내용을 본문 끝에 추가합니다. AI가 만든 문장이 아니며 기존 본문은 덮어쓰지 않습니다. 사실과 공개 가능 여부를 직접 검토하세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('본문 끝에 추가'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _body.text = [
          _body.text,
          facts,
        ].where((s) => s.trim().isNotEmpty).join('\n\n');
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (!widget.isDocument &&
        _audience == PortfolioAudience.publicReview &&
        !_reviewed) {
      setState(() => _error = '공개할 내용의 권한과 사실 관계를 직접 확인하세요.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.isDocument) {
        await widget.repository.saveDocument(
          ApplicationDocument(
            id: widget.document?.id ?? PersonalRecord.newId(),
            title: _title.text.trim(),
            target: _target.text.trim(),
            role: _role.text.trim(),
            type: _type,
            body: _body.text,
            sources: _selected,
          ),
        );
      } else {
        await widget.repository.saveComposition(
          PortfolioComposition(
            id: widget.composition?.id ?? PersonalRecord.newId(),
            title: _title.text.trim(),
            description: _description.text.trim(),
            audience: _audience,
            reviewed: _reviewed,
            sources: _selected,
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '기기에 저장하지 못했습니다. 입력은 유지됩니다. 원본 연결과 저장소 상태를 확인하고 다시 시도하세요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = widget.repository.sources.values
        .where(
          (s) => widget.isDocument || s.kind == PersonalRecordKind.portfolio,
        )
        .toList();
    return AlertDialog(
      title: Text(widget.isDocument ? '지원 문서 초안 편집' : '포트폴리오 구성 편집'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('기기 로컬 초안 · 온라인 게시·제출·파일 업로드·AI 생성은 하지 않습니다.'),
                const SizedBox(height: 16),
                _field(
                  _title,
                  'title',
                  widget.isDocument ? '문서 이름' : '구성 이름',
                  required: true,
                ),
                if (widget.isDocument) ...[
                  _field(_target, 'target', '지원처', required: true),
                  _field(_role, 'role', '지원 직무', required: true),
                  IgnorePointer(
                    ignoring: _saving,
                    child: AnchoredSelectField<String>(
                      key: const ValueKey('portfolio-document-type'),
                      value: _type,
                      label: '문서 종류',
                      options: [
                        for (final type in {'이력서', '자기소개서', '기타', _type})
                          SelectOption(type, type),
                      ],
                      onChanged: (type) => setState(() => _type = type),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _field(_body, 'body', '직접 작성할 본문', maxLines: 8),
                ] else ...[
                  _field(_description, 'description', '소개', maxLines: 3),
                  IgnorePointer(
                    ignoring: _saving,
                    child: AnchoredSelectField<PortfolioAudience>(
                      key: const ValueKey('portfolio-audience'),
                      value: _audience,
                      label: '사용 의도 · 실제 공개 설정 아님',
                      options: [
                        for (final audience in PortfolioAudience.values)
                          SelectOption(audience, audienceLabel(audience)),
                      ],
                      onChanged: (audience) => setState(() {
                        _audience = audience;
                        _reviewed = false;
                      }),
                    ),
                  ),
                  if (_audience == PortfolioAudience.publicReview)
                    CheckboxListTile(
                      key: const ValueKey('portfolio-review'),
                      value: _reviewed,
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _reviewed = value!),
                      title: const Text('내용·권한·개인정보·링크의 공개 가능 여부를 직접 확인했습니다.'),
                    ),
                ],
                const SizedBox(height: 16),
                const Text('선택한 기록 · 위에서 아래로 구성됩니다.'),
                for (var i = 0; i < _selected.length; i++)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${i + 1}. ${widget.repository.sources[_selected[i]]?.label ?? '원본 기록 삭제됨 · 연결 없음'}',
                          ),
                          Wrap(
                            children: [
                              IconButton(
                                key: ValueKey('portfolio-up-${_selected[i]}'),
                                tooltip: '위로 이동',
                                onPressed: _saving || i == 0
                                    ? null
                                    : () => _move(i, i - 1),
                                icon: const Icon(Icons.arrow_upward),
                              ),
                              IconButton(
                                key: ValueKey('portfolio-down-${_selected[i]}'),
                                tooltip: '아래로 이동',
                                onPressed: _saving || i == _selected.length - 1
                                    ? null
                                    : () => _move(i, i + 1),
                                icon: const Icon(Icons.arrow_downward),
                              ),
                              TextButton(
                                key: ValueKey(
                                  'portfolio-remove-${_selected[i]}',
                                ),
                                onPressed: _saving
                                    ? null
                                    : () => _select(_selected[i], false),
                                child: const Text('구성에서 제외'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const Text('추가할 개인 기록 선택 · 예시 데이터는 제외됩니다.'),
                if (candidates.isEmpty)
                  const Text('개인 기록이 없습니다. 성과 기록 또는 경험 메뉴에서 먼저 추가하세요.'),
                for (final source in candidates.where(
                  (s) => !_selected.contains(s.ref),
                ))
                  CheckboxListTile(
                    key: ValueKey('portfolio-source-${source.ref}'),
                    value: false,
                    onChanged: _saving
                        ? null
                        : (value) => _select(source.ref, value!),
                    title: Text(source.label),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                if (widget.isDocument)
                  OutlinedButton(
                    onPressed: _saving ? null : _importFacts,
                    child: const Text('선택한 기록을 본문에 가져오기'),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '저장 중…' : '초안 저장'),
        ),
      ],
    );
  }
}
