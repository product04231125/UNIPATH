import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../shared/widgets/surface_card.dart';
import 'career_gap.dart';

/// 홈 card: the latest 목표 직무 분석 on this device and what to prepare first.
class CareerGapSummaryCard extends StatelessWidget {
  const CareerGapSummaryCard({
    super.key,
    required this.report,
    required this.onOpen,
  });

  final ValueListenable<GapReport?> report;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<GapReport?>(
    valueListenable: report,
    builder: (context, value, _) {
      final theme = Theme.of(context);
      final gaps = [
        for (final r in value?.requirements ?? const <GapRequirement>[])
          if (r.status != 'supported') r,
      ];
      final when = value?.generatedAt?.toLocal();
      return SurfaceCard(
        key: const ValueKey('home-card-목표 직무 분석'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('목표 직무 분석', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (value == null)
              const Text('목표 직무 공고들이 공통으로 요구하는 조건과 내 기록을 비교하고 준비 계획을 받아 보세요.')
            else ...[
              Text(
                [
                  if (value.goalSummary.isNotEmpty) value.goalSummary,
                  '공고 ${value.postings.length}건 기준',
                  if (when != null) '${when.month}월 ${when.day}일 분석',
                ].join(' · '),
              ),
              Text(
                '요건 ${value.requirements.length}개 중 준비됨 ${value.count('supported')} · '
                '일부 ${value.count('partially_supported')} · '
                '준비 필요 ${value.count('insufficient_evidence')}',
              ),
              if (gaps.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('먼저 준비할 조건'),
                for (final gap in gaps.take(3))
                  Text(
                    '· ${gap.requirement} (공고 ${value.postings.length}건 중 ${gap.frequency}건)',
                  ),
              ],
            ],
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonal(
                key: const ValueKey('home-open-career-gap'),
                onPressed: onOpen,
                child: Text(value == null ? '목표 직무 분석하기' : '자세히 보기'),
              ),
            ),
          ],
        ),
      );
    },
  );
}
