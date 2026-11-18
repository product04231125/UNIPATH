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
        Text(switch (c.status) {
          'supported' => '근거 있음',
          'partially_supported' => '일부 근거 있음',
          'insufficient_evidence' => '근거 부족',
          _ => '비교 상태 확인 필요',
        }),
        SelectableText('공고 근거: ${c.postingExcerpt}'),
        for (final cite in c.evidence) ...[
          SelectableText(_citationLabel(cite)),
          if (result.locations[cite.id]?.method == 'ocr')
            const Text('자동 문자 인식 · 원본 확인'),
          SelectableText(cite.excerpt),
        ],
        SelectableText(c.explanation),
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
    RecommendationItem item, {
    RecommendedJob? recommendation,
  }) {
    final posting = item.posting;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(posting.title, style: Theme.of(context).textTheme.titleMedium),
            Text('${posting.company} · ${posting.location}'),
            Text('${_sourceName(posting.source)} · 마감 ${posting.closing}'),
            if (recommendation != null)
              Text('미확인 필수조건 ${recommendation.requiredToCheck}개'),
            Text(
              '비교 범위: ${switch (item.scope) {
                'metadata_only' => '공고 요약 정보',
                'excerpt' => '공고 본문 일부',
                'full_text' => '공고 본문 전체',
                _ => '확인 필요',
              }}',
            ),
            Text(recommendationStateLabel(item.status)),
            if (item.status == 'failed' && item.failureReason != null)
              Text(recommendationFailureLabel(item.failureReason!)),
            for (final warning in item.warnings) Text(warning),
            Align(
              alignment: Alignment.centerLeft,
              child: ExternalLinkButton(
                url: posting.url,
                label: '원 공고',
                description: '최신 모집 조건과 마감은 원 공고에서 확인하세요.',
              ),
            ),
            if (recommendation != null)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('왜 추천됐나요?'),
                children: [
                  for (final c in recommendation.matched) _comparison(c),
                ],
              ),
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
    final recommendedKeys = result.recommendations.map((r) => r.key).toSet();
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
        for (final source in result.sources) ...[
          Text(
            '${_sourceName(source.source)} · ${source.status == 'completed' ? '검색 완료' : recommendationStateLabel(source.status)}',
          ),
          if (source.status == 'failed' && source.failureReason != null)
            Text(recommendationFailureLabel(source.failureReason!)),
        ],
        for (final warning in result.warnings) Text(warning),
        if (result.items.isNotEmpty && result.recommendations.isEmpty)
          const Text('추천 공고가 없습니다. 비교 대상의 분석 상태와 근거를 확인하세요.'),
        for (final recommendation in result.recommendations)
          if (result.items.any((i) => i.posting.key == recommendation.key))
            _posting(
              context,
              result.items.firstWhere(
                (i) => i.posting.key == recommendation.key,
              ),
              recommendation: recommendation,
            )
          else
            const Text('추천 공고의 상세 응답을 확인하지 못했습니다.'),
        if (result.items.any(
          (i) => !recommendedKeys.contains(i.posting.key),
        )) ...[
          const SizedBox(height: 16),
          Text('함께 비교한 공고', style: Theme.of(context).textTheme.titleMedium),
          for (final item in result.items.where(
            (i) => !recommendedKeys.contains(i.posting.key),
          ))
            _posting(context, item),
        ],
      ],
    );
  }
}
