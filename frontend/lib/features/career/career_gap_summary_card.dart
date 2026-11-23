import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../shared/app_tones.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/widgets/tone_chip.dart';
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
      final muted = theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      );
      final when = value?.generatedAt?.toLocal();
      return SurfaceCard(
        key: const ValueKey('home-card-목표 직무 분석'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const IconBadge(
                  icon: Icons.insights_outlined,
                  tone: AppTone.info,
                  size: 36,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('준비도', style: theme.textTheme.titleMedium),
                ),
                if (value != null)
                  Text(
                    [
                      '공고 ${value.postings.length}건',
                      if (when != null) '${when.month}.${when.day} 분석',
                    ].join(' · '),
                    style: muted,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (value == null)
              Text('목표 직무 공고들이 요구하는 조건과 내 기록을 비교합니다.', style: muted)
            else
              _Readiness(report: value),
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: value == null
                  ? FilledButton.icon(
                      key: const ValueKey('home-open-career-gap'),
                      onPressed: onOpen,
                      icon: const Icon(Icons.insights_outlined),
                      label: const Text('목표 직무 분석하기'),
                    )
                  : OutlinedButton(
                      key: const ValueKey('home-open-career-gap'),
                      onPressed: onOpen,
                      child: const Text('자세히 보기'),
                    ),
            ),
          ],
        ),
      );
    },
  );
}

class _Readiness extends StatelessWidget {
  const _Readiness({required this.report});
  final GapReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = report.requirements.length;
    final ready = report.count('supported');
    final partial = report.count('partially_supported');
    final missing = report.count('insufficient_evidence');
    // Missing evidence before partial, then the most requested first.
    final gaps =
        [
          for (final r in report.requirements)
            if (r.status != 'supported') r,
        ]..sort((a, b) {
          final byStatus = (a.status == 'partially_supported' ? 1 : 0)
              .compareTo(b.status == 'partially_supported' ? 1 : 0);
          return byStatus != 0 ? byStatus : b.frequency.compareTo(a.frequency);
        });
    final segments = [
      (ready, AppTone.success),
      (partial, AppTone.warning),
      (missing, AppTone.danger),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$ready',
                style: theme.textTheme.headlineSmall?.copyWith(fontSize: 28),
              ),
              TextSpan(
                text: ' / $total 요건 준비됨',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 8,
            child: total == 0
                ? ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const SizedBox.expand(),
                  )
                : Row(
                    children: [
                      for (final (count, tone) in segments)
                        if (count > 0)
                          Expanded(
                            flex: count,
                            child: ColoredBox(
                              color: tone.color(context),
                              child: const SizedBox.expand(),
                            ),
                          ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '요건 $total개 중 준비됨 $ready · 일부 $partial · 준비 필요 $missing',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (gaps.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('먼저 준비할 조건', style: theme.textTheme.labelMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final gap in gaps.take(3))
                Tooltip(
                  message:
                      '공고 ${report.postings.length}건 중 ${gap.frequency}건이 요구',
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: ToneChip(
                      label: gap.requirement,
                      tone: gap.status == 'partially_supported'
                          ? AppTone.warning
                          : AppTone.danger,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
