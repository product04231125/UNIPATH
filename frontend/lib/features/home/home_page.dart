import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app_shell/phone_shell.dart';
import '../../app_shell/student_pages.dart';
import '../../shared/widgets/equal_height_row.dart';
import '../../shared/widgets/feature_line.dart';
import '../../shared/widgets/feature_page.dart';
import '../../shared/app_tones.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/responsive_grid.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/widgets/tone_chip.dart';

import '../auth/guest_preview_scope.dart';
import '../career/career_goal.dart';
import '../career/career_gap.dart';
import '../career/career_gap_summary_card.dart';
import '../career/career_goal_card.dart';
import '../planning/event_category_tone.dart';
import '../planning/planning_dates.dart';
import '../planning/planning_repository.dart';
import '../planning/planning_storage_state.dart';
import '../planning/weekly_schedule.dart';
import '../../shared/widgets/page_actions.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.onOpenPage,
    required this.onOpenSettings,
    required this.onOpenSchedule,
    required this.onAddSchedule,
    this.careerGoal,
    this.gapReport,
    this.onOpenCareerGap,
  });
  final PlanningRepository repository;

  /// Target job card on top; absent in guest preview and isolated tests.
  final CareerGoalController? careerGoal;

  /// Latest 목표 직무 분석 kept on this device, and how to open the full analysis.
  final ValueListenable<GapReport?>? gapReport;
  final VoidCallback? onOpenCareerGap;
  final ValueChanged<int> onOpenPage;
  final VoidCallback onOpenSettings;
  final ValueChanged<DateTime> onOpenSchedule;
  final VoidCallback onAddSchedule;

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
          .take(4)
          .toList();
      return LayoutBuilder(
        builder: (context, viewport) {
          final phone = PhoneChromeScope.of(context);
          final compact =
              viewport.maxWidth >= 1000 &&
              MediaQuery.textScalerOf(context).scale(14) <= 16.8;
          final gap = FeatureLine.slotGap(context);
          final prepareDone =
              profile.isConfigured && repository.events.isNotEmpty;
          final wide =
              !phone &&
              viewport.maxWidth >= LayoutWidths.wide &&
              MediaQuery.textScalerOf(context).scale(14) <= 16.8;
          return FeaturePage(
            scrollKey: const Key('home-scroll'),
            padding: EdgeInsets.only(
              bottom: phone ? phoneListGap : (compact ? 0 : 24),
            ),
            eyebrow: '${now.month}월 ${now.day}일 ${weekdayLabel(now.weekday)}요일',
            title: '나의 대학생활 경로',
            contextLabel: phone && profile.isConfigured
                ? (profile.hasCatalogSchool ? '등록' : '개인 설정')
                : null,
            body: wide
                ? _dashboard(context, upcoming, profile, year, prepareDone)
                : [
                    if (_career(context) case final career?) ...[
                      career,
                      SizedBox(height: gap),
                    ],
                    WeeklySchedule(
                      compact: compact,
                      events: repository.events,
                      startsOn: profile.weekStartsOn,
                      onSelectDay: onOpenSchedule,
                    ),
                    SizedBox(height: gap),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final upcomingCard = _upcoming(
                          context,
                          upcoming,
                          compact: compact,
                        );
                        final side = Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!prepareDone) ...[
                              _prepare(context, profile),
                              SizedBox(height: gap),
                            ],
                            _nextSteps(context, year),
                          ],
                        );
                        if (constraints.maxWidth < 820) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              upcomingCard,
                              SizedBox(height: gap),
                              side,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: upcomingCard),
                            const SizedBox(width: 16),
                            Expanded(flex: 2, child: side),
                          ],
                        );
                      },
                    ),
                  ],
          );
        },
      );
    },
  );

  /// FHD and larger: three columns (career, upcoming, setup) above a
  /// full-width week, so no card stretches across the whole screen.
  List<Widget> _dashboard(
    BuildContext context,
    List<PlanningEvent> upcoming,
    PlanningProfile profile,
    int? year,
    bool prepareDone,
  ) {
    final gap = FeatureLine.slotGap(context);
    Widget stack(List<Widget> cards) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          cards[i],
        ],
      ],
    );
    final career = [
      if (careerGoal case final goal?)
        CareerGoalCard(
          controller: goal,
          onFindJobs: () => onOpenPage(StudentPages.jobs),
        ),
      if ((gapReport, onOpenCareerGap) case (final report?, final open?))
        CareerGapSummaryCard(report: report, onOpen: open),
    ];
    final columns = [
      if (career.isNotEmpty) stack(career),
      _upcoming(context, upcoming),
      stack([
        if (!prepareDone) _prepare(context, profile),
        _nextSteps(context, year),
      ]),
    ];
    return [
      Row(
        key: const ValueKey('home-dashboard-columns'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < columns.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            Expanded(child: columns[i]),
          ],
        ],
      ),
      SizedBox(height: gap),
      WeeklySchedule(
        events: repository.events,
        startsOn: profile.weekStartsOn,
        onSelectDay: onOpenSchedule,
      ),
    ];
  }

  /// Target job and its readiness side by side on wide screens.
  Widget? _career(BuildContext context) {
    final goal = careerGoal;
    if (goal == null) return null;
    final goalCard = CareerGoalCard(
      controller: goal,
      onFindJobs: () => onOpenPage(StudentPages.jobs),
    );
    final gap = switch ((gapReport, onOpenCareerGap)) {
      (final report?, final open?) => CareerGapSummaryCard(
        report: report,
        onOpen: open,
      ),
      _ => null,
    };
    if (gap == null) return goalCard;
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 820
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                goalCard,
                SizedBox(height: FeatureLine.slotGap(context)),
                gap,
              ],
            )
          : EqualHeightRow(
              children: [
                Expanded(flex: 2, child: goalCard),
                const SizedBox(width: 16),
                Expanded(flex: 3, child: gap),
              ],
            ),
    );
  }

  Widget _card(
    BuildContext context,
    String title,
    Widget child, {
    Widget? trailing,
  }) => SurfaceCard(
    key: ValueKey('home-card-$title'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FeatureLine.section(
          text: title,
          trailing: trailing,
          padTop: false,
          padBottom: false,
        ),
        const SizedBox(height: 8),
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
        ? EmptyState(
            compact: true,
            icon: Icons.event_note_outlined,
            title: '앞으로 예정된 개인 일정이 없습니다.',
            action: TextButton(
              onPressed: () => onOpenPage(StudentPages.schedule),
              child: const Text('전체 일정 보기 →'),
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final event in events)
                _upcomingEvent(context, event, compact: compact),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => onOpenPage(StudentPages.schedule),
                  child: const Text('전체 일정 보기 →'),
                ),
              ),
            ],
          ),
    trailing: PageAddButton(
      label: '일정 추가',
      onPressed: () {
        if (GuestPreviewScope.isActive(context) || repository.writesBlocked) {
          GuestPreviewScope.showBlockedMessage(context);
          return;
        }
        onAddSchedule();
      },
    ),
  );

  Widget _upcomingEvent(
    BuildContext context,
    PlanningEvent event, {
    required bool compact,
  }) {
    final theme = Theme.of(context);
    final tone = event.category.tone;
    final start = event.start;
    final today = DateTime.now();
    final days = DateTime(
      start.year,
      start.month,
      start.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;
    final details =
        '${weekdayLabel(start.weekday)} ${planningTime(start)} · ${event.category.label}';
    return Tooltip(
      message:
          '${event.title}\n${start.month}.${start.day} · ${planningTime(start)} · ${event.category.label}',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onOpenSchedule(start),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 48,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: tone.container(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      '${start.month}월',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: tone.color(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${start.day}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        height: 1.1,
                        color: tone.color(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: compact ? 1 : null,
                      overflow: compact ? TextOverflow.ellipsis : null,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (days >= 0 && days <= 7)
                ToneChip(
                  label: days == 0 ? '오늘' : 'D-$days',
                  tone:
                      days <= 2 ||
                          event.category == PlanningEventCategory.deadline
                      ? AppTone.danger
                      : AppTone.warning,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _prepare(BuildContext context, PlanningProfile profile) {
    final configured = profile.isConfigured;
    final hasEvents = repository.events.isNotEmpty;
    final done = (configured ? 1 : 0) + (hasEvents ? 1 : 0);
    return _card(
      context,
      '준비 목록',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(minHeight: 6, value: done / 2),
          ),
          const SizedBox(height: 8),
          _prepareItem(
            context,
            configured,
            '학업과 계획 정보',
            configured ? '입력 완료' : '학교·학과·입학연도를 설정하세요.',
            onOpenSettings,
          ),
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
      trailing: ToneChip(label: '$done/2', tone: AppTone.accent),
    );
  }

  Widget _prepareItem(
    BuildContext context,
    bool done,
    String title,
    String description,
    VoidCallback action,
  ) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: action,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(
              done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: done
                  ? AppTone.success.color(context)
                  : theme.colorScheme.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Widget _nextSteps(BuildContext context, int? year) {
    final theme = Theme.of(context);
    final steps = switch (year) {
      1 || 2 => const [
        _PlanLink(
          '수강 계획 정리',
          '학기별 과목과 수강 계획',
          Icons.menu_book_outlined,
          StudentPages.academics,
        ),
        _PlanLink(
          '활동 기록 시작',
          '참여한 활동과 준비 중인 활동',
          Icons.volunteer_activism_outlined,
          StudentPages.activity,
        ),
      ],
      3 => const [
        _PlanLink(
          '활동 정리',
          '프로젝트와 경험 기록',
          Icons.volunteer_activism_outlined,
          StudentPages.activity,
        ),
        _PlanLink(
          '수강 계획 확인',
          '과목과 학기 계획',
          Icons.menu_book_outlined,
          StudentPages.academics,
        ),
      ],
      4 => const [
        _PlanLink(
          '졸업 요건 확인',
          '개인 기준 졸업 요건',
          Icons.school_outlined,
          StudentPages.academics,
        ),
        _PlanLink(
          '자료 정리',
          '경험과 자료 정리',
          Icons.collections_bookmark_outlined,
          StudentPages.materials,
        ),
      ],
      _ => const [
        _PlanLink(
          '수강 관리',
          '수강 과목과 학기 계획',
          Icons.menu_book_outlined,
          StudentPages.academics,
        ),
        _PlanLink(
          '활동 기록',
          '참여한 활동 기록',
          Icons.volunteer_activism_outlined,
          StudentPages.activity,
        ),
      ],
    };
    return SurfaceCard(
      key: const ValueKey('home-card-다음에 이어갈 기록'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('다음에 이어갈 기록', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final step in steps)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onOpenPage(step.page),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    IconBadge(icon: step.icon, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(step.label, style: theme.textTheme.titleSmall),
                          Text(
                            step.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
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
