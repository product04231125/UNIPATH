import 'package:flutter/material.dart';

import '../../shared/app_tones.dart';
import '../../shared/widgets/feature_page.dart';
import '../../shared/widgets/field_label.dart';
import '../../shared/widgets/responsive_grid.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/widgets/tone_chip.dart';
import '../../shared/widgets/work_layout.dart';
import '../api/job_recommendation_api.dart';
import '../api/student_api.dart';
import '../assistant/ai_record_catalog.dart';
import '../auth/auth_api.dart';
import '../auth/guest_preview_scope.dart';
import '../records/portfolio/job_recommendation_result.dart';
import '../settings/ai_consent_preferences.dart';
import '../settings/ai_consent_section.dart';
import 'career_goal.dart';
import 'career_goal_card.dart';
import 'certificate_schedule.dart';
import 'certificates.dart';
import 'saved_analyses.dart';

/// 자격증 추천: certificates for the target job's gaps, with official schedules.
class CertificateRecommendationView extends StatefulWidget {
  const CertificateRecommendationView({
    super.key,
    required this.api,
    required this.consent,
    this.careerGoal,
    this.loadRecords,
    this.onAddEvents,
    this.onOpenSchedule,
    this.onOpenCareerGap,
    this.now,
  });
  final StudentApi? api;
  final AiConsentPreferences? consent;
  final CareerGoalController? careerGoal;
  final Future<List<AiRecordOption>> Function()? loadRecords;
  final AddCertificateEvents? onAddEvents;

  /// Shows the certificate in the 시험 일정 tab.
  final ValueChanged<CertificateSummary>? onOpenSchedule;
  final VoidCallback? onOpenCareerGap;
  final DateTime Function()? now;

  @override
  State<CertificateRecommendationView> createState() =>
      _CertificateRecommendationViewState();
}

class _CertificateRecommendationViewState
    extends State<CertificateRecommendationView> {
  RecommendationAcademicStage? _stage;
  CertificateRecommendationResult? _result;
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
  }

  @override
  void didUpdateWidget(covariant CertificateRecommendationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.careerGoal, widget.careerGoal)) {
      oldWidget.careerGoal?.removeListener(_changed);
      widget.careerGoal?.addListener(_changed);
    }
    if (oldWidget.api?.ownerId != widget.api?.ownerId) {
      _revision++;
      _result = null;
      _error = null;
      _busy = false;
      _stage = null;
    }
  }

  @override
  void dispose() {
    widget.careerGoal?.removeListener(_changed);
    super.dispose();
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
            AiConsentFeature.certificateRecommendation,
          ) ||
          !mounted ||
          revision != _revision) {
        return;
      }
      final result = await CertificateApi(api)
          .recommend(records: records, academicStage: _stage);
      if (!mounted || revision != _revision) return;
      setState(() => _result = result);
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
      title: '자격증 추천',
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
                        child: FieldLabel(
                          label: '현재 학년 (선택)',
                          child:
                              DropdownButtonFormField<
                                RecommendationAcademicStage
                              >(
                                key: const ValueKey(
                                  'certificate-academic-stage',
                                ),
                                initialValue: _stage,
                                isExpanded: true,
                                items: [
                                  const DropdownMenuItem(child: Text('선택 안 함')),
                                  for (final stage
                                      in RecommendationAcademicStage.values)
                                    DropdownMenuItem(
                                      value: stage,
                                      child: Text(stage.label),
                                    ),
                                ],
                                onChanged: _busy
                                    ? null
                                    : (v) => setState(() => _stage = v),
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!_connected)
                      const NoteLine(
                        icon: Icons.lock_outline,
                        text: '자격증 추천을 받으려면 로그인해 주세요.',
                      )
                    else
                      const NoteLine(
                        icon: Icons.cloud_upload_outlined,
                        text: '목표 직무·부족 요건·내 기록을 외부 AI로 보내 추천을 받습니다',
                        detail:
                            '최근 목표 직무 분석의 부족 요건과 저장된 기록 전체를 Google 외부 AI로 보냅니다. '
                            '이미 가진 자격(자격 기록)은 추천에서 뺍니다. 시험 일정·응시료는 AI가 아니라 '
                            'Q-Net 공식 데이터와 시행 기관 공지에서 가져옵니다.',
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
                        key: const ValueKey('certificate-recommend-run'),
                        onPressed: _connected && !_busy ? _run : null,
                        icon: const Icon(Icons.auto_awesome_outlined),
                        label: Text(_busy ? '추천 받는 중…' : '자격증 추천 받기'),
                      ),
                    ),
                    if (_busy) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
            ],
          ),
          result: result == null ? null : _resultView(context, result),
          placeholder: const ResultPlaceholder(
            icon: Icons.workspace_premium_outlined,
            title: '목표 직무 공고가 요구하는 자격증과 다음 시험 일정을 알려 드립니다',
          ),
        ),
      ],
    );
  }

  Widget _resultView(BuildContext context, CertificateRecommendationResult r) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (r.status != 'completed') {
      return SurfaceCard(
        key: const ValueKey('certificate-recommend-result'),
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
      key: const ValueKey('certificate-recommend-result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('자격증 추천', style: theme.textTheme.titleMedium),
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
                      key: const ValueKey('certificate-gap-basis'),
                      label:
                          '목표 직무 분석 기준 · 공고 ${r.postingCount}건 · ${savedAnalysisTime(r.gapAnalyzedAt)}',
                      icon: Icons.insights_outlined,
                      tone: AppTone.info,
                    ),
                  if (r.held.isNotEmpty)
                    ToneChip(
                      key: const ValueKey('certificate-held'),
                      label: '보유 자격 제외 · ${r.held.join(', ')}',
                      icon: Icons.verified_outlined,
                      tone: AppTone.success,
                    ),
                ],
              ),
              if (r.gapAnalyzedAt == null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(
                      child: NoteLine(
                        key: ValueKey('certificate-no-gap'),
                        icon: Icons.info_outline,
                        text: '목표 직무 분석을 먼저 하면 공고에서 실제로 요구한 자격증을 근거로 추천합니다.',
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
                '추천은 공식 판정이 아니며 합격을 예측하지 않습니다. 일정은 접수 전에 공식 사이트에서 다시 확인하세요.',
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
              _card(context, r, item, i),
          ],
        ),
      ],
    );
  }

  Widget _card(
    BuildContext context,
    CertificateRecommendationResult r,
    CertificateRecommendation item,
    int index,
  ) {
    final theme = Theme.of(context);
    final today = (widget.now ?? DateTime.now)();
    final c = item.certificate;
    return SurfaceCard(
      key: ValueKey('certificate-recommendation-$index'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                Icons.workspace_premium_outlined,
                size: 20,
                color: AppTone.accent.color(context),
              ),
              ToneChip(label: c.kindLabel, tone: AppTone.accent),
              if (c.grade case final grade?) ToneChip(label: grade),
              if (item.weeks case final weeks?)
                ToneChip(label: '공부 약 $weeks주', icon: Icons.schedule),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            c.name,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (c.issuer.isNotEmpty)
            Text(
              c.issuer,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 6),
          Text(item.reason),
          if (item.evidence.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in item.evidence)
                  ToneChip(
                    label: e.frequency != null && r.postingCount > 0
                        ? '공고 ${r.postingCount}건 중 ${e.frequency}건 · ${e.requirement}'
                        : '보완 · ${e.requirement}',
                    tone: AppTone.warning,
                    icon: Icons.trending_up,
                  ),
              ],
            ),
          ],
          if (item.relatedRecords.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final title in item.relatedRecords)
                  ToneChip(
                    label: '도움 되는 기록 · $title',
                    tone: AppTone.success,
                    icon: Icons.check_circle_outline,
                  ),
              ],
            ),
          ],
          if (item.timing case final timing?) ...[
            const SizedBox(height: 8),
            NoteLine(
              icon: Icons.calendar_month_outlined,
              text: '준비 시기 · $timing',
            ),
          ],
          const Divider(height: 24),
          NextRegistrationLine(schedule: item.schedule, today: today),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: [
              if (widget.onOpenSchedule != null)
                TextButton.icon(
                  key: ValueKey('certificate-open-schedule-$index'),
                  onPressed: () => widget.onOpenSchedule!(c),
                  icon: const Icon(Icons.event_note_outlined),
                  label: const Text('시험 일정·과목 보기'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
