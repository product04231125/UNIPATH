import 'package:flutter/material.dart';

import '../../shared/widgets/horizontal_scroll_area.dart';

import 'planning_dates.dart';
import 'planning_repository.dart';

/// Shared seven-day personal calendar, including an explicit empty state.
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
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final days = planningWeek(
      DateTime.now().add(Duration(days: _offset * 7)),
      widget.startsOn,
    );
    return Card(
      margin: const EdgeInsets.all(4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('이번 주 일정', style: Theme.of(context).textTheme.titleLarge),
                Text(
                  '${days.first.month}.${days.first.day}–${days.last.month}.${days.last.day}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: '이전 주',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => setState(() => _offset--),
                    ),
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
                final width = ((constraints.maxWidth - 48) / 7).clamp(
                  92.0,
                  double.infinity,
                );
                return HorizontalScrollArea(
                  scrollbarKey: const Key('weekly-horizontal-scrollbar'),
                  controller: _scroll,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < 7; i++) ...[
                        SizedBox(width: width, child: _day(context, days[i])),
                        if (i < 6) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _day(BuildContext context, DateTime day) {
    final events = eventsOnDay(widget.events, day);
    final today = sameDay(day, DateTime.now());
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label:
          '${day.month}월 ${day.day}일${today ? ', 오늘' : ''}, 일정 ${events.length}개',
      button: true,
      child: Material(
        color: today ? colors.primaryContainer : colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: today ? colors.primary : colors.outlineVariant,
          ),
        ),
        child: InkWell(
          key: ValueKey('week-day-${day.toIso8601String()}'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => widget.onSelectDay(day),
          child: Container(
            constraints: const BoxConstraints(minHeight: 144),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${weekdayLabel(day.weekday)} ${day.month}/${day.day}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  today ? '오늘' : ' ',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                if (events.isEmpty)
                  Text('일정 없음', style: Theme.of(context).textTheme.bodySmall)
                else ...[
                  for (final event in events.take(widget.compact ? 1 : 2))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            maxLines: widget.compact ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            sameDay(event.start, day)
                                ? planningTime(event.start)
                                : '이어지는 일정',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  if (events.length > (widget.compact ? 1 : 2))
                    Text(
                      '+ ${events.length - (widget.compact ? 1 : 2)}개',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
