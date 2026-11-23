import 'package:flutter/material.dart';

import '../../shared/app_tones.dart';
import '../../shared/widgets/surface_card.dart';

import 'event_category_tone.dart';
import 'planning_dates.dart';
import 'planning_repository.dart';

/// Shared seven-day personal calendar. Wide cards list event titles; narrow
/// ones (phone, side panel open) keep all seven days visible as dots.
class WeeklySchedule extends StatefulWidget {
  static const minimumWidth = 7 * 92.0 + 6 * 8 + 32 + 8;

  const WeeklySchedule({
    super.key,
    required this.events,
    required this.startsOn,
    required this.onSelectDay,
    this.compact = false,
  });
  final List<PlanningEvent> events;
  final WeekStartDay startsOn;
  final ValueChanged<DateTime> onSelectDay;
  final bool compact;

  @override
  State<WeeklySchedule> createState() => _WeeklyScheduleState();
}

class _WeeklyScheduleState extends State<WeeklySchedule> {
  int _offset = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = planningWeek(
      DateTime.now().add(Duration(days: _offset * 7)),
      widget.startsOn,
    );
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            children: [
              Semantics(
                header: true,
                child: Text(
                  _offset == 0 ? '이번 주 일정' : '주간 일정',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${days.first.month}.${days.first.day} – ${days.last.month}.${days.last.day}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '이전 주',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() => _offset--),
                  ),
                  if (_offset != 0)
                    TextButton(
                      onPressed: () => setState(() => _offset = 0),
                      child: const Text('오늘'),
                    ),
                  IconButton(
                    tooltip: '다음 주',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => setState(() => _offset++),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final detailed =
                  (constraints.maxWidth - 6 * 8) / 7 >=
                  MediaQuery.textScalerOf(context).scale(84);
              final gap = detailed ? 8.0 : 2.0;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < 7; i++) ...[
                    Expanded(child: _day(context, days[i], detailed)),
                    if (i < 6) SizedBox(width: gap),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Color _weekdayColor(BuildContext context, int weekday) => switch (weekday) {
    DateTime.sunday => AppTone.danger.color(context),
    DateTime.saturday => AppTone.info.color(context),
    _ => Theme.of(context).colorScheme.onSurfaceVariant,
  };

  Widget _date(BuildContext context, DateTime day, bool today) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: today
          ? BoxDecoration(color: colors.primary, shape: BoxShape.circle)
          : null,
      child: Text(
        '${day.day}',
        style: TextStyle(
          fontSize: 15,
          fontWeight: today ? FontWeight.w800 : FontWeight.w600,
          color: today ? colors.onPrimary : colors.onSurface,
        ),
      ),
    );
  }

  Widget _day(BuildContext context, DateTime day, bool detailed) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final events = eventsOnDay(widget.events, day);
    final today = sameDay(day, DateTime.now());
    final shown = widget.compact ? 1 : 2;
    final weekday = Text(
      weekdayLabel(day.weekday),
      style: theme.textTheme.labelMedium?.copyWith(
        color: _weekdayColor(context, day.weekday),
      ),
    );
    final Widget body = detailed
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [weekday, const Spacer(), _date(context, day, today)],
              ),
              const SizedBox(height: 8),
              for (final event in events.take(shown))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _EventPill(event: event, day: day),
                ),
              if (events.length > shown)
                Text(
                  '+${events.length - shown}개 더',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          )
        : Column(
            children: [
              weekday,
              const SizedBox(height: 4),
              _date(context, day, today),
              const SizedBox(height: 6),
              SizedBox(
                height: 6,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final event in events.take(3))
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: event.category.tone.color(context),
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox(width: 6, height: 6),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
    return Semantics(
      label:
          '${day.month}월 ${day.day}일${today ? ', 오늘' : ''}, 일정 ${events.length}개',
      button: true,
      child: Material(
        color: today
            ? colors.primaryContainer
            : detailed
            ? colors.surfaceContainerLow
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: ValueKey('week-day-${day.toIso8601String()}'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => widget.onSelectDay(day),
          child: Container(
            constraints: BoxConstraints(minHeight: detailed ? 132 : 0),
            padding: EdgeInsets.symmetric(
              horizontal: detailed ? 10 : 0,
              vertical: detailed ? 10 : 8,
            ),
            child: body,
          ),
        ),
      ),
    );
  }
}

class _EventPill extends StatelessWidget {
  const _EventPill({required this.event, required this.day});
  final PlanningEvent event;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = event.category.tone;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: tone.container(context),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ColoredBox(
                color: tone.color(context),
                child: const SizedBox(width: 3),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(7, 6, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        sameDay(event.start, day)
                            ? planningTime(event.start)
                            : '이어지는 일정',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
