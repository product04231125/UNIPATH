import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/app_tones.dart';
import '../../shared/widgets/external_link_button.dart';
import '../../shared/widgets/tone_chip.dart';
import '../api/job_analysis_models.dart';
import '../api/job_recommendation_api.dart';
import '../api/student_api.dart';
import '../auth/auth_api.dart';
import '../career/saved_analyses.dart';
import '../records/portfolio/job_recommendation_result.dart';
import 'posting_link.dart';

/// The posting a draft is written for, in the writing form: title, company and source, how
/// its requirements stood, the original link and the collected text to read.
class LinkedPostingCard extends StatelessWidget {
  const LinkedPostingCard({super.key, required this.link, this.onUnlink});
  final PostingLink link;
  final VoidCallback? onUnlink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final required = link.requirements.where((r) => r.required);
    return Container(
      key: const ValueKey('writing-linked-posting'),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.work_outline,
                  size: 20,
                  color: AppTone.accent.color(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      link.title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      [
                        if (link.company.isNotEmpty) link.company,
                        link.sourceLabel,
                        if (link.analyzedAt case final at?)
                          '${savedAnalysisTime(at)} 분석',
                      ].join(' · '),
                      style: muted,
                    ),
                  ],
                ),
              ),
              if (onUnlink != null)
                TextButton(
                  key: const ValueKey('writing-unlink-posting'),
                  onPressed: onUnlink,
                  child: const Text('연결 해제'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (link.requirements.isNotEmpty)
                ToneChip(
                  label:
                      '요건 ${link.requirements.length}개 · 준비 ${link.ready}개'
                      '${required.isEmpty ? '' : ' · 필수 ${required.length}개'}',
                  tone: AppTone.info,
                ),
              if (!link.hasText)
                const ToneChip(
                  label: '공고 본문 없음 · 요건만 보냅니다',
                  tone: AppTone.warning,
                ),
              if (link.url.isNotEmpty)
                ExternalLinkButton(
                  url: link.url,
                  label: '원 공고',
                  description: '최신 모집 조건과 마감은 원 공고에서 확인하세요.',
                ),
            ],
          ),
          if (link.hasText)
            ExpansionTile(
              key: const ValueKey('writing-linked-posting-text'),
              tilePadding: const EdgeInsets.only(right: 8),
              expandedAlignment: Alignment.topLeft,
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              title: Text('공고 본문 보기', style: theme.textTheme.bodyMedium),
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(right: 8, bottom: 8),
                    child: SelectableText(
                      link.text,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Picks a posting from saved 채용공고 분석 results: a 공고 1개 비교, or one posting of a
/// 공고 찾기. Returns null when closed.
Future<PostingLink?> showSavedPostingPicker(
  BuildContext context,
  StudentApi api,
) => showDialog<PostingLink>(
  context: context,
  builder: (context) => _SavedPostingPicker(api: api),
);

class _SavedPostingPicker extends StatefulWidget {
  const _SavedPostingPicker({required this.api});
  final StudentApi api;

  @override
  State<_SavedPostingPicker> createState() => _SavedPostingPickerState();
}

class _SavedPostingPickerState extends State<_SavedPostingPicker> {
  late final _results = AnalysisResultsApi(widget.api.api);
  late Future<List<SavedAnalysisSummary>> _saved = _load();
  SavedAnalysisSummary? _search;
  List<RankedPosting>? _postings;
  DateTime? _searchedAt;
  bool _opening = false;
  String? _error;

  Future<List<SavedAnalysisSummary>> _load() async {
    final lists = await Future.wait([
      _results.list(AnalysisKind.posting),
      _results.list(AnalysisKind.search),
    ]);
    return [...lists[0], ...lists[1]]..sort(
      (a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );
  }

  Future<void> _open(SavedAnalysisSummary item) async {
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final saved = await _results.get(item.id);
      if (!mounted) return;
      if (item.kind == AnalysisKind.posting.value) {
        Navigator.of(context).pop(
          PostingLink.fromJobAnalysis(
            saved.input['posting_text'] as String? ?? '',
            JobAnalysisResponse.fromJson(saved.result),
            analyzedAt: saved.createdAt,
          ),
        );
        return;
      }
      final postings = rankPostings(
        JobRecommendationResponse.fromJson(saved.result),
      );
      setState(() {
        _search = item;
        _searchedAt = saved.createdAt;
        _postings = postings;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is AuthFailure ? e.message : '저장된 분석을 열지 못했습니다.',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screen = MediaQuery.sizeOf(context);
    final postings = _postings;
    return Dialog(
      key: const ValueKey('posting-picker'),
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: math.min(screen.width - 48, 760),
        height: math.min(screen.height - 48, 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                children: [
                  if (postings != null)
                    IconButton(
                      tooltip: '저장된 분석 목록',
                      onPressed: () => setState(() {
                        _postings = null;
                        _search = null;
                      }),
                      icon: const Icon(Icons.arrow_back),
                    )
                  else
                    const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      postings == null
                          ? '저장된 분석에서 공고 고르기'
                          : _search?.title ?? '공고 찾기',
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (_opening) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: postings == null
                  ? _savedList(context)
                  : _postingList(context, postings),
            ),
          ],
        ),
      ),
    );
  }

  Widget _savedList(BuildContext context) =>
      FutureBuilder<List<SavedAnalysisSummary>>(
        future: _saved,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _centered(
              context,
              '저장된 분석을 읽지 못했습니다.',
              action: TextButton(
                onPressed: () => setState(() => _saved = _load()),
                child: const Text('다시 시도'),
              ),
            );
          }
          final items = snapshot.data;
          if (items == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (items.isEmpty) {
            return _centered(
              context,
              '저장된 공고 분석이 없습니다. 채용공고 분석에서 공고 1개 비교나 공고 찾기를 먼저 실행하세요.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, i) {
              final item = items[i];
              final single = item.kind == AnalysisKind.posting.value;
              return ListTile(
                key: ValueKey('posting-picker-saved-${item.id}'),
                enabled: !_opening,
                leading: Icon(
                  single ? Icons.description_outlined : Icons.travel_explore,
                ),
                title: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    single ? '공고 1개 비교' : '공고 찾기',
                    ?item.fact,
                    savedAnalysisTime(item.createdAt),
                  ].join(' · '),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.favorite)
                      Icon(
                        Icons.star,
                        size: 18,
                        color: AppTone.warning.color(context),
                      ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => _open(item),
              );
            },
          );
        },
      );

  Widget _postingList(BuildContext context, List<RankedPosting> postings) {
    if (postings.isEmpty) {
      return _centered(context, '이 검색 결과에는 공고가 없습니다.');
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: postings.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
      itemBuilder: (context, i) {
        final entry = postings[i];
        final posting = entry.posting;
        final (ready, total) = entry.required;
        return ListTile(
          key: ValueKey('posting-picker-posting-${posting.key}'),
          title: Text(posting.title, maxLines: 2),
          subtitle: Text(
            [
              posting.company,
              if (entry.comparisons.isNotEmpty)
                '준비 ${entry.comparisons.where((c) => c.status == 'supported').length} / ${entry.comparisons.length}'
                    '${total == 0 ? '' : ' · 필수 $ready / $total'}',
              if (posting.textScope == 'metadata_only') '본문 없음',
            ].join(' · '),
          ),
          trailing: ToneChip(
            label: entry.verdict.label,
            tone: entry.verdict.tone,
          ),
          onTap: () =>
              Navigator.of(context)
                  .pop(PostingLink.fromRanked(entry, analyzedAt: _searchedAt)),
        );
      },
    );
  }

  Widget _centered(BuildContext context, String text, {Widget? action}) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, textAlign: TextAlign.center),
              ?action,
            ],
          ),
        ),
      );
}
