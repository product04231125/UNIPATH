import 'package:flutter/material.dart';

import '../../../shared/widgets/external_link_button.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../api/job_recommendation_api.dart';
import '../../assistant/ai_record_catalog.dart';

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

class JobRecommendationResult extends StatelessWidget {
  const JobRecommendationResult({
    super.key,
    required this.result,
    this.selectedRecords = const [],
  });
  final JobRecommendationResponse result;
  final List<AiRecordOption> selectedRecords;

  Widget _comparison(RecommendationComparison c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${c.priority == 'required'
              ? '필수'
              : c.priority == 'preferred'
              ? '우대'
              : '구분 확인 필요'} · ${c.requirement}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        SelectableText(c.explanation),
        const SizedBox(height: 8),
        SelectableText('공고 근거: ${c.postingExcerpt}'),
        for (final cite in c.evidence) ...[
          SelectableText(_citationLabel(cite)),
          if (result.locations[cite.id]?.method == 'ocr')
            const Text('자동 문자 인식 · 원본 확인'),
          SelectableText(cite.excerpt),
        ],
      ],
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

  Widget _posting(
    BuildContext context,
    RecommendationPosting posting, {
    RecommendationItem? item,
    RecommendedJob? recommendation,
    RecommendationDisplayCandidate? candidate,
  }) {
    final type = candidate?.type ?? recommendation?.type;
    final badge = switch (type) {
      'evidence_match' => '근거가 확인된 후보',
      'closest_needs_review' => '조건 확인 필요',
      'analysis_unavailable' => '분석 미완료 · 검색 후보',
      null => null,
      _ => '후보 유형 확인 필요',
    };
    final evidence =
        (type == null || type == 'evidence_match') &&
            recommendation?.hasVerifiedEvidence == true
        ? recommendation
        : null;
    final status = candidate?.status ?? item?.status;
    final notice = candidate?.notice ?? recommendation?.notice;
    final guidance = candidate != null && candidate.guidanceSentences.isNotEmpty
        ? candidate.guidanceSentences
        : item?.guidanceSentences ?? const <String>[];
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (badge != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ),
            Text(posting.title, style: theme.textTheme.titleMedium),
            Text('${posting.company} · ${posting.location}'),
            Text('${_sourceName(posting.source)} · 마감 ${posting.closing}'),
            if (notice != null && notice.isNotEmpty) Text(notice),
            if (evidence != null) Text('미확인 필수조건 ${evidence.requiredToCheck}개'),
            if (item != null && type != 'analysis_unavailable')
              Text(
                '비교 범위: ${switch (item.scope) {
                  'metadata_only' => '공고 요약 정보',
                  'excerpt' => '공고 본문 일부',
                  'full_text' => '공고 본문 전체',
                  _ => '확인 필요',
                }}',
              ),
            if (status != null) Text(recommendationStateLabel(status)),
            if (status == 'failed' && item?.failureReason != null)
              Text(recommendationFailureLabel(item!.failureReason!)),
            if (item != null)
              for (final warning in item.warnings)
                if (warning != notice) Text(warning),
            if (guidance.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('준비 안내', style: theme.textTheme.titleSmall),
              for (final sentence in guidance) Text(sentence),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: ExternalLinkButton(
                url: posting.url,
                label: '원 공고',
                description: '최신 모집 조건과 마감은 원 공고에서 확인하세요.',
              ),
            ),
            if (evidence != null && evidence.matched.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('왜 추천됐나요?'),
                children: [for (final c in evidence.matched) _comparison(c)],
              ),
            if (item != null &&
                (type != 'analysis_unavailable' || item.comparisons.isNotEmpty))
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final candidates = result.displayCandidates;
    final recommendations = {
      for (final recommendation in result.recommendations)
        recommendation.key: recommendation,
    };
    final items = {for (final item in result.items) item.posting.key: item};
    final displayedKeys =
        candidates?.map((c) => c.posting.key).toSet() ??
        recommendations.keys.toSet();
    final remainingItems = result.items.where(
      (item) => !displayedKeys.contains(item.posting.key),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('공고 비교 결과', style: Theme.of(context).textTheme.titleLarge),
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
        if (result.notice.isNotEmpty) Text(result.notice),
        if (result.occupationLabel case final label? when label.isNotEmpty)
          Text('검색 직종 · $label'),
        if (result.searchNotice case final notice? when notice.isNotEmpty)
          Text(notice),
        for (final source in result.sources) ...[
          Text(
            '${_sourceName(source.source)} · ${switch ((source.status, source.reason)) {
              ('completed', _) => '검색 완료',
              ('skipped', 'category_unsupported') => '직종 검색 미지원',
              _ => recommendationStateLabel(source.status),
            }}',
          ),
          if (source.status == 'failed' && source.failureReason != null)
            Text(recommendationFailureLabel(source.failureReason!)),
        ],
        for (final warning in result.warnings) Text(warning),
        if (items.isNotEmpty && displayedKeys.isEmpty)
          const Text('추천 공고가 없습니다. 비교 대상의 분석 상태와 근거를 확인하세요.'),
        if (candidates != null)
          for (final candidate in candidates)
            _posting(
              context,
              candidate.posting,
              candidate: candidate,
              item: items[candidate.posting.key],
              recommendation: recommendations[candidate.posting.key],
            )
        else
          for (final recommendation in result.recommendations)
            if (items[recommendation.key] case final item?)
              _posting(
                context,
                item.posting,
                item: item,
                recommendation: recommendation,
              )
            else
              const Text('추천 공고의 상세 응답을 확인하지 못했습니다.'),
        if (remainingItems.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('함께 비교한 공고', style: Theme.of(context).textTheme.titleMedium),
          for (final item in remainingItems)
            _posting(context, item.posting, item: item),
        ],
      ],
    );
  }
}
