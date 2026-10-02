import 'package:flutter/material.dart';

import '../planning/planning_dates.dart';
import '../planning/planning_repository.dart';
import '../planning/weekly_schedule.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.onOpenPage,
    required this.onOpenSettings,
    required this.onOpenSchedule,
  });
  final PlanningRepository repository;
  final ValueChanged<int> onOpenPage;
  final VoidCallback onOpenSettings;
  final ValueChanged<DateTime> onOpenSchedule;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: repository,
    builder: (context, _) {
      if (repository.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      final profile = repository.profile;
      final now = DateTime.now();
      final year = profile.academicYearFor(now);
      final todayEvents = eventsOnDay(repository.events, now);
      final upcoming = repository.events
          .where((e) => e.end.isAfter(now))
          .take(3)
          .toList();
      return LayoutBuilder(
        builder: (context, viewport) {
          final compact =
              viewport.maxWidth >= 1000 &&
              MediaQuery.textScalerOf(context).scale(14) <= 16.8;
          return SingleChildScrollView(
            key: const Key('home-scroll'),
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  key: const Key('home-overview'),
                  padding: EdgeInsets.all(compact ? 16 : 20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Flex(
                    direction: compact ? Axis.horizontal : Axis.vertical,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        flex: compact ? 3 : 0,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${now.month}월 ${now.day}일 ${weekdayLabel(now.weekday)}요일',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '나의 대학생활 경로',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              profile.isConfigured
                                  ? '${profile.school} · ${profile.department}'
                                  : '학교·학과와 첫 일정을 입력하고 나의 계획을 시작하세요.',
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: compact ? 24 : 0,
                        height: compact ? 0 : 14,
                      ),
                      Flexible(
                        flex: compact ? 2 : 0,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(label: Text('오늘 일정 ${todayEvents.length}개')),
                            Chip(
                              label: Text(
                                year == null ? '개인 계획 미설정' : '개인 계획 $year학년',
                              ),
                            ),
                            const Chip(label: Text('기기 로컬 저장')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                WeeklySchedule(
                  compact: compact,
                  events: repository.events,
                  startsOn: profile.weekStartsOn,
                  onSelectDay: onOpenSchedule,
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final upcomingCard = _upcoming(
                      context,
                      upcoming,
                      compact: compact,
                    );
                    final prepare = _prepare(context, profile);
                    if (constraints.maxWidth < 820) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          upcomingCard,
                          const SizedBox(height: 16),
                          prepare,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: compact ? 1 : 3, child: upcomingCard),
                        const SizedBox(width: 16),
                        Expanded(flex: compact ? 1 : 2, child: prepare),
                        if (compact) ...[
                          const SizedBox(width: 16),
                          Expanded(
                            child: _nextSteps(context, year, compact: true),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                if (!compact) ...[
                  const SizedBox(height: 16),
                  _nextSteps(context, year),
                ],
              ],
            ),
          );
        },
      );
    },
  );

  Widget _card(BuildContext context, String title, Widget child) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );

  Widget _upcoming(
    BuildContext context,
    List<PlanningEvent> events, {
    bool compact = false,
  }) => _card(
    context,
    '다가오는 일정',
    events.isEmpty
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.event_available_outlined, size: 28),
              const SizedBox(height: 8),
              const Text('앞으로 예정된 개인 일정이 없습니다.'),
              const SizedBox(height: 4),
              Text(
                '과제 마감이나 참여할 활동을 기록해 이번 주 계획을 채워보세요.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => onOpenSchedule(DateTime.now()),
                icon: const Icon(Icons.add),
                label: const Text('일정 추가'),
              ),
            ],
          )
        : Column(
            children: [
              for (final event in events)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(
                    event.title,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${event.start.month}.${event.start.day} · ${planningTime(event.start)} · ${event.category.label}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onOpenSchedule(event.start),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => onOpenPage(1),
                  child: const Text('전체 일정 보기 →'),
                ),
              ),
            ],
          ),
  );

  Widget _prepare(BuildContext context, PlanningProfile profile) {
    final configured = profile.isConfigured;
    final hasEvents = repository.events.isNotEmpty;
    return _card(
      context,
      '준비 목록',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '기본 준비 ${(configured ? 1 : 0) + (hasEvents ? 1 : 0)}/2',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: ((configured ? 1 : 0) + (hasEvents ? 1 : 0)) / 2,
          ),
          const SizedBox(height: 12),
          _prepareItem(
            context,
            configured,
            '학업과 계획 정보',
            configured ? '학교·학과·입학연도 입력 완료' : '학교·학과·입학연도를 설정하세요.',
            onOpenSettings,
          ),
          const Divider(),
          _prepareItem(
            context,
            hasEvents,
            '개인 일정',
            hasEvents
                ? '개인 일정 ${repository.events.length}개 저장됨'
                : '첫 일정으로 계획을 시작하세요.',
            () => onOpenSchedule(DateTime.now()),
          ),
        ],
      ),
    );
  }

  Widget _prepareItem(
    BuildContext context,
    bool done,
    String title,
    String description,
    VoidCallback action,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      done ? Icons.check_circle_outline : Icons.radio_button_unchecked,
    ),
    title: Text(title),
    subtitle: Text(description),
    trailing: const Icon(Icons.chevron_right),
    onTap: action,
  );

  Widget _nextSteps(BuildContext context, int? year, {bool compact = false}) {
    final steps = switch (year) {
      1 || 2 => const [
        _PlanLink(
          '수강 계획 정리',
          '학기별 과목과 개인 수강 계획을 확인하세요.',
          Icons.menu_book_outlined,
          2,
        ),
        _PlanLink(
          '활동 기록 시작',
          '참여한 활동과 준비 중인 활동을 정리하세요.',
          Icons.volunteer_activism_outlined,
          4,
        ),
      ],
      3 => const [
        _PlanLink(
          '경험 정리',
          '프로젝트와 경험을 내 기록으로 남기세요.',
          Icons.business_center_outlined,
          5,
        ),
        _PlanLink(
          '수강 계획 확인',
          '과목과 학기 계획을 이어서 정리하세요.',
          Icons.menu_book_outlined,
          2,
        ),
      ],
      4 => const [
        _PlanLink(
          '졸업 요건 확인',
          '개인 기준과 학교 공식 정보의 범위를 확인하세요.',
          Icons.school_outlined,
          3,
        ),
        _PlanLink(
          '포트폴리오 정리',
          '기록한 경험과 성과를 정리하세요.',
          Icons.collections_bookmark_outlined,
          7,
        ),
      ],
      _ => const [
        _PlanLink('수강 관리', '수강 과목과 학기 계획을 정리하세요.', Icons.menu_book_outlined, 2),
        _PlanLink(
          '활동 기록',
          '참여한 활동을 내 기록으로 남기세요.',
          Icons.volunteer_activism_outlined,
          4,
        ),
        _PlanLink(
          '경험 정리',
          '프로젝트와 경험을 정리하세요.',
          Icons.business_center_outlined,
          5,
        ),
      ],
    };
    return _card(
      context,
      '다음에 이어갈 기록',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            year == null
                ? '관심 있는 기록부터 시작하세요.'
                : '$year학년 개인 계획 링크 · 공식 학적 판정이나 서버 추천이 아닙니다.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (compact)
            for (final step in steps)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(step.icon),
                title: Text(step.label),
                subtitle: Text(step.description),
                onTap: () => onOpenPage(step.page),
              )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 820 ? steps.length : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final step in steps)
                      SizedBox(
                        width: width,
                        child: Material(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => onOpenPage(step.page),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(step.icon),
                                  const SizedBox(height: 10),
                                  Text(
                                    step.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    step.description,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _PlanLink {
  const _PlanLink(this.label, this.description, this.icon, this.page);
  final String label;
  final String description;
  final IconData icon;
  final int page;
}
