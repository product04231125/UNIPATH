import 'package:flutter/material.dart';

import '../api/academic_guidance_models.dart';
import '../auth/guidance_asset_gateway.dart';
import '../../shared/widgets/external_link_button.dart';
import '../../shared/widgets/content_scroll_view.dart';
import 'assistant_conversation.dart';
import 'guidance_asset_open.dart';

class AcademicGuidanceView extends StatelessWidget {
  const AcademicGuidanceView({super.key, required this.conversation});
  final AssistantConversation conversation;
  @override
  Widget build(BuildContext context) {
    final node = conversation.guidance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '학사 안내',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (!conversation.registeredOnly)
              TextButton(
                onPressed: conversation.closeGuidance,
                child: const Text('질문으로 돌아가기'),
              ),
          ],
        ),
        if (conversation.registeredOnly) ...[
          const Text('메뉴를 선택해 학교 안내 자료를 찾아보세요.'),
          const Text(
            '현재 서버가 제공하는 수집 자료입니다. 등록 학교와의 연결은 아직 확인되지 않아 원문의 학교·적용 대상을 확인해 주세요.',
          ),
          const SizedBox(height: 12),
        ],
        if (conversation.guidanceLoading) const LinearProgressIndicator(),
        if (conversation.guidanceError != null) ...[
          Text(conversation.guidanceError!),
          TextButton(
            onPressed: conversation.guidanceLoading
                ? null
                : () => conversation.navigateGuidance(
                    conversation.guidanceNodeId,
                  ),
            child: const Text('안내 다시 읽기'),
          ),
        ],
        if (node != null) ...[
          Text(
            node.title ?? '학사 안내',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final warning in node.warnings)
            Text(
              warning,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (node.snapshotStale == true)
            const Text('수집한 지 오래된 자료입니다. 원문의 최신 내용을 확인하세요.'),
          if (node.fetchedAt != null) Text('수집 시각: ${node.fetchedAt}'),
          Text(node.message),
          if (node.state == 'unavailable') const Text('자료 준비 중'),
          if (node.reason == 'verified_audit_required' ||
              node.audit != null) ...[
            TextButton(
              onPressed: conversation.auditsLoading
                  ? null
                  : conversation.refreshAudits,
              child: const Text('본인 공식 감사 이력 읽기'),
            ),
            if (conversation.auditsLoading) const LinearProgressIndicator(),
            for (final audit in conversation.auditOptions)
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  title: Text(
                    '${audit.evaluatedOn} · ${const {'satisfied': '충족', 'not_satisfied': '미충족', 'needs_review': '확인 필요', 'not_applicable': '적용 기준 없음'}[audit.status] ?? '상태 확인 필요'}',
                  ),
                  selected: conversation.guidanceAuditId == audit.id,
                  leading: Icon(
                    conversation.guidanceAuditId == audit.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  onTap: conversation.guidanceLoading
                      ? null
                      : () => conversation.selectAudit(audit.id),
                ),
              ),
            if (!conversation.auditsLoading &&
                conversation.auditOptions.isEmpty)
              const Text(
                '현재 학업 프로필에 맞는 공식 감사를 선택해야 합니다. 개인 계산 결과는 사용할 수 없습니다.',
              ),
          ],
          if (node.audit?.currentUsable == false)
            const Text('재확인 필요 · 과거 기준일의 감사 결과입니다.'),
          for (final card in node.cards)
            _GuidanceCard(card: card, conversation: conversation),
          if (node.source != null) _source(node.source!),
          if (node.notice != null) Text(node.notice!),
          if (node.workflow != null) ...[
            for (final step in node.workflow!.steps) Text(step),
            if (node.workflow!.id == 'posting')
              TextButton(
                onPressed: conversation.openCareer,
                child: const Text('채용공고 분석으로 이동'),
              )
            else
              const Text('이 분석 기능은 준비 중입니다.'),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final button in node.buttons)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton(
                    onPressed: conversation.guidanceLoading
                        ? null
                        : () => conversation.navigateGuidance(button.nodeId),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${button.label}${button.availability == "content_pending" ? " · 준비 중" : ""}',
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _source(GuidanceSource source) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (source.title != null) Text(source.title!),
      if (source.page != null) Text('${source.page}페이지'),
      if (source.assetId != null)
        GuidanceAssetButton(conversation: conversation, id: source.assetId!),
      if (source.sourceUrl != null)
        ExternalLinkButton(url: source.sourceUrl!, label: '출처 열기'),
    ],
  );
}

class _GuidanceCard extends StatelessWidget {
  const _GuidanceCard({
    required this.card,
    required this.conversation,
    this.expanded = false,
  });
  final GuidanceCard card;
  final AssistantConversation conversation;
  final bool expanded;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(card.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (card.extractionStatus == 'ocr_unreviewed')
          const Text('OCR 미검토 · 원본 이미지를 먼저 확인해 주세요.'),
        if (card.imageAssetId != null)
          GuidanceAssetButton(
            conversation: conversation,
            id: card.imageAssetId!,
            image: true,
          ),
        if (card.extractionStatus == 'ocr_unreviewed')
          ExpansionTile(
            title: const Text('추출 텍스트 보기'),
            children: [SelectableText(card.body)],
          )
        else
          SelectableText(
            !expanded && card.body.length > 600
                ? '${card.body.substring(0, 600)}…'
                : card.body,
          ),
        if (card.dateText != null) Text(card.dateText!),
        if (card.status != null)
          Text(
            '결과: ${const {'satisfied': '충족', 'not_satisfied': '미충족', 'needs_review': '확인 필요', 'not_applicable': '적용 기준 없음'}[card.status] ?? '상태 확인 필요'}',
          ),
        if (card.quantities != null)
          Text(
            '현재 ${card.quantities!.current ?? "확인 필요"} / 기준 ${card.quantities!.required ?? "확인 필요"} / 부족 ${card.quantities!.deficit ?? "확인 필요"} ${card.unit ?? ""}',
          ),
        for (final course in card.missingCourses) Text('미충족 과목: $course'),
        for (final course in card.uncertainCourses) Text('확인 필요 과목: $course'),
        if (card.table != null) _grid(context, card.table!.grid),
        for (final table in card.tables ?? <List<List<String?>>>[])
          _grid(context, table),
        if (!expanded &&
            (card.body.length > 300 ||
                card.table != null ||
                card.tables != null))
          TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => Dialog(
                child: SizedBox(
                  width: 960,
                  height: MediaQuery.sizeOf(context).height * .85,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(card.title),
                            ),
                          ),
                          IconButton(
                            tooltip: '상세 닫기',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      Expanded(
                        child: ContentScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: _GuidanceCard(
                              card: card,
                              conversation: conversation,
                              expanded: true,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            child: const Text('넓게 자세히 보기'),
          ),
        for (final source in card.sources) ...[
          Text(
            '${source.title ?? "출처"}${source.page == null ? "" : " · ${source.page}페이지"}',
          ),
          if (source.assetId != null)
            GuidanceAssetButton(
              conversation: conversation,
              id: source.assetId!,
            ),
          if (source.sourceUrl != null)
            ExternalLinkButton(url: source.sourceUrl!, label: '출처 열기'),
        ],
      ],
    ),
  );
  Widget _grid(BuildContext context, List<List<String?>> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final columns = rows.fold<int>(
      0,
      (n, row) => row.length > n ? row.length : n,
    );
    if (columns == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Table(
        border: TableBorder.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        children: [
          for (final row in rows)
            TableRow(
              children: [
                for (var i = 0; i < columns; i++)
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(i < row.length ? row[i] ?? '' : ''),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class GuidanceAssetButton extends StatefulWidget {
  const GuidanceAssetButton({
    super.key,
    required this.conversation,
    required this.id,
    this.image = false,
  });
  final AssistantConversation conversation;
  final String id;
  final bool image;
  @override
  State<GuidanceAssetButton> createState() => _AssetState();
}

class _AssetState extends State<GuidanceAssetButton> {
  GuidanceAsset? _asset;
  bool _loading = false;
  String? _error;
  int _generation = 0;
  @override
  void didUpdateWidget(covariant GuidanceAssetButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id ||
        oldWidget.conversation != widget.conversation) {
      _generation++;
      _asset = null;
      _loading = false;
      _error = null;
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await widget.conversation.loadGuidanceAsset(widget.id);
      if (mounted && generation == _generation) setState(() => _asset = value);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '원문을 읽지 못했습니다. 다시 시도해 주세요.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_error != null) Text(_error!),
      if (_asset == null)
        TextButton(
          onPressed: _loading ? null : _load,
          child: Text(
            _loading
                ? '원문 준비 중…'
                : widget.image
                ? '원본 이미지 읽기'
                : '원문 준비',
          ),
        ),
      if (_asset?.contentType == 'image/jpeg')
        Image.memory(
          _asset!.bytes,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Text('이미지를 표시하지 못했습니다. 다시 읽어 주세요.'),
        ),
      if (_asset?.contentType == 'application/pdf')
        TextButton(
          onPressed: () async {
            try {
              final opened = await openGuidancePdf(_asset!, widget.id);
              if (!opened && mounted) {
                setState(
                  () => _error =
                      '원문 창이 열리지 않았다면 팝업 또는 기본 PDF 앱 설정을 확인하고 다시 시도해 주세요.',
                );
              }
            } catch (_) {
              if (mounted) setState(() => _error = '원문을 열지 못했습니다. 다시 시도해 주세요.');
            }
          },
          child: const Text('원문 PDF 열기'),
        ),
    ],
  );
}
