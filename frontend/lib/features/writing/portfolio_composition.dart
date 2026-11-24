import 'package:flutter/material.dart';

import '../../shared/app_tones.dart';
import '../../shared/widgets/tone_chip.dart';
import '../api/student_api.dart';
import '../assistant/ai_record_catalog.dart';
import '../auth/auth_api.dart';
import '../career/career_gap.dart';
import '../career/saved_analyses.dart';

/// One target-job requirement and the student's records that show it.
class CompositionGroup {
  const CompositionGroup({
    required this.requirement,
    required this.records,
    this.frequency,
    this.postings,
  });
  final String requirement;
  final List<AiRecordOption> records;

  /// How many analysed postings asked for it, when known.
  final int? frequency, postings;

  CompositionGroup withRecords(List<AiRecordOption> value) => CompositionGroup(
    requirement: requirement,
    records: value,
    frequency: frequency,
    postings: postings,
  );

  Map<String, Object?> toJson() => {
    'requirement': requirement,
    'records': [
      for (final r in records) {'kind': r.kind, 'record_id': r.id},
    ],
  };
}

const maxCompositionGroups = 12, maxGroupRecords = 10;

/// 포트폴리오 구성 from a 목표 직무 분석: requirements most postings asked for first, each with the
/// saved records cited as its evidence. Requirements without such records are left out.
List<CompositionGroup> composeFromGap(
  GapReport report,
  List<AiRecordOption> records,
) {
  final byId = {for (final r in records) r.id: r};
  final ordered = [...report.requirements]
    ..sort((a, b) {
      final byFrequency = b.frequency.compareTo(a.frequency);
      if (byFrequency != 0) return byFrequency;
      int rank(String status) => switch (status) {
        'supported' => 0,
        'partially_supported' => 1,
        _ => 2,
      };
      return rank(a.status).compareTo(rank(b.status));
    });
  final groups = <CompositionGroup>[];
  for (final requirement in ordered) {
    final shown = <AiRecordOption>[];
    for (final evidence in requirement.evidence) {
      final record = byId[evidence.recordId];
      if (record != null && !shown.contains(record)) shown.add(record);
    }
    if (shown.isEmpty) continue;
    groups.add(
      CompositionGroup(
        requirement: requirement.requirement,
        records: shown.take(maxGroupRecords).toList(),
        frequency: requirement.frequency,
        postings: report.postings.length,
      ),
    );
    if (groups.length == maxCompositionGroups) break;
  }
  return groups;
}

/// Builds and edits a 포트폴리오 구성 from the latest saved 목표 직무 분석.
class PortfolioCompositionCard extends StatefulWidget {
  const PortfolioCompositionCard({
    super.key,
    required this.api,
    required this.groups,
    required this.onChanged,
    this.loadRecords,
    this.enabled = true,
  });
  final StudentApi api;
  final List<CompositionGroup> groups;
  final ValueChanged<List<CompositionGroup>> onChanged;
  final Future<List<AiRecordOption>> Function()? loadRecords;
  final bool enabled;

  @override
  State<PortfolioCompositionCard> createState() =>
      _PortfolioCompositionCardState();
}

class _PortfolioCompositionCardState extends State<PortfolioCompositionCard> {
  bool _loading = false;
  String? _message;
  DateTime? _analyzedAt;

  Future<void> _compose() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final results = AnalysisResultsApi(widget.api.api);
      final saved = await results.list(AnalysisKind.gap);
      final latest = [...saved]
        ..sort(
          (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
            a.createdAt ?? DateTime(0),
          ),
        );
      if (latest.isEmpty) {
        setState(
          () =>
              _message = '저장된 목표 직무 분석이 없습니다. 채용공고 분석에서 목표 직무 분석을 먼저 실행해 주세요.',
        );
        return;
      }
      final report = GapReport.fromJson(
        (await results.get(latest.first.id)).result,
      );
      final records =
          await (widget.loadRecords?.call() ?? loadAiRecords(widget.api));
      if (!mounted) return;
      final groups = composeFromGap(report, records);
      _analyzedAt = latest.first.createdAt;
      if (groups.isEmpty) {
        setState(
          () => _message =
              '목표 직무 분석에서 내 기록이 근거로 쓰인 요건이 없습니다. 기록을 더 추가한 뒤 다시 분석해 보세요.',
        );
      }
      widget.onChanged(groups);
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _message = e is AuthFailure ? e.message : '포트폴리오 구성을 만들지 못했습니다.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle(int group, AiRecordOption record, bool on) {
    final groups = [...widget.groups];
    final current = groups[group].records;
    groups[group] = groups[group].withRecords(
      on ? [...current, record] : current.where((r) => r != record).toList(),
    );
    widget.onChanged(groups.where((g) => g.records.isNotEmpty).toList());
  }

  void _move(int index, int by) {
    final groups = [...widget.groups];
    final item = groups.removeAt(index);
    groups.insert((index + by).clamp(0, groups.length), item);
    widget.onChanged(groups);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final groups = widget.groups;
    return Container(
      key: const ValueKey('portfolio-composition'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('포트폴리오 구성 (선택)', style: theme.textTheme.titleSmall),
              ),
              if (groups.isNotEmpty)
                TextButton(
                  key: const ValueKey('portfolio-composition-clear'),
                  onPressed: widget.enabled
                      ? () => widget.onChanged(const [])
                      : null,
                  child: const Text('구성 지우기'),
                ),
              TextButton.icon(
                key: const ValueKey('portfolio-composition-build'),
                onPressed: widget.enabled && !_loading ? _compose : null,
                icon: const Icon(Icons.account_tree_outlined, size: 18),
                label: Text(groups.isEmpty ? '목표 직무 요건 순으로 구성' : '다시 구성'),
              ),
            ],
          ),
          Text(
            '최근 목표 직무 분석에서 공고가 자주 요구한 요건부터, 그 요건의 근거가 된 내 기록을 묶습니다. 구성하면 초안이 이 순서로 프로젝트를 소개합니다.',
            style: muted,
          ),
          if (_loading) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(_message!, style: muted),
          ],
          if (groups.isNotEmpty) ...[
            if (_analyzedAt != null) ...[
              const SizedBox(height: 6),
              Text(
                '목표 직무 분석 · ${savedAnalysisTime(_analyzedAt)} 기준',
                style: muted,
              ),
            ],
            for (final (i, group) in groups.indexed)
              Padding(
                key: ValueKey('portfolio-group-$i'),
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ToneChip(label: '${i + 1}', tone: AppTone.accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            group.requirement,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (group.frequency != null &&
                            (group.postings ?? 0) > 0)
                          ToneChip(
                            label:
                                '공고 ${group.postings}건 중 ${group.frequency}건',
                          ),
                        IconButton(
                          tooltip: '위로',
                          visualDensity: VisualDensity.compact,
                          onPressed: widget.enabled && i > 0
                              ? () => _move(i, -1)
                              : null,
                          icon: const Icon(Icons.arrow_upward, size: 18),
                        ),
                        IconButton(
                          tooltip: '아래로',
                          visualDensity: VisualDensity.compact,
                          onPressed: widget.enabled && i < groups.length - 1
                              ? () => _move(i, 1)
                              : null,
                          icon: const Icon(Icons.arrow_downward, size: 18),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final record in group.records)
                          FilterChip(
                            key: ValueKey('portfolio-record-$i-${record.id}'),
                            selected: true,
                            label: Text(
                              '${record.kindLabel} · ${record.title}',
                            ),
                            onSelected: widget.enabled
                                ? (on) => _toggle(i, record, on)
                                : null,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
