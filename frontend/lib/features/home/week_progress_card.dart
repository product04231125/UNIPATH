import 'package:flutter/material.dart';

import '../../shared/app_tones.dart';
import '../../shared/widgets/feature_line.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/widgets/tone_chip.dart';
import '../auth/auth_api.dart';
import '../auth/guest_preview_scope.dart';
import '../planning/event_category_tone.dart';
import '../planning/planning_dates.dart';
import '../planning/planning_repository.dart';

/// 이번 주 할 일: this week's events (study goals, exam steps, plans) with check boxes and
/// how many are done.
class WeekProgressCard extends StatelessWidget {
  const WeekProgressCard({
    super.key,
    required this.repository,
    required this.startsOn,
    required this.onOpenSchedule,
    this.now,
    this.maxItems = 7,
  });
  final PlanningRepository repository;
  final WeekStartDay startsOn;
  final ValueChanged<DateTime> onOpenSchedule;
  final DateTime Function()? now;
  final int maxItems;

  static List<PlanningEvent> thisWeek(
    List<PlanningEvent> events,
    DateTime today,
    WeekStartDay startsOn,
  ) {
    final days = planningWeek(today, startsOn);
    final start = days.first, end = days.last.add(const Duration(days: 1));
    return events
        .where((e) => !e.start.isBefore(start) && e.start.isBefore(end))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  Future<void> _toggle(
    BuildContext context,
    PlanningEvent event,
    bool done,
  ) async {
    if (GuestPreviewScope.isActive(context) || repository.writesBlocked) {
      GuestPreviewScope.showBlockedMessage(context);
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await repository.saveEvent(
        event.withCompletion(done ? (now ?? DateTime.now)() : null),
      );
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(e is AuthFailure ? e.message : '완료 표시를 저장하지 못했습니다.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repository,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final today = dateOnly((now ?? DateTime.now)());
    final events = thisWeek(repository.events, today, startsOn);
    final done = events.where((e) => e.done).length;
    final shown = [
      // Open ones first, then what is already done.
      ...events.where((e) => !e.done),
      ...events.where((e) => e.done),
    ].take(maxItems).toList();
    return SurfaceCard(
      key: const ValueKey('home-week-progress'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FeatureLine.section(
            text: '이번 주 할 일',
            padTop: false,
            padBottom: false,
            trailing: events.isEmpty
                ? null
                : Text(
                    '완료 $done / ${events.length}',
                    key: const ValueKey('home-week-progress-count'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: AppTone.accent.color(context),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          if (events.isEmpty)
            Text(
              '이번 주 일정이 없습니다. 자격증 학습 계획이나 준비 계획을 일정에 넣으면 여기서 체크할 수 있습니다.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: done / events.length,
                minHeight: 6,
                color: AppTone.success.color(context),
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 6),
            for (final event in shown)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onOpenSchedule(event.start),
                child: Row(
                  children: [
                    Checkbox(
                      key: ValueKey('home-week-done-${event.id}'),
                      value: event.done,
                      semanticLabel: '${event.title} 완료',
                      onChanged: (value) =>
                          _toggle(context, event, value ?? false),
                    ),
                    Expanded(
                      child: Text(
                        event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          decoration: event.done
                              ? TextDecoration.lineThrough
                              : null,
                          color: event.done ? muted : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${weekdayLabel(event.start.weekday)} ${event.start.month}.${event.start.day}',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                    const SizedBox(width: 6),
                    ToneChip(
                      label: event.category.label,
                      tone: event.category.tone,
                      dot: true,
                    ),
                  ],
                ),
              ),
            if (events.length > shown.length)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '외 ${events.length - shown.length}개 · 일정에서 모두 볼 수 있습니다',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
