import 'package:flutter/material.dart';

import '../api/academic_guidance_models.dart';
import '../../shared/widgets/content_scroll_view.dart';
import 'assistant_conversation.dart';
import 'guidance_asset_button.dart';
import 'guidance_sources.dart';
import 'guidance_menu.dart';
export 'guidance_asset_button.dart' show GuidanceAssetButton;
import 'guidance_criteria_view.dart';

class AcademicGuidanceView extends StatelessWidget {
  const AcademicGuidanceView({super.key, required this.conversation});
  final AssistantConversation conversation;

  bool _collectionWarning(String warning) =>
      warning.contains('수집 시점') ||
      warning.contains('수집 시각') ||
      warning.contains('수집한 지');

  @override
  Widget build(BuildContext context) {
    final node = conversation.guidance;
    final theme = Theme.of(context);
    final personal = node?.nodeId == 'summary';
    final navigation =
        node?.buttons
            .where((b) => b.nodeId == 'home' || b.label == '이전 메뉴')
            .toList() ??
        <GuidanceButton>[];
    final options =
        node?.buttons.where((b) => !navigation.contains(b)).toList() ??
        <GuidanceButton>[];
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.menu_book_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node?.title ?? '학교 안내',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (!conversation.registeredOnly)
                  TextButton(
                    onPressed: conversation.closeGuidance,
                    child: const Text('질문으로 돌아가기'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (conversation.guidanceLoading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
            ],
            if (conversation.guidanceError != null) ...[
              Text(
                conversation.guidanceError!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: conversation.guidanceLoading
                      ? null
                      : () => conversation.navigateGuidance(
                          conversation.guidanceNodeId,
                        ),
                  child: const Text('안내 다시 읽기'),
                ),
              ),
            ],
            if (node != null) ...[
              if (conversation.showingCriteria)
                GuidanceCriteriaView(conversation: conversation)
              else ...[
                for (final warning in node.warnings.where(
                  (w) => !_collectionWarning(w),
                ))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(warning),
                  ),
                if (node.message.trim().isNotEmpty &&
                    node.message.trim() != node.title?.trim() &&
                    !node.cards.any(
                      (card) =>
                          node.message.trim() == card.title.trim() ||
                          node.message.trim() == card.body.trim(),
                    ))
                  Text(node.message),
                if (node.state == 'unavailable')
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('자료 준비 중', style: theme.textTheme.labelMedium),
                  ),
                if (personal) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: conversation.auditsLoading
                          ? null
                          : conversation.refreshAudits,
                      icon: const Icon(Icons.history, size: 18),
                      label: const Text('저장된 내 졸업요건 결과 불러오기'),
                    ),
                  ),
                  if (conversation.auditsLoading)
                    const LinearProgressIndicator(),
                  for (final audit in conversation.auditOptions)
                    ListTile(
                      title: Text('점검 기준일 ${audit.evaluatedOn}'),
                      subtitle: Text(
                        const {
                              'satisfied': '충족',
                              'not_satisfied': '미충족',
                              'needs_review': '확인 필요',
                              'not_applicable': '판정 항목 없음',
                            }[audit.status] ??
                            '상태 확인 필요',
                      ),
                      leading: Icon(
                        conversation.guidanceAuditId == audit.id
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      onTap: conversation.guidanceLoading
                          ? null
                          : () => conversation.selectAudit(audit.id),
                    ),
                  if (!conversation.auditsLoading &&
                      conversation.auditOptions.isEmpty)
                    const Text('졸업 요건에서 저장한 본인 점검 결과를 불러올 수 있습니다.'),
                ],
                for (var index = 0; index < node.cards.length; index++) ...[
                  if (index > 0) const Divider(height: 1),
                  _GuidanceCard(
                    card: node.cards[index],
                    conversation: conversation,
                    showHeading:
                        node.cards[index].title.trim() != node.title?.trim(),
                  ),
                ],
                GuidanceSources(
                  sources: [
                    for (final card in node.cards) ...card.sources,
                    if (node.source != null) node.source!,
                  ],
                  conversation: conversation,
                ),
              ],
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
              if (options.isNotEmpty) ...[
                const SizedBox(height: 12),
                GuidanceMenu(
                  nodeId: conversation.guidanceNodeId,
                  options: options,
                  loading: conversation.guidanceLoading,
                  onSelect: conversation.navigateGuidance,
                ),
              ],
              if (navigation.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final button in navigation)
                      TextButton.icon(
                        icon: Icon(
                          button.nodeId == 'home'
                              ? Icons.home_outlined
                              : Icons.arrow_back,
                          size: 18,
                        ),
                        onPressed: conversation.guidanceLoading
                            ? null
                            : () =>
                                  conversation.navigateGuidance(button.nodeId),
                        label: Text(button.label),
                      ),
                  ],
                ),
              ],
              if (!conversation.showingCriteria &&
                  (conversation.registeredOnly ||
                      node.notice != null ||
                      node.snapshotStale == true ||
                      node.warnings.any(_collectionWarning)))
                ExpansionTile(
                  title: Text('자료 정보', style: theme.textTheme.labelMedium),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  children: [
                    if (conversation.registeredOnly)
                      const Text('서버 수집 참고 자료입니다. 원문의 학교와 적용 대상을 확인해 주세요.'),
                    if (node.snapshotStale == true)
                      const Text('최신 내용은 원문에서 확인해 주세요.'),
                    for (final warning in node.warnings.where(
                      _collectionWarning,
                    ))
                      Text(warning),
                    if (node.notice != null) Text(node.notice!),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}

String _displayBody(GuidanceCard card) {
  final lines = card.body.split('\n');
  var first = 0;
  var removedHeading = false;
  while (first < lines.length) {
    final line = lines[first].trim();
    if (line == card.title.trim() && line.isNotEmpty) {
      removedHeading = true;
      first++;
    } else if (line.isEmpty) {
      first++;
    } else {
      break;
    }
  }
  return removedHeading ? lines.skip(first).join('\n') : card.body;
}

class _GuidanceCard extends StatelessWidget {
  const _GuidanceCard({
    required this.card,
    required this.conversation,
    this.expanded = false,
    this.showHeading = true,
  });
  final GuidanceCard card;
  final AssistantConversation conversation;
  final bool expanded;
  final bool showHeading;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading)
          Text(card.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (card.extractionStatus == 'ocr_unreviewed')
          const Text('OCR 미검토 · 원본 이미지를 먼저 확인해 주세요.'),
        if (card.imageAssetId != null)
          GuidanceAssetButton(
            conversation: conversation,
            id: card.imageAssetId!,
            image: true,
          ),
        if (card.type == 'calendar_event' && card.dateText != null) ...[
          const SizedBox(height: 4),
          if (showHeading)
            Text(card.dateText!, style: Theme.of(context).textTheme.bodySmall),
          if (card.body.trim().isNotEmpty &&
              card.body.trim() != '${card.dateText} — ${card.title}' &&
              card.body.trim() != card.title &&
              card.body.trim() != card.dateText)
            SelectableText(_displayBody(card)),
        ] else if (card.extractionStatus == 'ocr_unreviewed')
          ExpansionTile(
            title: const Text('추출 텍스트 보기'),
            children: [SelectableText(_displayBody(card))],
          )
        else if (_displayBody(card).trim().isNotEmpty)
          SelectableText(_displayBody(card)),
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
                              showHeading: false,
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
        if (expanded)
          GuidanceSources(sources: card.sources, conversation: conversation),
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
