import 'package:flutter/material.dart';

import '../../app_shell/phone_shell.dart';
import '../../shared/widgets/equal_height_row.dart';
import '../../shared/widgets/feature_actions.dart';
import '../../shared/widgets/feature_line.dart';
import '../../shared/widgets/feature_page.dart';
import '../../shared/widgets/surface_card.dart';

import '../planning/planning_dates.dart';
import '../planning/planning_repository.dart';
import '../planning/planning_storage_state.dart';
import '../planning/weekly_schedule.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.onOpenPage,
    required this.onOpenSettings,
    required this.onOpenSchedule,
    required this.onAddSchedule,
    this.coveredRightWidth = 0,
  });
  final PlanningRepository repository;
  final ValueChanged<int> onOpenPage;
  final VoidCallback onOpenSettings;
  final ValueChanged<DateTime> onOpenSchedule;
  final VoidCallback onAddSchedule;
  final double coveredRightWidth;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: repository,
    builder: (context, _) {
      if (repository.isLoading || repository.loadFailed) {
        return PlanningStorageState(repository: repository);
      }
      final profile = repository.profile;
      final now = DateTime.now();
      final year = profile.academicYearFor(now);
      final upcoming = repository.events
          .where((e) => e.end.isAfter(now))
          .take(3)
          .toList();
      return LayoutBuilder(
        builder: (context, viewport) {
          final phone = PhoneChromeScope.of(context);
          final compact =
              viewport.maxWidth >= 1000 &&
              MediaQuery.textScalerOf(context).scale(14) <= 16.8;
          return FeaturePage(
            scrollKey: const Key('home-scroll'),
            padding: EdgeInsets.only(
              bottom: phone ? phoneListGap : (compact ? 0 : 24),
            ),
            eyebrow: '${now.month}월 ${now.day}일 ${weekdayLabel(now.weekday)}요일',
            title: '나의 대학생활 경로',
            description: '오늘 일정과 다음 기록을 한눈에 봅니다.',
            contextLabel: phone && profile.isConfigured
                ? '${profile.school} · ${profile.department}'
                : null,
            body: [
              LayoutBuilder(
                builder: (context, constraints) => Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: (constraints.maxWidth - coveredRightWidth).clamp(
                      0.0,
                      constraints.maxWidth,
                    ),
                    child: WeeklySchedule(
                      compact: compact,
                      events: repository.events,
                      startsOn: profile.weekStartsOn,
                      onSelectDay: onOpenSchedule,
                    ),
                  ),
                ),
              ),
              FeatureActions(
                children: [
                  FilledButton.icon(
                    onPressed: onAddSchedule,
                    icon: const Icon(Icons.add),
                    label: const Text('일정 추가'),
                  ),
                ],
              ),
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
                        SizedBox(height: phoneAwareGap(context, wide: 16)),
                        prepare,
                      ],
                    );
                  }
                  return EqualHeightRow(
                    children: [
                      Expanded(flex: compact ? 1 : 3, child: upcomingCard),
                      const SizedBox(width: 16),
                      Expanded(flex: compact ? 1 : 2, child: prepare),
                    ],
                  );
                },
              ),
              SizedBox(height: phone ? phoneListGap : (compact ? 8 : 16)),
              _nextSteps(context, year, compact: true),
            ],
          );
        },
      );
    },
  );

  Widget _card(BuildContext context, String title, Widget child) => SurfaceCard(
    key: ValueKey('home-card-$title'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FeatureLine.section(text: title),
        child,
      ],
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
              const Text('앞으로 예정된 개인 일정이 없습니다.'),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => onOpenPage(1),
                child: const Text('전체 일정 보기 →'),
              ),
            ],
          )
        : Column(
            children: [
              for (final event in events)
                InkWell(
                  onTap: () => onOpenSchedule(event.start),
                  child: FeatureLine.two(
                    primary: event.title,
                    secondary:
                        '${event.start.month}.${event.start.day} · ${planningTime(event.start)} · ${event.category.label}',
                    leading: const Icon(Icons.event_outlined),
                    trailing: const Icon(Icons.chevron_right),
                  ),
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
  ) => InkWell(
    onTap: action,
    child: FeatureLine.two(
      primary: title,
      secondary: description,
      leading: Icon(
        done ? Icons.check_circle_outline : Icons.radio_button_unchecked,
      ),
      trailing: const Icon(Icons.chevron_right),
    ),
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
          '활동 정리',
          '프로젝트와 경험을 내 기록으로 남기세요.',
          Icons.volunteer_activism_outlined,
          4,
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
          '자료 정리',
          '기록한 경험과 자료를 정리하세요.',
          Icons.collections_bookmark_outlined,
          6,
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
      ],
    };
    return Padding(
      key: const ValueKey('home-card-다음에 이어갈 기록'),
      padding: EdgeInsets.symmetric(
        horizontal: PhoneChromeScope.of(context) ? phoneCardPadding : 18,
        vertical: PhoneChromeScope.of(context)
            ? phoneListGap
            : (compact ? 4 : 8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('다음에 이어갈 기록', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final step in steps)
                Tooltip(
                  message: step.description,
                  child: TextButton.icon(
                    onPressed: () => onOpenPage(step.page),
                    icon: Icon(step.icon, size: 18),
                    label: Text(step.label),
                  ),
                ),
            ],
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
