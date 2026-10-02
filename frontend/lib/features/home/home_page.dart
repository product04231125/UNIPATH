import 'package:flutter/material.dart';

import '../planning/planning_repository.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.onOpenPage,
    required this.onOpenSettings,
  });

  final PlanningRepository repository;
  final ValueChanged<int> onOpenPage;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: repository,
    builder: (context, _) {
      if (repository.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      final profile = repository.profile;
      final academicYear = profile.academicYearFor(DateTime.now());
      final weekEvents = _eventsThisWeek(
        repository.events,
        profile.weekStartsOn,
      );
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: constraints.maxHeight < 620 ? 28 : 8,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1050),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.school.trim().isEmpty
                      ? '오늘 무엇을 정리해볼까요?'
                      : '${profile.school} · ${profile.department}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xff946c2e),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '나의 대학생활 경로',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                const Text(
                  '입력한 개인 계획을 바탕으로 다음 작업을 정리합니다.',
                  style: TextStyle(color: Color(0xff607386)),
                ),
                const SizedBox(height: 18),
                if (constraints.maxWidth >= 820)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _weeklyCard(
                          context,
                          weekEvents,
                          profile.weekStartsOn,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        flex: 2,
                        child: _prepareCard(context, profile, academicYear),
                      ),
                    ],
                  )
                else ...[
                  _weeklyCard(context, weekEvents, profile.weekStartsOn),
                  const SizedBox(height: 18),
                  _prepareCard(context, profile, academicYear),
                ],
                const SizedBox(height: 18),
                _nextStepsCard(context, academicYear),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _weeklyCard(
    BuildContext context,
    List<PlanningEvent> events,
    WeekStartDay weekStartsOn,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.calendar_month_outlined,
                    color: Color(0xff315a77),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '이번 주 일정',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              );
              final action = TextButton(
                onPressed: () => onOpenPage(1),
                child: const Text('전체 일정 보기 →'),
              );
              if (constraints.maxWidth < 340) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, action],
                );
              }
              return Row(children: [title, const Spacer(), action]);
            },
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final dayWidth = ((constraints.maxWidth - 48) / 7)
                  .clamp(72.0, 132.0)
                  .toDouble();
              final weekDays = _weekDays(DateTime.now(), weekStartsOn);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var index = 0; index < weekDays.length; index++) ...[
                      SizedBox(
                        width: dayWidth,
                        child: _weekDayCard(
                          context,
                          weekDays[index],
                          _eventsForDay(events, weekDays[index]),
                        ),
                      ),
                      if (index < weekDays.length - 1) const SizedBox(width: 8),
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

  Widget _weekDayCard(
    BuildContext context,
    DateTime day,
    List<PlanningEvent> events,
  ) {
    final isToday = _sameDay(day, DateTime.now());
    return Container(
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isToday ? const Color(0xffdcebf1) : const Color(0xfff6f8f9),
        border: Border.all(
          color: isToday ? const Color(0xff315a77) : const Color(0xffd8e1e7),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_weekdayLabel(day.weekday)} ${day.month}/${day.day}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: isToday ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (events.isEmpty)
            const Text(
              '일정 없음',
              style: TextStyle(fontSize: 11, color: Color(0xff607386)),
            )
          else ...[
            for (final event in events.take(2))
              Text(
                event.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (events.length > 2)
              Text(
                '+ ${events.length - 2}개',
                style: const TextStyle(fontSize: 11, color: Color(0xff607386)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _prepareCard(
    BuildContext context,
    PlanningProfile profile,
    int? academicYear,
  ) {
    final items = <_ChecklistItem>[
      if (!profile.isConfigured)
        _ChecklistItem(
          title: '학업과 계획 정보 입력',
          description: '학교·학과·입학연도를 입력하면 개인 계획 학년을 안내할 수 있어요.',
          action: '설정 열기',
          onTap: onOpenSettings,
        ),
      if (repository.events.isEmpty)
        _ChecklistItem(
          title: '첫 개인 일정 추가',
          description: '이번 주에 준비할 과제, 활동 또는 마감을 기록해 보세요.',
          action: '일정 추가',
          onTap: () => onOpenPage(1),
        ),
      if (profile.isConfigured && repository.events.isNotEmpty)
        _ChecklistItem(
          title: '기본 계획 준비 완료',
          description:
              '${academicYear == null ? '개인 계획' : '$academicYear학년 개인 계획'}과 이번 주 일정을 확인할 수 있어요.',
          action: '일정 보기',
          onTap: () => onOpenPage(1),
        ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('준비 목록', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text(
              '아직 입력하지 않은 항목부터 시작하세요.',
              style: TextStyle(color: Color(0xff607386)),
            ),
            const SizedBox(height: 10),
            for (final item in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.radio_button_unchecked),
                title: Text(item.title),
                subtitle: Text(item.description),
                trailing: TextButton(
                  onPressed: item.onTap,
                  child: Text(item.action),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _nextStepsCard(BuildContext context, int? academicYear) {
    final steps = _linksFor(academicYear);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('다음에 이어갈 기록', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              academicYear == null
                  ? '학업과 계획 정보를 입력하면 개인 계획 학년에 맞춰 안내합니다.'
                  : '$academicYear학년 개인 계획을 위한 우선 링크입니다. 공식 학적 판정이나 서버 추천이 아닙니다.',
              style: const TextStyle(color: Color(0xff607386)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final step in steps)
                  OutlinedButton.icon(
                    onPressed: () => onOpenPage(step.page),
                    icon: Icon(step.icon),
                    label: Text(step.label),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<_PlanLink> _linksFor(int? academicYear) => switch (academicYear) {
    1 || 2 => const [
      _PlanLink('수강 계획 정리', Icons.menu_book_outlined, 2),
      _PlanLink('활동 기록 시작', Icons.volunteer_activism_outlined, 4),
    ],
    3 => const [
      _PlanLink('경험 정리', Icons.business_center_outlined, 5),
      _PlanLink('수강 계획 확인', Icons.menu_book_outlined, 2),
    ],
    4 => const [
      _PlanLink('졸업 요건 확인', Icons.school_outlined, 3),
      _PlanLink('포트폴리오 정리', Icons.collections_bookmark_outlined, 7),
    ],
    _ => const [
      _PlanLink('수강 관리', Icons.menu_book_outlined, 2),
      _PlanLink('활동 기록', Icons.volunteer_activism_outlined, 4),
      _PlanLink('경험 정리', Icons.business_center_outlined, 5),
    ],
  };
}

class _ChecklistItem {
  const _ChecklistItem({
    required this.title,
    required this.description,
    required this.action,
    required this.onTap,
  });
  final String title;
  final String description;
  final String action;
  final VoidCallback onTap;
}

class _PlanLink {
  const _PlanLink(this.label, this.icon, this.page);
  final String label;
  final IconData icon;
  final int page;
}

List<PlanningEvent> _eventsThisWeek(
  List<PlanningEvent> events,
  WeekStartDay weekStartsOn,
) {
  final now = DateTime.now();
  final start = _weekDays(now, weekStartsOn).first;
  final end = start.add(const Duration(days: 7));
  return events
      .where((event) => event.start.isBefore(end) && event.end.isAfter(start))
      .toList();
}

List<DateTime> _weekDays(DateTime date, WeekStartDay weekStartsOn) {
  final start = DateTime(
    date.year,
    date.month,
    date.day,
  ).subtract(Duration(days: (date.weekday - weekStartsOn.weekday + 7) % 7));
  return List.generate(7, (index) => start.add(Duration(days: index)));
}

List<PlanningEvent> _eventsForDay(List<PlanningEvent> events, DateTime day) {
  final start = DateTime(day.year, day.month, day.day);
  final end = start.add(const Duration(days: 1));
  return events
      .where((event) => event.start.isBefore(end) && event.end.isAfter(start))
      .toList();
}

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _weekdayLabel(int weekday) => switch (weekday) {
  DateTime.monday => '월',
  DateTime.tuesday => '화',
  DateTime.wednesday => '수',
  DateTime.thursday => '목',
  DateTime.friday => '금',
  DateTime.saturday => '토',
  DateTime.sunday => '일',
  _ => '',
};
