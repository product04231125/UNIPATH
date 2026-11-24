import 'package:flutter/material.dart';

import '../../shared/app_tones.dart';
import '../../shared/widgets/external_link_button.dart';
import '../../shared/widgets/tone_chip.dart';
import '../../shared/widgets/work_layout.dart';
import '../auth/auth_api.dart';
import '../records/portfolio/job_recommendation_result.dart';
import 'certificates.dart';

typedef AddCertificateEvents = Future<void> Function(
  String certificate,
  List<ScheduleEvent> events,
);

/// One line about the next registration, or why there is none.
class NextRegistrationLine extends StatelessWidget {
  const NextRegistrationLine({
    super.key,
    required this.schedule,
    required this.today,
  });
  final CertificateSchedule schedule;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final next = schedule.nextRegistration;
    if (schedule.status == 'upcoming' && next != null) {
      final until = dDay(next.start, today);
      final open = until == null;
      return NoteLine(
        icon: Icons.event_available_outlined,
        color: AppTone.accent.color(context),
        text: open
            ? '${next.label} 중 · ${shortDate(next.end)} 마감 (${dDay(next.end, today)})'
            : '다음 ${next.label} ${shortDate(next.start)} ~ ${shortDate(next.end)} ($until)',
      );
    }
    return NoteLine(
      icon: switch (schedule.status) {
        'always' => Icons.all_inclusive,
        'unavailable' => Icons.cloud_off_outlined,
        _ => Icons.hourglass_empty,
      },
      text: switch (schedule.status) {
        'always' => '상시 시험 · 원하는 날짜를 골라 접수합니다',
        'unavailable' => '공식 일정을 불러오지 못했습니다',
        _ => '다음 접수 일정 공개 전 · 올해 일정을 참고하세요',
      },
    );
  }
}

/// Official rounds: upcoming ones, or this year's as reference, with D-days and the source.
class CertificateScheduleView extends StatelessWidget {
  const CertificateScheduleView({
    super.key,
    required this.name,
    required this.schedule,
    required this.today,
    this.onAdd,
  });
  final String name;
  final CertificateSchedule schedule;
  final DateTime today;
  final AddCertificateEvents? onAdd;

  List<ScheduleEvent> get _ahead => [
    for (final r in schedule.rounds)
      for (final e in r.events)
        if (!e.endedBefore(today)) e,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final reference = schedule.status != 'upcoming';
    final rounds = reference ? schedule.referenceRounds : schedule.rounds;
    return Column(
      key: const ValueKey('certificate-schedule'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NextRegistrationLine(schedule: schedule, today: today),
        if (schedule.status == 'unavailable' &&
            schedule.failureReason != null) ...[
          const SizedBox(height: 4),
          Text(
            recommendationFailureLabel(schedule.failureReason!),
            style: muted,
          ),
        ],
        if (schedule.note case final note?) ...[
          const SizedBox(height: 6),
          Text(note, style: muted),
        ],
        if (reference && schedule.status == 'unpublished' && rounds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('올해 일정 (참고)', style: theme.textTheme.labelLarge),
          ),
        if (!reference && schedule.status == 'upcoming')
          // Rounds still running (e.g. 최종 발표) before the next registration.
          const SizedBox(height: 4),
        for (final round in rounds) _round(context, round, reference),
        if (schedule.source != null) ...[
          const SizedBox(height: 8),
          Text(
            [
              '출처 · ${schedule.source}',
              if (schedule.checkedAt != null) '확인 ${schedule.checkedAt}',
            ].join(' · '),
            style: muted,
          ),
        ],
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (schedule.sourceUrl case final url?)
              ExternalLinkButton(
                url: url,
                label: '공식 일정 확인',
                description: '일정은 바뀔 수 있습니다. 접수 전에 공식 사이트에서 확인하세요.',
              ),
            if (onAdd != null && _ahead.isNotEmpty)
              TextButton.icon(
                key: const ValueKey('certificate-add-events'),
                onPressed: () => _add(context),
                icon: const Icon(Icons.event_available_outlined),
                label: const Text('일정에 추가'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _round(BuildContext context, ScheduleRound round, bool reference) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            round.name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          for (final e in round.events)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(
                      e.label,
                      style: TextStyle(
                        color: e.endedBefore(today) || reference ? muted : null,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      eventPeriod(e),
                      style: TextStyle(
                        color: e.endedBefore(today) || reference ? muted : null,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  if (!reference)
                    if (dDay(e.start, today) case final d?)
                      ToneChip(
                        label: d,
                        tone: e.kind == ScheduleEventKind.registration
                            ? AppTone.accent
                            : AppTone.info,
                      )
                    else if (!e.endedBefore(today))
                      const ToneChip(label: '진행 중', tone: AppTone.success),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final chosen = await showDialog<List<ScheduleEvent>>(
      context: context,
      builder: (context) => _AddEventsDialog(name: name, events: _ahead),
    );
    if (chosen == null || chosen.isEmpty || !context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await onAdd!(name, chosen);
      messenger?.showSnackBar(
        SnackBar(content: Text('$name 일정 ${chosen.length}개를 추가했습니다.')),
      );
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(e is AuthFailure ? e.message : '일정에 추가하지 못했습니다.'),
        ),
      );
    }
  }
}

class _AddEventsDialog extends StatefulWidget {
  const _AddEventsDialog({required this.name, required this.events});
  final String name;
  final List<ScheduleEvent> events;

  @override
  State<_AddEventsDialog> createState() => _AddEventsDialogState();
}

class _AddEventsDialogState extends State<_AddEventsDialog> {
  late final _chosen = {for (final e in widget.events) e.key};

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.name} 일정 추가'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('공식 일정은 바뀔 수 있습니다. 추가할 일정을 고르세요.'),
            const SizedBox(height: 8),
            for (final e in widget.events)
              CheckboxListTile(
                key: ValueKey('certificate-event-${e.key}'),
                value: _chosen.contains(e.key),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(e.label),
                subtitle: Text(eventPeriod(e)),
                onChanged: (on) => setState(
                  () => on == true ? _chosen.add(e.key) : _chosen.remove(e.key),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        key: const ValueKey('certificate-add-events-confirm'),
        onPressed: _chosen.isEmpty
            ? null
            : () => Navigator.pop(context, [
                for (final e in widget.events)
                  if (_chosen.contains(e.key)) e,
              ]),
        child: Text('${_chosen.length}개 추가'),
      ),
    ],
  );
}
