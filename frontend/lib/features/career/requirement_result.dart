import 'package:flutter/material.dart';

import '../../shared/app_tones.dart';
import '../../shared/widgets/tone_chip.dart';

/// How far a requirement is covered by the student's records, shared by
/// 공고 1개 비교, 목표 직무 분석 and 공고 찾기.
enum RequirementStatus {
  supported('준비됨', Icons.check_circle_outline, AppTone.success),
  partial('일부 준비됨', Icons.timelapse, AppTone.warning),
  missing('준비 필요', Icons.error_outline, AppTone.danger);

  const RequirementStatus(this.label, this.icon, this.tone);
  final String label;
  final IconData icon;
  final AppTone tone;

  static RequirementStatus parse(String raw) => switch (raw) {
    'supported' => supported,
    'partially_supported' => partial,
    _ => missing,
  };

  /// Gaps first so the student sees what to work on.
  int get order => switch (this) {
    missing => 0,
    partial => 1,
    supported => 2,
  };
}

/// The model writes `직무 해석: … / 경험 활용: … / 다음 행동: …` lines.
/// Unlabelled text stays whole under [RequirementExplanation.body].
class RequirementExplanation {
  const RequirementExplanation({
    this.role = '',
    this.body = '',
    this.next = '',
  });

  /// 직무 해석: what the requirement means in this job.
  final String role;

  /// 경험 활용 (or the whole text when unlabelled).
  final String body;

  /// 다음 행동: one concrete next step.
  final String next;

  factory RequirementExplanation.parse(String text) {
    String role = '', body = '', next = '';
    final rest = <String>[];
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      String? after(String label) {
        for (final sep in [':', '：']) {
          if (line.startsWith('$label$sep')) {
            return line.substring(label.length + 1).trim();
          }
        }
        return null;
      }

      if (after('직무 해석') case final v?) {
        role = v;
      } else if (after('경험 활용') case final v?) {
        body = v;
      } else if (after('다음 행동') case final v?) {
        next = v;
      } else {
        rest.add(line);
      }
    }
    if (rest.isNotEmpty) {
      body = [body, ...rest].where((s) => s.isNotEmpty).join('\n');
    }
    return RequirementExplanation(role: role, body: body, next: next);
  }
}

/// Covered share of requirements: a big `준비 N / M`, a stacked bar and
/// per-status counts, with 필수·우대 coverage when priorities are known.
class ReadinessSummary extends StatelessWidget {
  const ReadinessSummary({
    super.key,
    required this.statuses,
    this.required,
    this.preferred,
  });

  final List<RequirementStatus> statuses;

  /// (ready, total) for 필수 and 우대, when the result has priorities.
  final (int, int)? required, preferred;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    int count(RequirementStatus s) => statuses.where((v) => v == s).length;
    final total = statuses.length;
    final ready = count(RequirementStatus.supported);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    return Container(
      key: const ValueKey('readiness-summary'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('준비된 요건', style: muted),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$ready',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(
                          text: ' / $total',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (required case (final r, final t) when t > 0)
                _split(context, '필수', r, t),
              if (preferred case (final r, final t) when t > 0)
                _split(context, '우대', r, t),
            ],
          ),
          const SizedBox(height: 12),
          if (total > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    for (final s in RequirementStatus.values)
                      if (count(s) > 0)
                        Expanded(
                          flex: count(s),
                          child: ColoredBox(
                            color: s.tone.color(context),
                            child: const SizedBox.expand(),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final s in RequirementStatus.values)
                ToneChip(
                  label: '${s.label} ${count(s)}',
                  tone: s.tone,
                  dot: true,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _split(BuildContext context, String label, int ready, int total) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label 요건',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text('$ready / $total 준비', style: theme.textTheme.titleMedium),
      ],
    );
  }
}

/// One requirement: status icon, name, chips, how the student's records
/// cover it, the evidence, a highlighted next step and, folded, what the
/// requirement means in this job.
class RequirementCard extends StatefulWidget {
  const RequirementCard({
    super.key,
    required this.requirement,
    required this.status,
    required this.explanation,
    this.chips = const [],
    this.evidence = const [],
    this.postingEvidence = const [],
    this.footer = const [],
  });

  final String requirement;
  final RequirementStatus status;
  final String explanation;

  /// Priority, frequency and similar chips after the status.
  final List<Widget> chips;

  /// The student's own record lines that support the requirement.
  final List<String> evidence;

  /// Where the posting asks for it (`공고 근거: …`).
  final List<String> postingEvidence;

  /// Actions such as 일정에 추가.
  final List<Widget> footer;

  @override
  State<RequirementCard> createState() => _RequirementCardState();
}

class _RequirementCardState extends State<RequirementCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final parts = RequirementExplanation.parse(widget.explanation);
    final small = theme.textTheme.bodySmall;
    final muted = small?.copyWith(color: colors.onSurfaceVariant);
    final status = widget.status;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: status.tone.color(context), width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(status.icon, color: status.tone.color(context), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.requirement,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ToneChip(label: status.label, tone: status.tone),
                        ...widget.chips,
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (parts.body.isNotEmpty) ...[
            const SizedBox(height: 12),
            SelectableText(parts.body, style: theme.textTheme.bodyMedium),
          ],
          if (widget.evidence.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final line in widget.evidence)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.bookmark_border,
                        size: 15,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: SelectableText(line, style: small)),
                  ],
                ),
              ),
          ],
          if (parts.next.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              key: const ValueKey('requirement-next-step'),
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
                          '다음 행동',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppTone.accent.color(context),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        SelectableText(parts.next, style: small),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (widget.footer.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: widget.footer),
          ],
          if (parts.role.isNotEmpty || widget.postingEvidence.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                onPressed: () => setState(() => _open = !_open),
                icon: Icon(_open ? Icons.expand_less : Icons.expand_more),
                label: Text(_open ? '공고 근거 접기' : '공고 근거·직무 해석'),
              ),
            ),
            if (_open) ...[
              for (final line in widget.postingEvidence)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.fromLTRB(10, 4, 8, 4),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: colors.outlineVariant, width: 3),
                    ),
                  ),
                  child: SelectableText(line, style: muted),
                ),
              if (parts.role.isNotEmpty) ...[
                const SizedBox(height: 6),
                SelectableText('직무 해석 · ${parts.role}', style: muted),
              ],
            ],
          ],
        ],
      ),
    );
  }
}

/// `필수 요건 3` style heading above a group of requirement cards.
class RequirementGroupHeading extends StatelessWidget {
  const RequirementGroupHeading({
    super.key,
    required this.title,
    required this.count,
  });

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(width: 8),
        ToneChip(label: '$count'),
      ],
    ),
  );
}
