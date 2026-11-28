import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/app_tones.dart';
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
import '../planning/academic_stage.dart';
import '../records/portfolio/job_recommendation_result.dart';
import '../settings/ai_consent_preferences.dart';
import '../settings/ai_consent_section.dart';
import '../records/personal_record_form.dart';
import '../records/personal_record_repository.dart';
import '../records/personal_repository_scope.dart';
import 'academic_stage_field.dart';
import 'activity_recommendation.dart';
import 'career_goal.dart';
import 'career_goal_card.dart';
import 'saved_analyses.dart';

typedef AddActivityPlan = Future<void> Function(
  ActivityRecommendation activity,
  DateTime date,
);

/// 활동 추천: kinds of external activities for the target job's gaps, where to look
/// (links only; listing sites do not allow collection) and Work24 internships.
class ActivityRecommendationView extends StatefulWidget {
  const ActivityRecommendationView({
    super.key,
    required this.api,
    required this.consent,
    this.careerGoal,
    this.loadRecords,
    this.onAddPlan,
    this.onRecordSaved,
    this.onOpenCareerGap,
    this.profileStage,
    this.now,
  });
  final StudentApi? api;
  final AiConsentPreferences? consent;
  final CareerGoalController? careerGoal;
  final Future<List<AiRecordOption>> Function()? loadRecords;
  final AddActivityPlan? onAddPlan;

  /// Called after a recommendation was saved as an activity record (내 자료).
  final VoidCallback? onRecordSaved;

  /// Opens 목표 직무 분석 so its gaps can steer the recommendations.
  final VoidCallback? onOpenCareerGap;

  /// The 학업 프로필 stage the 현재 학년 starts at.
  final ValueListenable<AcademicStage?>? profileStage;
  final DateTime Function()? now;

  @override
  State<ActivityRecommendationView> createState() =>
      _ActivityRecommendationViewState();
}

class _ActivityRecommendationViewState
    extends State<ActivityRecommendationView> {
  var _recordFormOpen = false;
  final _stage = AcademicStageChoice();
  ActivityRecommendationResult? _result;

  /// Finished recommendations kept in the account; null before signing in.
  SavedAnalysesController? _saved;

  static SavedAnalysesController? _savedFor(StudentApi? api) => api == null
      ? null
      : SavedAnalysesController(
          AnalysisResultsApi(api.api),
          AnalysisKind.activity,
        );
  bool _busy = false;
  String? _error;
  var _revision = 0;

  bool get _connected =>
      widget.api != null &&
      widget.consent != null &&
      !GuestPreviewScope.isActive(context);

  @override
  void initState() {
    super.initState();
    widget.careerGoal?.addListener(_changed);
    widget.profileStage?.addListener(_changed);
    _saved = _savedFor(widget.api);
  }

  @override
  void didUpdateWidget(covariant ActivityRecommendationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.careerGoal, widget.careerGoal)) {
      oldWidget.careerGoal?.removeListener(_changed);
      widget.careerGoal?.addListener(_changed);
    }
    if (!identical(oldWidget.profileStage, widget.profileStage)) {
      oldWidget.profileStage?.removeListener(_changed);
      widget.profileStage?.addListener(_changed);
    }
    if (oldWidget.api?.ownerId != widget.api?.ownerId) {
      _revision++;
      _result = null;
      _error = null;
      _busy = false;
      _stage.reset();
      _saved?.dispose();
      _saved = _savedFor(widget.api);
    }
  }

  @override
  void dispose() {
    _saved?.dispose();
    widget.careerGoal?.removeListener(_changed);
    widget.profileStage?.removeListener(_changed);
    super.dispose();
  }

  Future<void> _save(
    ActivityRecommendationResult result,
    AcademicStage? stage,
  ) async {
    if (result.status != 'completed' || result.recommendations.isEmpty) return;
    await _saved?.save(
      title: analysisTitle(result.goalSummary, fallback: '활동 추천'),
      summary: {'recommendations': result.recommendations.length},
      input: {
        if (result.goalSummary.isNotEmpty) 'goal': result.goalSummary,
        'academic_stage': ?stage?.name,
      },
      result: result.raw,
    );
  }

  Future<void> _openSaved(SavedAnalysisSummary item) async {
    if (_busy) return;
    final revision = _revision;
    final saved = await _saved?.open(item.id);
    if (saved == null || !mounted || revision != _revision) return;
    try {
      final result = ActivityRecommendationResult.fromJson(saved.result);
      setState(() {
        _result = result;
        _error = null;
      });
    } catch (_) {
      setState(() => _error = '저장된 결과의 형식을 읽지 못했습니다.');
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _run() async {
    final api = widget.api, consent = widget.consent;
    if (_busy || api == null || consent == null || !_connected) return;
    final revision = _revision;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final records = await (widget.loadRecords?.call() ?? loadAiRecords(api));
      if (!mounted || revision != _revision) return;
      if (records.isEmpty) {
        setState(
          () => _error = '추천에 쓸 기록이 없습니다. 수강·활동·경험·자격·성과 기록을 먼저 추가해 주세요.',
        );
        return;
      }
      if (!await requestAiConsent(
            context,
            consent,
            AiConsentFeature.activityRecommendation,
          ) ||
          !mounted ||
          revision != _revision) {
        return;
      }
      final stage = _stage.valueWith(widget.profileStage);
      final result = await ActivityRecommendationApi(api)
          .recommend(records: records, academicStage: stage);
      if (!mounted || revision != _revision) return;
      setState(() => _result = result);
      unawaited(_save(result, stage));
    } on AuthFailure catch (e) {
      if (mounted && revision == _revision) {
        setState(
          () => _error = e.status == 409
              ? '저장 기록이 변경되었습니다. 다시 실행하면 최신 기록으로 추천합니다.'
              : e.message,
        );
      }
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(() => _error = '추천을 받지 못했습니다. 잠시 후 다시 시도해 주세요.');
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final goal = widget.careerGoal;
    final result = _result;
    return FeaturePage(
      title: '활동 추천',
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
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 280),
                        child: AcademicStageField(
                          fieldKey: const ValueKey('activity-academic-stage'),
                          value: _stage.valueWith(widget.profileStage),
                          fromProfile: _stage.fromProfile(widget.profileStage),
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _stage.pick(v)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!_connected)
                      const NoteLine(
                        icon: Icons.lock_outline,
                        text: '활동 추천을 받으려면 로그인해 주세요.',
                      )
                    else
                      const NoteLine(
                        icon: Icons.cloud_upload_outlined,
                        text: '목표 직무·부족 요건·내 기록을 외부 AI로 보내 추천을 받습니다',
                        detail:
                            '최근 목표 직무 분석의 부족 요건과 저장된 기록 전체를 Google 외부 AI로 보냅니다. '
                            '대외활동·공모전 사이트는 이용약관상 자동 수집을 허용하지 않아, '
                            '찾을 곳과 검색어만 알려 드립니다. 실제 채용 공고는 채용공고 분석의 공고 찾기에서 찾을 수 있습니다.',
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: FilledButton.icon(
                        key: const ValueKey('activity-recommend-run'),
                        onPressed: _connected && !_busy ? _run : null,
                        icon: const Icon(Icons.auto_awesome_outlined),
                        label: Text(_busy ? '추천 받는 중…' : '활동 추천 받기'),
                      ),
                    ),
                    if (_busy) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
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
          result: result == null ? null : _resultView(context, result),
          placeholder: const ResultPlaceholder(
            icon: Icons.explore_outlined,
            title: '목표 직무에 맞는 해커톤·공모전·대외활동·인턴을 추천합니다',
          ),
        ),
      ],
    );
  }

  Widget _resultView(BuildContext context, ActivityRecommendationResult r) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (r.status != 'completed') {
      return SurfaceCard(
        key: const ValueKey('activity-recommend-result'),
        child: Text(switch (r.status) {
          'needs_user_input' when r.missingFields.contains('career_goal') =>
            '목표 직무를 먼저 정해 주세요.',
          'needs_user_input' when r.missingFields.contains('records') =>
            '추천에 쓸 기록을 먼저 추가해 주세요.',
          'needs_user_input' => '외부 전송 동의가 필요합니다. 다시 실행해 동의를 확인하세요.',
          'not_configured' => '추천 기능 준비 중입니다. 서버 분석 설정이 필요합니다.',
          _ =>
            r.failureReason != null
                ? recommendationFailureLabel(r.failureReason!)
                : '추천을 완료하지 못했습니다. 잠시 후 다시 시도해 주세요.',
        }),
      );
    }
    return Column(
      key: const ValueKey('activity-recommend-result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('활동 추천', style: theme.textTheme.titleMedium),
                  if (_saved case final saved?) ...[
                    const SizedBox(width: 4),
                    SavedAnalysisStar(controller: saved),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (r.goalSummary.isNotEmpty)
                    ToneChip(
                      label: '목표 직무 · ${r.goalSummary}',
                      icon: Icons.work_outline,
                      tone: AppTone.accent,
                    ),
                  if (r.gapAnalyzedAt != null)
                    ToneChip(
                      key: const ValueKey('activity-gap-basis'),
                      label:
                          '목표 직무 분석 기준 · 부족 요건 ${r.gapCount}개 · ${savedAnalysisTime(r.gapAnalyzedAt)}',
                      icon: Icons.insights_outlined,
                      tone: AppTone.info,
                    ),
                ],
              ),
              if (r.gapAnalyzedAt == null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(
                      child: NoteLine(
                        key: ValueKey('activity-no-gap'),
                        icon: Icons.info_outline,
                        text: '목표 직무 분석을 먼저 하면 부족한 요건에 맞춰 더 정확히 추천합니다.',
                      ),
                    ),
                    if (widget.onOpenCareerGap != null)
                      TextButton(
                        onPressed: widget.onOpenCareerGap,
                        child: const Text('목표 직무 분석'),
                      ),
                  ],
                ),
              ],
              if (r.summary case final summary?) ...[
                const SizedBox(height: 10),
                Text(summary),
              ],
              const SizedBox(height: 6),
              Text(
                '추천은 공식 판정이 아니며, 모집 조건과 일정은 각 사이트에서 직접 확인하세요.',
                style: muted,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ResponsiveGrid(
          targetItemWidth: 420,
          minItemWidth: 320,
          maxColumns: 3,
          minHeightFactor: 0,
          children: [
            for (final (i, item) in r.recommendations.indexed)
              _activityCard(context, r, item, i),
          ],
        ),
      ],
    );
  }

  static IconData _icon(String kind) => switch (kind) {
    'hackathon' => Icons.code,
    'contest' => Icons.emoji_events_outlined,
    'external' => Icons.groups_outlined,
    'internship' => Icons.badge_outlined,
    'volunteer' => Icons.volunteer_activism_outlined,
    'education' => Icons.school_outlined,
    _ => Icons.construction_outlined,
  };

  Widget _activityCard(
    BuildContext context,
    ActivityRecommendationResult r,
    ActivityRecommendation item,
    int index,
  ) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return SurfaceCard(
      key: ValueKey('activity-recommendation-$index'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                _icon(item.kind),
                size: 20,
                color: AppTone.accent.color(context),
              ),
              const SizedBox(width: 8),
              ToneChip(label: item.kindLabel, tone: AppTone.accent),
              if (item.weeks case final weeks?) ...[
                const SizedBox(width: 6),
                ToneChip(label: '약 $weeks주', icon: Icons.schedule),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(item.reason),
          if (item.requirements.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final text in item.requirements)
                  ToneChip(
                    label: '보완 · $text',
                    tone: AppTone.warning,
                    icon: Icons.trending_up,
                  ),
              ],
            ),
          ],
          if (item.deliverable case final deliverable?) ...[
            const SizedBox(height: 10),
            NoteLine(icon: Icons.edit_note, text: '기록할 결과 · $deliverable'),
          ],
          if (item.keywords.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('검색어 (누르면 복사)', style: muted),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final word in item.keywords)
                  ActionChip(
                    key: ValueKey('activity-keyword-$index-$word'),
                    avatar: const Icon(Icons.search, size: 16),
                    label: Text(word),
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.maybeOf(context);
                      await Clipboard.setData(ClipboardData(text: word));
                      messenger?.showSnackBar(
                        SnackBar(content: Text('‘$word’를 복사했습니다.')),
                      );
                    },
                  ),
              ],
            ),
          ],
          if (item.sites.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('찾을 곳', style: muted),
            Wrap(
              spacing: 2,
              children: [
                for (final id in item.sites)
                  if (r.sites[id] case final site?)
                    ExternalLinkButton(
                      url: site.url,
                      label: site.name,
                      description: '모집 조건과 일정은 ${site.name}에서 직접 확인하세요.',
                    ),
              ],
            ),
          ],
          if (widget.onAddPlan != null || _records != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: [
                if (widget.onAddPlan != null)
                  TextButton.icon(
                    key: ValueKey('activity-add-plan-$index'),
                    onPressed: () => _addPlan(item),
                    icon: const Icon(Icons.event_available_outlined),
                    label: const Text('일정에 추가'),
                  ),
                if (_records != null)
                  TextButton.icon(
                    key: ValueKey('activity-add-record-$index'),
                    onPressed: () => _addRecord(item),
                    icon: const Icon(Icons.post_add_outlined),
                    label: const Text('활동 기록으로 추가'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// The activity record repositories, when this view sits under the signed-in workspace.
  PersonalRepositoryScope? get _records =>
      widget.api == null ? null : PersonalRepositoryScope.read(context);

  Future<void> _addRecord(ActivityRecommendation item) async {
    final scope = _records;
    if (scope == null || _recordFormOpen) return;
    final draft = activityRecordDraft(item);
    final messenger = ScaffoldMessenger.maybeOf(context);
    var saved = false;
    _recordFormOpen = true;
    try {
      // Repositories refuse writes until they have read the current records.
      final repository = scope.records(draft.kind);
      try {
        await repository.load();
      } catch (e) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              e is AuthFailure ? e.message : '활동 기록을 읽지 못했습니다. 다시 시도하세요.',
            ),
          ),
        );
        return;
      }
      if (!mounted) return;
      await showPersonalRecordForm(
        context: context,
        kind: draft.kind,
        repository: repository,
        addLabel: draft.kind == PersonalRecordKind.experience
            ? '경험 추가'
            : '활동 추가',
        draftValues: draft.values,
        onSaved: () => saved = true,
      );
    } finally {
      _recordFormOpen = false;
    }
    if (!saved) return;
    widget.onRecordSaved?.call();
    messenger?.showSnackBar(
      const SnackBar(content: Text('내 자료에 추가했습니다. 참여한 뒤 역할과 결과를 채워 주세요.')),
    );
  }

  Future<void> _addPlan(ActivityRecommendation item) async {
    final today = (widget.now ?? DateTime.now)();
    final date = await showDatePicker(
      context: context,
      helpText: '목표일 선택 · ${item.title}',
      initialDate: DateUtils.dateOnly(
        today.add(Duration(days: 7 * (item.weeks ?? 4))),
      ),
      firstDate: DateUtils.dateOnly(today),
      lastDate: DateUtils.dateOnly(today.add(const Duration(days: 730))),
    );
    if (date == null || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await widget.onAddPlan!(item, date);
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
