import 'package:flutter/material.dart';

import '../../../shared/app_tones.dart';
import '../../../shared/widgets/external_link_button.dart';
import '../../../shared/widgets/responsive_grid.dart';
import '../../../shared/widgets/tone_chip.dart';
import '../../../shared/widgets/work_layout.dart';
import '../../career/requirement_result.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../api/job_recommendation_api.dart';
import '../../assistant/ai_record_catalog.dart';
import '../../planning/planning_dates.dart';
import '../../writing/posting_link.dart';
import '../../writing/writing_api.dart';

Widget _surface({required Widget child}) => SurfaceCard(
  child: Material(type: MaterialType.transparency, child: child),
);

String recommendationStateLabel(String state) => switch (state) {
  'completed' => '비교 완료',
  'partial' => '일부 수집처에서 검색 완료',
  'not_configured' => '설정 필요',
  'failed' => '처리 실패',
  'skipped' => '시간 제한으로 생략',
  'budget_exhausted' => '이번 요청의 분석 한도 도달',
  'insufficient_evidence' => '비교 근거 부족',
  'personal_analysis_not_authorized' => '자료 비교 동의 필요',
  _ => '상태 확인 필요',
};

/// Server failure codes in plain words; the code stays visible for support.
String recommendationFailureLabel(String code) {
  final text = switch (code) {
    'posting_quote' => 'AI가 공고 문장을 정확히 인용하지 못했습니다.',
    'personal_citation' => 'AI가 선택한 자료를 정확히 인용하지 못했습니다.',
    'classification' || 'output_shape' => 'AI 응답 형식이 맞지 않았습니다.',
    'model_timeout' || 'timeout' => '응답 시간이 초과되었습니다.',
    'model_busy' => 'AI 요청이 몰려 있습니다.',
    'model_http_429' => 'AI 호출 한도에 도달했습니다.',
    'model_invalid_json' || 'model_no_candidate' => 'AI 응답을 읽지 못했습니다.',
    'network' => '공고 수집처에 연결하지 못했습니다.',
    _ when code.startsWith('output_missing_') => 'AI 응답 형식이 맞지 않았습니다.',
    _ when code.startsWith('model_incomplete_') => 'AI 응답이 중간에 끝났습니다.',
    _ when code.startsWith('model_') => 'AI 서버 호출에 실패했습니다.',
    _ when code.startsWith('http_') => '공고 수집처가 오류를 반환했습니다.',
    _ => '처리 중 문제가 생겼습니다.',
  };
  return '$text 잠시 후 다시 시도해 주세요. (코드: $code)';
}

String _sourceName(String value) => switch (value) {
  'saramin' => '사람인',
  'work24' => '고용24',
  'greenhouse' => 'Greenhouse',
  'jobkorea' => '잡코리아',
  _ => value,
};

/// Posting deadline as a Korean date, e.g. `마감 11월 30일(일)`.
///
/// Korean postings close in Korea time, so an `expires_at` with an offset is shown in KST
/// whatever the device time zone. A deadline at the end of the day (23:59) or with no time
/// shows the date only; the year appears only when it differs from [now]. Without a date the
/// posting's own closing text (`채용시까지`, `확인 필요`) is shown as is.
String postingDeadlineLabel(RecommendationPosting posting, {DateTime? now}) {
  final value = posting.expiresAt;
  if (value == null) return '마감 ${posting.closingLabel}';
  final at = value.isUtc ? value.add(const Duration(hours: 9)) : value;
  final today = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 9));
  final year = at.year == today.year ? '' : '${at.year}년 ';
  final dateOnly =
      (at.hour == 23 && at.minute == 59) || (at.hour == 0 && at.minute == 0);
  final time = dateOnly ? '' : ' ${planningTime(at)}';
  return '마감 $year${at.month}월 ${at.day}일(${weekdayLabel(at.weekday)})$time';
}

/// How one compared posting stands against the recommendation rule: a ready
/// requirement, and at least one ready 필수 requirement when it has any.
enum PostingVerdict {
  recommended('추천', AppTone.success),
  closest('조건 확인 필요', AppTone.warning),
  requiredMissing('필수 요건 미충족', AppTone.danger),
  noEvidence('준비된 요건 없음', AppTone.danger),
  unavailable('분석 미완료', AppTone.neutral);

  const PostingVerdict(this.label, this.tone);
  final String label;
  final AppTone tone;
}

/// One posting in the single ranked list, with everything its card shows.
class RankedPosting {
  RankedPosting({
    required this.posting,
    required this.verdict,
    required this.reason,
    this.item,
    this.recommendation,
    this.candidate,
  });
  final RecommendationPosting posting;
  final RecommendationItem? item;
  final RecommendedJob? recommendation;
  final RecommendationDisplayCandidate? candidate;
  final PostingVerdict verdict;
  final String reason;

  List<RecommendationComparison> get comparisons =>
      item?.comparisons ?? const [];
  List<RequirementStatus> get statuses => [
    for (final c in comparisons) RequirementStatus.parse(c.status),
  ];
  (int, int) get required {
    final rows = comparisons.where((c) => c.priority == 'required');
    return (rows.where((c) => c.status == 'supported').length, rows.length);
  }
}

/// Every compared posting in one list: recommended ones in the server's order
/// (fewest unconfirmed 필수 first), then the closest candidate, then the rest
/// by how near they are, and postings without a finished analysis last.
List<RankedPosting> rankPostings(JobRecommendationResponse result) {
  final recommendations = {for (final r in result.recommendations) r.key: r};
  final candidates = {
    for (final c
        in result.displayCandidates ?? const <RecommendationDisplayCandidate>[])
      c.posting.key: c,
  };
  final items = {for (final i in result.items) i.posting.key: i};
  final keys = <String>[
    ...result.items.map((i) => i.posting.key),
    for (final key in candidates.keys)
      if (!items.containsKey(key)) key,
  ];
  RankedPosting entry(String key) {
    final item = items[key];
    final candidate = candidates[key];
    final recommendation = recommendations[key];
    final posting = item?.posting ?? candidate!.posting;
    final status = item?.status ?? candidate?.status;
    final comparisons = item?.comparisons ?? const <RecommendationComparison>[];
    final required = comparisons.where((c) => c.priority == 'required');
    final requiredReady = required.where((c) => c.status == 'supported').length;
    final ready = comparisons.where((c) => c.status == 'supported').length;
    // The server's candidate type decides first; otherwise the comparisons do.
    final type =
        candidate?.type ??
        recommendation?.type ??
        (recommendation != null ? 'evidence_match' : null);
    final (verdict, reason) = switch (type) {
      'evidence_match' => (
        PostingVerdict.recommended,
        required.isEmpty
            ? '준비된 요건이 $ready개 있어 추천했습니다.'
            : '필수 요건 ${required.length}개 중 $requiredReady개가 준비되어 추천했습니다.',
      ),
      'closest_needs_review' => (
        PostingVerdict.closest,
        '추천 기준에는 못 미치지만 비교한 공고 중 가장 가깝습니다. 지원 조건을 직접 확인하세요.',
      ),
      _ when type == 'analysis_unavailable' || status != 'completed' => (
        PostingVerdict.unavailable,
        item?.failureReason != null
            ? recommendationFailureLabel(item!.failureReason!)
            : '${recommendationStateLabel(status ?? '')} · 역량 부족으로 해석하지 마세요.',
      ),
      _ when ready == 0 => (
        PostingVerdict.noEvidence,
        '준비된 요건이 없어 추천에서 제외했습니다.',
      ),
      _ when required.isNotEmpty && requiredReady == 0 => (
        PostingVerdict.requiredMissing,
        '필수 요건 ${required.length}개 중 준비된 것이 없어 추천에서 제외했습니다.',
      ),
      _ => (PostingVerdict.closest, '추천 기준에 가깝습니다. 지원 조건을 직접 확인하세요.'),
    };
    return RankedPosting(
      posting: posting,
      item: item,
      recommendation: recommendation,
      candidate: candidate,
      verdict: verdict,
      reason: reason,
    );
  }

  final all = [for (final key in keys) entry(key)];
  final order = [for (final r in result.recommendations) r.key];
  int score(RankedPosting p) {
    final (ready, total) = p.required;
    final supported = p.statuses
        .where((s) => s == RequirementStatus.supported)
        .length;
    // Fewer unconfirmed 필수, then more ready requirements.
    return (total - ready) * 100 - supported;
  }

  int group(RankedPosting p) => switch (p.verdict) {
    PostingVerdict.recommended => 0,
    PostingVerdict.closest => 1,
    PostingVerdict.requiredMissing || PostingVerdict.noEvidence => 2,
    PostingVerdict.unavailable => 3,
  };
  all.sort((a, b) {
    final byGroup = group(a).compareTo(group(b));
    if (byGroup != 0) return byGroup;
    if (a.verdict == PostingVerdict.recommended) {
      return order
          .indexOf(a.posting.key)
          .compareTo(order.indexOf(b.posting.key));
    }
    return score(a).compareTo(score(b));
  });
  return all;
}

class JobRecommendationResult extends StatelessWidget {
  const JobRecommendationResult({
    super.key,
    required this.result,
    this.selectedRecords = const [],
    this.onBrowseCategory,
    this.titleTrailing,
    this.openedNote,
    this.onWrite,
    this.analyzedAt,
  });
  final JobRecommendationResponse result;
  final List<AiRecordOption> selectedRecords;

  /// Beside the title, e.g. the star that keeps a saved result.
  final Widget? titleTrailing;

  /// When a saved result is shown again: `저장된 결과 · 11월 24일 02:13 분석`.
  final String? openedNote;

  /// Search the same category again without detail words (shown after a 0-match search).
  final VoidCallback? onBrowseCategory;

  /// Opens 자기소개서·포트폴리오 for one posting; [analyzedAt] is when this result was made.
  final WriteForPosting? onWrite;
  final DateTime? analyzedAt;

  Widget _comparison(RecommendationComparison c) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: RequirementCard(
      requirement: c.requirement,
      status: RequirementStatus.parse(c.status),
      explanation: c.explanation,
      chips: [
        ToneChip(
          label: c.priority == 'required'
              ? '필수'
              : c.priority == 'preferred'
              ? '우대'
              : '구분 확인 필요',
          tone: c.priority == 'required' ? AppTone.accent : AppTone.info,
        ),
      ],
      evidence: [
        for (final cite in c.evidence) ...[
          _citationLabel(cite),
          if (result.locations[cite.id]?.method == 'ocr') '자동 문자 인식 · 원본 확인',
          cite.excerpt,
        ],
      ],
      postingEvidence: ['공고 근거: ${c.postingExcerpt}'],
    ),
  );

  String _citationLabel(RecommendationCitation cite) {
    final location = result.locations[cite.id];
    if (location != null) {
      return '내 자료: ${location.filename} · ${location.location}';
    }
    final matches = selectedRecords.where(
      (r) =>
          r.kind == cite.kind && r.id == cite.id && r.version == cite.version,
    );
    if (matches.isNotEmpty) {
      return '내 기록: ${matches.first.title} · ${matches.first.kindLabel} · 버전 ${cite.version}';
    }
    return '내 기록: ${cite.kind} · ${cite.id} · 버전 ${cite.version}';
  }

  Widget _posting(BuildContext context, RankedPosting entry, int rank) {
    final posting = entry.posting;
    final item = entry.item;
    final recommendation = entry.recommendation;
    final evidence =
        entry.verdict == PostingVerdict.recommended &&
            recommendation?.hasVerifiedEvidence == true
        ? recommendation
        : null;
    final candidate = entry.candidate;
    final guidance = candidate != null && candidate.guidanceSentences.isNotEmpty
        ? candidate.guidanceSentences
        : item?.guidanceSentences ?? const <String>[];
    final theme = Theme.of(context);
    final verdict = entry.verdict;
    return _surface(
      child: Column(
        key: ValueKey('recommend-posting-${posting.key}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: verdict.tone.container(context),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$rank',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: verdict.tone.color(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ToneChip(
                key: ValueKey('recommend-verdict-${posting.key}'),
                label: verdict.label,
                tone: verdict.tone,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            posting.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${posting.company} · ${posting.location}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (entry.comparisons.isNotEmpty) ...[
            const SizedBox(height: 12),
            ReadinessBar(statuses: entry.statuses, required: entry.required),
          ],
          const SizedBox(height: 10),
          NoteLine(
            icon: switch (verdict) {
              PostingVerdict.recommended => Icons.check_circle_outline,
              PostingVerdict.unavailable => Icons.hourglass_empty,
              _ => Icons.info_outline,
            },
            text: entry.reason,
            color: verdict == PostingVerdict.unavailable
                ? null
                : verdict.tone.color(context),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ToneChip(
                label:
                    '${_sourceName(posting.source)} · ${postingDeadlineLabel(posting)}',
                icon: Icons.event_outlined,
              ),
              if (item != null && verdict != PostingVerdict.unavailable)
                ToneChip(
                  label:
                      '비교 범위: ${switch (item.scope) {
                        'metadata_only' => '공고 요약 정보',
                        'excerpt' => '공고 본문 일부',
                        'full_text' => '공고 본문 전체',
                        _ => '확인 필요',
                      }}',
                ),
            ],
          ),
          if (item != null)
            for (final warning in item.warnings) ...[
              const SizedBox(height: 6),
              NoteLine(icon: Icons.warning_amber_outlined, text: warning),
            ],
          if (guidance.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTone.accent.container(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 18,
                    color: AppTone.accent.color(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '준비 안내',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppTone.accent.color(context),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        for (final sentence in guidance)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              sentence,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ExternalLinkButton(
                url: posting.url,
                label: '원 공고',
                description: '최신 모집 조건과 마감은 원 공고에서 확인하세요.',
              ),
              // The two 쓰기 buttons wrap to the next line together.
              if (onWrite case final write?)
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final type in WritingType.values)
                      TextButton.icon(
                        key: ValueKey(
                          'recommend-write-${type.value}-${posting.key}',
                        ),
                        onPressed: () => write(
                          PostingLink.fromRanked(entry, analyzedAt: analyzedAt),
                          type,
                        ),
                        icon: Icon(
                          type == WritingType.coverLetter
                              ? Icons.edit_note_outlined
                              : Icons.folder_open_outlined,
                        ),
                        label: Text('${type.label} 쓰기'),
                      ),
                  ],
                ),
            ],
          ),
          if (evidence != null && evidence.matched.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('왜 추천됐나요?'),
              children: [for (final c in evidence.matched) _comparison(c)],
            ),
          if (item != null &&
              (verdict != PostingVerdict.unavailable ||
                  item.comparisons.isNotEmpty))
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('전체 요건과 비교 근거'),
              children: [
                if (item.comparisons.isEmpty)
                  const Text('비교 결과가 없습니다. 위 분석 상태를 확인하세요.'),
                for (final c in item.comparisons) _comparison(c),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ranked = rankPostings(result);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final recommended = ranked
        .where((p) => p.verdict == PostingVerdict.recommended)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('공고 비교 결과', style: theme.textTheme.titleMedium),
                  ?titleTrailing,
                ],
              ),
              if (openedNote != null) ...[
                const SizedBox(height: 4),
                NoteLine(
                  key: const ValueKey('recommend-opened'),
                  icon: Icons.history,
                  text: openedNote!,
                ),
              ],
              const SizedBox(height: 6),
              Semantics(
                liveRegion: true,
                child: Text(switch (result.status) {
                  'completed' => '공고 검색 완료 · 아래에서 공고별 비교 상태를 확인하세요.',
                  'needs_user_input' =>
                    result.missingFields.contains('external_processing_consent')
                        ? '외부 처리 동의가 필요합니다. 입력을 유지했습니다. 다시 실행해 동의를 확인하세요.'
                        : '비교할 파일 또는 저장 기록을 선택하세요.',
                  'not_configured' => '공고 추천 기능 준비 중입니다. 서버 분석 설정이 필요합니다.',
                  'no_results' => '검색한 수집처에서 조건에 맞는 공고가 없습니다.',
                  'not_available' => '공고를 가져온 수집처가 없습니다. 아래 수집처 상태를 확인하세요.',
                  _ => recommendationStateLabel(result.status),
                }),
              ),
              if (result.notice.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(result.notice, style: muted),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (result.occupationLabel case final label?
                      when label.isNotEmpty)
                    ToneChip(
                      label: result.queryKeyword?.isEmpty ?? false
                          ? '검색 직종 · $label · 세부 검색어 없음'
                          : '검색 직종 · $label',
                      icon: Icons.work_outline,
                      tone: AppTone.accent,
                    ),
                  if (result.regionLabel case final label?
                      when label.isNotEmpty)
                    ToneChip(
                      key: const ValueKey('recommend-region-chip'),
                      label: '근무 지역 · $label',
                      icon: Icons.place_outlined,
                      tone: AppTone.accent,
                    ),
                  for (final source in result.sources)
                    ToneChip(
                      label:
                          '${_sourceName(source.source)} · ${switch ((source.status, source.reason)) {
                            ('completed', _) => '검색 완료',
                            ('skipped', 'category_unsupported') => '직종 검색 미지원',
                            ('skipped', 'region_unsupported') => '지역 검색 미지원',
                            _ => recommendationStateLabel(source.status),
                          }}',
                      tone: switch (source.status) {
                        'completed' => AppTone.success,
                        'failed' => AppTone.danger,
                        _ => AppTone.neutral,
                      },
                      dot: true,
                    ),
                ],
              ),
              for (final source in result.sources)
                if (source.status == 'failed' && source.failureReason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: NoteLine(
                      icon: Icons.error_outline,
                      text: recommendationFailureLabel(source.failureReason!),
                    ),
                  ),
              if (result.searchNotice case final notice?
                  when notice.isNotEmpty) ...[
                const SizedBox(height: 8),
                NoteLine(icon: Icons.info_outline, text: notice),
              ],
              for (final warning in result.warnings) ...[
                const SizedBox(height: 6),
                NoteLine(icon: Icons.warning_amber_outlined, text: warning),
              ],
              if (result.categoryBrowseAvailable &&
                  onBrowseCategory != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton(
                    key: const ValueKey('recommend-browse-category'),
                    onPressed: onBrowseCategory,
                    child: const Text('직종 전체 보기'),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (ranked.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Text('비교한 공고', style: theme.textTheme.titleMedium),
              const SizedBox(width: 8),
              ToneChip(label: '${ranked.length}건'),
              const SizedBox(width: 6),
              if (recommended > 0)
                ToneChip(label: '추천 $recommended', tone: AppTone.success),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '추천 기준: 준비된 요건이 있고, 필수 요건 중 하나 이상이 준비됨. '
            '기준을 만족한 공고부터 보여 줍니다.',
            style: muted,
          ),
          const SizedBox(height: 12),
          ResponsiveGrid(
            targetItemWidth: 440,
            minItemWidth: 340,
            maxColumns: 3,
            minHeightFactor: 0,
            children: [
              for (final (index, entry) in ranked.indexed)
                _posting(context, entry, index + 1),
            ],
          ),
        ],
      ],
    );
  }
}
