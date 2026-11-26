import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/widgets/external_link_button.dart';
import '../../shared/widgets/feature_page.dart';
import '../../shared/widgets/responsive_grid.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/widgets/tone_chip.dart';
import '../../shared/widgets/work_layout.dart';
import '../api/student_api.dart';
import '../assistant/ai_record_catalog.dart';
import '../auth/auth_api.dart';
import '../auth/guest_preview_scope.dart';
import '../planning/planning_dates.dart';
import '../settings/ai_consent_preferences.dart';
import '../settings/ai_consent_section.dart';
import 'career_gap.dart';
import 'career_goal.dart';
import 'career_goal_card.dart';
import 'requirement_result.dart';
import 'saved_analyses.dart';

/// Adds one preparation step to 일정; [date] is the target day the student confirmed.
typedef AddPreparationPlan = Future<void> Function(
  GapAction action,
  GapRequirement requirement,
  DateTime date,
);

/// 목표 직무 분석: common requirements across postings for the goal, compared with all records.
class CareerGapView extends StatefulWidget {
  const CareerGapView({
    super.key,
    this.api,
    this.consent,
    this.careerGoal,
    this.store,
    this.loadRecords,
    this.onAddPlan,
    this.onReport,
    this.now,
  });

  final StudentApi? api;
  final AiConsentPreferences? consent;
  final CareerGoalController? careerGoal;
  final GapReportStore? store;
  final Future<List<AiRecordOption>> Function()? loadRecords;
  final AddPreparationPlan? onAddPlan;

  /// Called with each completed report (홈 summary).
  final ValueChanged<GapReport>? onReport;
  final DateTime Function()? now;

  @override
  State<CareerGapView> createState() => _CareerGapViewState();
}

class _CareerGapViewState extends State<CareerGapView> {
  GapReport? _report;
  bool _busy = false, _cached = false, _opened = false;

  /// Finished analyses kept in the account; null before signing in.
  SavedAnalysesController? _saved;

  static SavedAnalysesController? _savedFor(StudentApi? api) => api == null
      ? null
      : SavedAnalysesController(AnalysisResultsApi(api.api), AnalysisKind.gap);

  Future<void> _save(GapReport report) async {
    if (report.status != 'completed') return;
    await _saved?.save(
      title: analysisTitle(report.goalSummary, fallback: '목표 직무 분석'),
      summary: {
        'ready': report.requirements
            .where((r) => r.status == 'supported')
            .length,
        'total': report.requirements.length,
      },
      input: {'goal': report.goalSummary},
      result: report.raw,
    );
  }

  Future<void> _openSaved(SavedAnalysisSummary item) async {
    if (_busy) return;
    final revision = _revision;
    final saved = await _saved?.open(item.id);
    if (saved == null || !mounted || revision != _revision) return;
    try {
      final report = GapReport.fromJson(saved.result);
      setState(() {
        _report = report;
        _cached = false;
        _opened = true;
        _error = null;
      });
    } catch (_) {
      setState(() => _error = '저장된 결과의 형식을 읽지 못했습니다.');
    }
  }

  String? _error;
  var _revision = 0;

  @override
  void initState() {
    super.initState();
    widget.careerGoal?.addListener(_changed);
    _saved = _savedFor(widget.api);
    _restore();
  }

  @override
  void didUpdateWidget(covariant CareerGapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.careerGoal, widget.careerGoal)) {
      oldWidget.careerGoal?.removeListener(_changed);
      widget.careerGoal?.addListener(_changed);
    }
    if (oldWidget.api?.ownerId != widget.api?.ownerId) {
      _revision++;
      _report = null;
      _error = null;
      _busy = false;
      _opened = false;
      _saved?.dispose();
      _saved = _savedFor(widget.api);
      _restore();
    }
  }

  @override
  void dispose() {
    _saved?.dispose();
    widget.careerGoal?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _restore() async {
    final revision = _revision;
    final report = await widget.store?.load();
    if (!mounted ||
        revision != _revision ||
        report == null ||
        _report != null) {
      return;
    }
    setState(() {
      _report = report;
      _cached = true;
    });
  }

  bool get _connected =>
      widget.api != null &&
      widget.consent != null &&
      !GuestPreviewScope.isActive(context);

  Future<void> _run({bool wholeCategory = false}) async {
    final api = widget.api, consent = widget.consent;
    if (_busy || api == null || consent == null || !_connected) return;
    final goal = widget.careerGoal?.goal;
    final revision = _revision;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final records = await (widget.loadRecords?.call() ?? loadAiRecords(api));
      if (!mounted || revision != _revision) return;
      if (records.isEmpty) {
        setState(() {
          _error = '비교할 기록이 없습니다. 수강·활동·경험·자격·성과 기록을 먼저 추가해 주세요.';
        });
        return;
      }
      if (!await requestAiConsent(
            context,
            consent,
            AiConsentFeature.careerGap,
          ) ||
          !mounted ||
          revision != _revision) {
        return;
      }
      final report = await CareerGapApi(api).analyze(
        records: [
          for (final record in records)
            {
              'kind': record.kind,
              'record_id': record.id,
              'expected_version': record.version,
            },
        ],
        // The whole category: the saved goal's codes without the detail words.
        categoryCodes: wholeCategory && goal != null
            ? goal.categoryCodes
            : const [],
      );
      if (!mounted || revision != _revision) return;
      setState(() {
        _report = report;
        _cached = false;
        _opened = false;
      });
      if (report.status == 'completed') {
        // Kept in the account; a failed save leaves the result on screen.
        unawaited(_save(report));
        await widget.store?.save(report);
        widget.onReport?.call(report);
      }
    } on AuthFailure catch (e) {
      if (mounted && revision == _revision) {
        setState(() => _error = gapFailureMessage(e));
      }
    } catch (e) {
      if (mounted && revision == _revision) {
        setState(() => _error = gapFailureMessage(e));
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.careerGoal;
    final report = _report;
    final theme = Theme.of(context);
    return FeaturePage(
      title: '목표 직무 분석',
      body: [
        WorkLayout(
          input: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (goal != null) ...[
                CareerGoalCard(controller: goal),
                const SizedBox(height: 16),
              ],
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const NoteLine(
                      icon: Icons.cloud_upload_outlined,
                      text: '목표 직무 공고 최대 8건과 내 기록 전체를 비교합니다',
                      detail: '목표 직무 공고 최대 8건의 본문과 저장된 수강·활동·경험·자격·성과 기록 전체를 외부 Gemini에 보내 비교합니다. 다른 사람의 이름이나 민감한 정보가 없는지 확인하세요.',
                    ),
                    if (widget.api == null || widget.consent == null) ...[
                      const SizedBox(height: 6),
                      const NoteLine(
                        icon: Icons.lock_outline,
                        text: '로그인 후 이용할 수 있습니다.',
                      ),
                    ],
                    if (GuestPreviewScope.isActive(context)) ...[
                      const SizedBox(height: 6),
                      const NoteLine(
                        icon: Icons.visibility_outlined,
                        text: '게스트 미리보기에서는 자료를 전송하지 않습니다.',
                      ),
                    ],
                    if (goal != null && goal.loaded && !goal.goal.isSet) ...[
                      const SizedBox(height: 6),
                      const Text('목표 직무를 먼저 정해 주세요.'),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: FilledButton.icon(
                        key: const ValueKey('career-gap-run'),
                        onPressed:
                            _busy ||
                                !_connected ||
                                (goal != null && !goal.goal.isSet)
                            ? null
                            : _run,
                        icon: const Icon(Icons.insights_outlined),
                        label: Text(_busy ? '공고 수집·분석 중…' : '분석 실행'),
                      ),
                    ),
                    if (_busy) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 6),
                      Text(
                        '공고를 모으고 비교하는 데 1~2분 걸릴 수 있습니다. 같은 요청을 자동으로 다시 보내지 않습니다.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_saved case final saved?) ...[
                const SizedBox(height: 16),
                SavedAnalysesPanel(
                  controller: saved,
                  enabled: !_busy,
                  onOpen: _openSaved,
                ),
              ],
            ],
          ),
          result: report == null
              ? null
              : SurfaceCard(
                  key: const ValueKey('career-gap-result'),
                  child: _result(context, report),
                ),
          placeholder: const ResultPlaceholder(
            icon: Icons.insights_outlined,
            title: '분석을 실행하면 공고 요건과 내 기록의 비교 결과가 나옵니다',
          ),
        ),
      ],
    );
  }

  Widget _result(BuildContext context, GapReport report) {
    final theme = Theme.of(context);
    final heading = Text('분석 결과', style: theme.textTheme.titleMedium);
    switch (report.status) {
      case 'completed':
        break;
      case 'no_postings':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading,
            const SizedBox(height: 8),
            Text(
              report.searchNotice ??
                  '목표 직무로 비교할 수 있는 공고를 찾지 못했습니다. 잠시 후 다시 시도하거나 목표 직무를 넓혀 보세요.',
            ),
            if (report.categoryBrowseAvailable) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                key: const ValueKey('career-gap-whole-category'),
                onPressed: _busy ? null : () => _run(wholeCategory: true),
                child: const Text('직종 전체로 분석'),
              ),
            ],
          ],
        );
      case 'needs_user_input':
        return Text(
          report.missingFields.contains('career_goal')
              ? '목표 직무를 먼저 정해 주세요.'
              : report.missingFields.contains('records')
              ? '비교할 기록을 먼저 추가해 주세요.'
              : '외부 전송 동의가 필요합니다. 다시 실행해 동의를 확인하세요.',
        );
      case 'not_configured':
        return const Text('분석 기능 준비 중입니다. 서버 분석 설정이 필요합니다.');
      default:
        return const Text(
          '분석을 완료하지 못했습니다. 잠시 후 다시 시도하세요. 입력과 목표 직무는 그대로 있습니다.',
        );
    }
    final when = report.generatedAt?.toLocal();
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            heading,
            if (_saved case final saved?) ...[
              const SizedBox(width: 4),
              SavedAnalysisStar(controller: saved),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          [
            if (report.goalSummary.isNotEmpty) '목표 직무 · ${report.goalSummary}',
            '공고 ${report.postings.length}건 기준',
            if (when != null)
              '${when.month}월 ${when.day}일 ${planningTime(when)} 분석${_opened
                  ? ' (저장된 결과)'
                  : _cached
                  ? ' (이 기기에 저장된 최근 결과)'
                  : ''}',
          ].join(' · '),
          style: muted,
        ),
        const SizedBox(height: 16),
        ReadinessSummary(
          statuses: [
            for (final r in report.requirements)
              RequirementStatus.parse(r.status),
          ],
        ),
        if (report.summary case final summary?) ...[
          const SizedBox(height: 12),
          SelectableText(summary),
        ],
        for (final warning in report.warnings) ...[
          const SizedBox(height: 6),
          NoteLine(icon: Icons.warning_amber_outlined, text: warning),
        ],
        const SizedBox(height: 6),
        const NoteLine(
          icon: Icons.info_outline,
          text: '공고 요건과 기록의 비교이며 합격 가능성이나 지원 자격 판정이 아닙니다.',
        ),
        const SizedBox(height: 16),
        RequirementGroupHeading(
          title: '공통 요건',
          count: report.requirements.length,
        ),
        ResponsiveGrid(
          targetItemWidth: 420,
          minItemWidth: 320,
          maxColumns: 3,
          minHeightFactor: 0,
          children: [
            for (final requirement
                in [...report.requirements]..sort((a, b) {
                  final byStatus = RequirementStatus.parse(a.status).order
                      .compareTo(RequirementStatus.parse(b.status).order);
                  // Then the requirement most postings ask for.
                  return byStatus != 0
                      ? byStatus
                      : b.frequency.compareTo(a.frequency);
                }))
              _requirement(context, report, requirement),
          ],
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          key: const ValueKey('career-gap-postings'),
          tilePadding: EdgeInsets.zero,
          title: Text('분석한 공고 ${report.postings.length}건'),
          children: [
            for (final posting in report.postings)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('[${posting.number}] ${posting.title}'),
                subtitle: Text(
                  '${posting.company} · 마감 ${posting.closingLabel}',
                ),
                trailing: ExternalLinkButton(
                  url: posting.url,
                  label: '원 공고',
                  description: '최신 모집 조건과 마감은 원 공고에서 확인하세요.',
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _requirement(
    BuildContext context,
    GapReport report,
    GapRequirement requirement,
  ) {
    final titles = {for (final p in report.postings) p.number: p.title};
    return RequirementCard(
      key: ValueKey('career-gap-requirement-${requirement.id}'),
      requirement: requirement.requirement,
      status: RequirementStatus.parse(requirement.status),
      explanation: requirement.explanation,
      chips: [
        Tooltip(
          message:
              '공고 ${report.postings.length}건 중 ${requirement.frequency}건이 요구',
          child: ToneChip(
            label: '공고 ${report.postings.length}건 중 ${requirement.frequency}건',
            icon: Icons.work_outline,
          ),
        ),
      ],
      evidence: [
        for (final cite in requirement.evidence) '내 기록 근거: ${cite.excerpt}',
      ],
      postingEvidence: [
        for (final ref in requirement.postings.take(2))
          '공고 근거 [${ref.posting}] ${titles[ref.posting] ?? ''}: ${ref.excerpt}',
        if (requirement.postings.length > 2)
          '외 ${requirement.postings.length - 2}건의 공고에도 있습니다.',
      ],
      footer: [
        for (final action in requirement.actions)
          _action(context, requirement, action),
      ],
    );
  }

  Widget _action(
    BuildContext context,
    GapRequirement requirement,
    GapAction action,
  ) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '준비 제안 · ${action.typeLabel} · ${action.title}'
          '${action.weeks == null ? '' : ' · 약 ${action.weeks}주'}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        SelectableText(action.detail),
        Wrap(
          spacing: 8,
          children: [
            if (widget.onAddPlan != null)
              TextButton.icon(
                key: ValueKey(
                  'career-gap-plan-${requirement.id}-${action.title}',
                ),
                onPressed: () => _addPlan(requirement, action),
                icon: const Icon(Icons.event_available_outlined),
                label: const Text('일정에 추가'),
              ),
            if (action.type == 'certificate')
              const ExternalLinkButton(
                url: 'https://www.q-net.or.kr/',
                label: 'Q-Net에서 확인',
                description: '시험 일정·응시자격·원서접수는 Q-Net 등 공식 사이트에서 직접 확인하세요.',
              ),
          ],
        ),
      ],
    ),
  );

  Future<void> _addPlan(GapRequirement requirement, GapAction action) async {
    final today = (widget.now ?? DateTime.now)();
    final initial = DateUtils.dateOnly(
      today.add(Duration(days: 7 * (action.weeks ?? 4))),
    );
    final date = await showDatePicker(
      context: context,
      helpText: '목표일 선택 · ${action.title}',
      initialDate: initial,
      firstDate: DateUtils.dateOnly(today),
      lastDate: DateUtils.dateOnly(today.add(const Duration(days: 730))),
    );
    if (date == null || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await widget.onAddPlan!(action, requirement, date);
      messenger?.showSnackBar(
        SnackBar(content: Text('${date.month}월 ${date.day}일 일정에 추가했습니다.')),
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
