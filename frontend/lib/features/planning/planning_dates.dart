import 'planning_repository.dart';

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

List<DateTime> planningWeek(DateTime date, WeekStartDay startsOn) {
  final start = dateOnly(date)
      .subtract(Duration(days: (date.weekday - startsOn.weekday + 7) % 7));
  return List.generate(7, (i) => start.add(Duration(days: i)));
}

List<PlanningEvent> eventsOnDay(List<PlanningEvent> events, DateTime day) {
  final start = dateOnly(day);
  final end = start.add(const Duration(days: 1));
  return events
      .where((e) => e.start.isBefore(end) && e.end.isAfter(start))
      .toList()
    ..sort((a, b) => a.start.compareTo(b.start));
}

bool sameDay(DateTime a, DateTime b) => dateOnly(a) == dateOnly(b);

String weekdayLabel(int day) =>
    const ['월', '화', '수', '목', '금', '토', '일'][day - 1];

String planningTime(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
