import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/app_typography.dart';
import '../../../shared/widgets/surface_card.dart';
import 'portfolio_editor_dialog.dart';
import 'portfolio_workspace_repository.dart';

class PortfolioDraftsPage extends StatefulWidget {
  const PortfolioDraftsPage({
    super.key,
    required this.isDocument,
    this.repository,
  });
  final bool isDocument;
  final PortfolioWorkspaceRepository? repository;
  @override
  State<PortfolioDraftsPage> createState() => _PortfolioDraftsPageState();
}

class _PortfolioDraftsPageState extends State<PortfolioDraftsPage> {
  late final PortfolioWorkspaceRepository _repository;
  bool _loading = true, _failed = false, _busy = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? PortfolioWorkspaceRepository();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      await _repository.load();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit({
    PortfolioComposition? composition,
    ApplicationDocument? document,
  }) async {
    try {
      await _repository.reloadSources();
      if (!mounted) return;
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PortfolioEditorDialog(
          repository: _repository,
          isDocument: widget.isDocument,
          composition: composition,
          document: document,
        ),
      );
      if (mounted && saved == true) {
        setState(() => _message = '이 기기에 초안을 저장했습니다.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = '개인 기록을 읽지 못했습니다. 원본은 유지됩니다. 다시 시도하세요.');
      }
    }
  }

  Future<void> _delete(String id, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('로컬 초안 삭제'),
        content: Text('$title 초안을 삭제할까요? 연결된 성과·경험 원본은 삭제되지 않습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      if (widget.isDocument) {
        await _repository.deleteDocument(id);
      } else {
        await _repository.deleteComposition(id);
      }
      if (mounted) setState(() => _message = '초안을 삭제했습니다. 원본 기록은 유지됩니다.');
    } catch (_) {
      if (mounted) {
        setState(() => _message = '삭제하지 못했습니다. 초안과 원본은 유지됩니다. 다시 시도하세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _documentText(ApplicationDocument document) => [
    document.title,
    '기기 로컬 지원 문서 초안 · 미제출',
    '${document.type} · ${document.target} · ${document.role}',
    document.body,
    if (document.sources.any((ref) => !_repository.sources.containsKey(ref)))
      '참고 원본 기록 삭제됨 · 작성한 본문은 유지됩니다.',
  ].join('\n\n');

  Widget _card(
    String title,
    String subtitle,
    List<String> refs,
    VoidCallback edit,
    VoidCallback delete,
    String preview,
  ) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: AppTypography.section,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(subtitle),
          for (var i = 0; i < refs.length; i++)
            Text(
              '${i + 1}. ${_repository.sources[refs[i]]?.label ?? '원본 기록 삭제됨 · 연결 없음'}',
            ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: _busy ? null : edit,
                child: const Text('수정'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (_) => _DraftPreview(text: preview),
                      ),
                child: const Text('미리보기'),
              ),
              TextButton(
                onPressed: _busy ? null : delete,
                child: const Text('삭제'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed) {
      return SingleChildScrollView(
        child: Column(
          children: [
            const Text('초안 또는 연결 기록을 읽지 못했습니다. 기존 저장 내용은 덮어쓰지 않습니다.'),
            TextButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ),
      );
    }
    final document = widget.isDocument;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            document ? '지원 문서' : '포트폴리오 구성',
            style: const TextStyle(
              fontSize: AppTypography.page,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            document
                ? '지원처별 이력서·자기소개서 초안을 직접 편집합니다. 개인 경험·성과를 선택하여 본문에 가져올 수 있습니다. AI가 작성하거나 지원처로 제출하지 않습니다.'
                : '개인 성과 중 사용할 항목과 순서를 선택합니다. 나만 보기·제출 검토용·공개 검토용은 기기 로컬 사용 의도이며 실제 게시·권한 설정이 아닙니다.',
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _busy ? null : () => _edit(),
            icon: const Icon(Icons.add),
            label: Text(document ? '지원 문서 초안 추가' : '포트폴리오 구성 추가'),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_message!),
            ),
          if (document && _repository.documents.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: Text('아직 만든 문서가 없습니다. 빈 초안부터 직접 작성할 수 있습니다.'),
            ),
          if (!document && _repository.compositions.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: Text('아직 만든 구성이 없습니다. 성과 기록을 먼저 추가하거나 빈 구성을 저장하세요.'),
            ),
          if (document)
            for (final d in _repository.documents)
              _card(
                d.title,
                '${d.type} · ${d.target} · ${d.role} · 로컬 초안 · 미제출',
                d.sources,
                () => _edit(document: d),
                () => _delete(d.id, d.title),
                _documentText(d),
              )
          else
            for (final c in _repository.compositions)
              _card(
                c.title,
                '${audienceLabel(c.audience)} · ${c.sources.length}개 · 로컬 구성 · 게시되지 않음',
                c.sources,
                () => _edit(composition: c),
                () => _delete(c.id, c.title),
                _repository.compositionText(c),
              ),
        ],
      ),
    );
  }
}

class _DraftPreview extends StatefulWidget {
  const _DraftPreview({required this.text});
  final String text;
  @override
  State<_DraftPreview> createState() => _DraftPreviewState();
}

class _DraftPreviewState extends State<_DraftPreview> {
  String? _message;
  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.text));
      if (mounted) {
        setState(() => _message = '초안 텍스트를 복사했습니다. 붙여넣을 위치와 공개 범위를 직접 확인하세요.');
      }
    } catch (_) {
      if (mounted) setState(() => _message = '복사하지 못했습니다. 본문을 직접 선택해 복사하세요.');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('로컬 초안 미리보기'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(widget.text),
            if (_message != null) Text(_message!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('닫기'),
      ),
      FilledButton(onPressed: _copy, child: const Text('초안 텍스트 복사')),
    ],
  );
}
