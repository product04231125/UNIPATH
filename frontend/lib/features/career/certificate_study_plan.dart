import 'package:flutter/material.dart';

import '../../shared/app_tones.dart';
import '../../shared/widgets/field_label.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/widgets/tone_chip.dart';
import '../../shared/widgets/work_layout.dart';
import '../api/job_analysis_models.dart';
import '../api/student_api.dart';
import '../assistant/ai_record_catalog.dart';
import '../auth/auth_api.dart';
import '../records/portfolio/job_recommendation_result.dart';
import '../settings/ai_consent_preferences.dart';
import '../settings/ai_consent_section.dart';
import 'certificates.dart';

class StudyWeek {
  StudyWeek.fromJson(Map<String, dynamic> json)
    : week = json['week'] as int,
      start = DateTime.parse(json['start'] as String),
      end = DateTime.parse(json['end'] as String),
      focus = json['focus'] as String,
      subjects = List<String>.from(json['subjects'] as List? ?? const []),
      tasks = List<String>.from(json['tasks'] as List? ?? const []),
      hours = json['hours'] as int?,
      relatedRecords = List<String>.from(
        json['related_records'] as List? ?? const [],
      );
  final int week;
  final DateTime start, end;
  final String focus;
  final List<String> subjects, tasks, relatedRecords;
  final int? hours;
}

class StudyPlan {
  StudyPlan.fromJson(Map<String, dynamic> json)
    : status = json['status'] as String,
      missingFields = List<String>.from(json['missing_fields'] as List? ?? []),
      examDate = DateTime.tryParse(json['exam_date'] as String? ?? ''),
      subjects = List<String>.from(
        (json['scope'] as Map?)?['subjects'] as List? ?? const [],
      ),
      scopeSource = (json['scope'] as Map?)?['source'] as String?,
      weeks = [
        for (final w in json['weeks'] as List? ?? const [])
          StudyWeek.fromJson(Map<String, dynamic>.from(w as Map)),
      ],
      advice = json['advice'] as String?,
      failureReason = json['failure_reason'] as String?;
  final String status;
  final List<String> missingFields, subjects;
  final DateTime? examDate;
  final String? scopeSource, advice, failureReason;
  final List<StudyWeek> weeks;
}

typedef AddStudyPlan = Future<void> Function(
  String certificate,
  List<StudyWeek> weeks,
);

const studyHourOptions = [3, 5, 8, 10, 15, 20];

/// 학습 계획: weekly goals up to the exam over the official exam scope.
class CertificateStudyPlanCard extends StatefulWidget {
  const CertificateStudyPlanCard({
    super.key,
    required this.api,
    required this.consent,
    required this.certificate,
    required this.schedule,
    this.loadRecords,
    this.onAddPlan,
    this.now,
  });
  final StudentApi api;
  final AiConsentPreferences? consent;
  final CertificateSummary certificate;
  final CertificateSchedule schedule;
  final Future<List<AiRecordOption>> Function()? loadRecords;
  final AddStudyPlan? onAddPlan;
  final DateTime Function()? now;

  @override
  State<CertificateStudyPlanCard> createState() =>
      _CertificateStudyPlanCardState();
}

class _CertificateStudyPlanCardState extends State<CertificateStudyPlanCard> {
  DateTime? _examDate;
  var _hours = 8;
  StudyPlan? _plan;
  bool _busy = false;
  String? _error;

  DateTime get _today {
    final now = (widget.now ?? DateTime.now)();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _examDate = _nextExam();
  }

  @override
  void didUpdateWidget(covariant CertificateStudyPlanCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.certificate.id != widget.certificate.id) {
      _plan = null;
      _error = null;
      _examDate = _nextExam();
    }
  }

  /// The first official exam still ahead, as the default target.
  DateTime? _nextExam() {
    final exams = [
      for (final r in widget.schedule.rounds)
        for (final e in r.events)
          if (e.kind == ScheduleEventKind.exam && e.start.isAfter(_today))
            e.start,
    ]..sort();
    return exams.firstOrNull;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      helpText: '목표 시험일',
      initialDate: _examDate ?? _today.add(const Duration(days: 56)),
      firstDate: _today.add(const Duration(days: 1)),
      lastDate: _today.add(const Duration(days: 730)),
    );
    if (picked != null && mounted) setState(() => _examDate = picked);
  }

  Future<void> _run() async {
    final consent = widget.consent, date = _examDate;
    if (_busy || consent == null || date == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final records =
          await (widget.loadRecords?.call() ?? loadAiRecords(widget.api));
      if (!mounted) return;
      if (!await requestAiConsent(
            context,
            consent,
            AiConsentFeature.certificateStudyPlan,
          ) ||
          !mounted) {
        return;
      }
      final value = await widget.api.api.request(
        'POST',
        'me/certificate-study-plans',
        {
          'certificate_id': widget.certificate.id,
          'exam_date':
              '${date.year.toString().padLeft(4, '0')}-'
              '${date.month.toString().padLeft(2, '0')}-'
              '${date.day.toString().padLeft(2, '0')}',
          'hours_per_week': _hours,
          'records': [
            for (final r in records)
              PersonalEvidenceSelection(
                kind: r.kind,
                recordId: r.id,
                expectedVersion: r.version,
              ).toJson(),
          ],
          'external_processing_consent': true,
        },
      );
      if (mounted) setState(() => _plan = StudyPlan.fromJson(value!));
    } on AuthFailure catch (e) {
      if (mounted) {
        setState(
          () => _error = e.status == 409
              ? '저장 기록이 변경되었습니다. 다시 실행해 주세요.'
              : e.message,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = '학습 계획을 만들지 못했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPlan(StudyPlan plan) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await widget.onAddPlan!(widget.certificate.name, plan.weeks);
      messenger?.showSnackBar(
        SnackBar(content: Text('주차 목표 ${plan.weeks.length}개를 일정에 추가했습니다.')),
      );
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(e is AuthFailure ? e.message : '일정에 추가하지 못했습니다.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final date = _examDate;
    final plan = _plan;
    return SurfaceCard(
      key: const ValueKey('certificate-study-plan'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('학습 계획', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '공식 시험 과목을 범위로, 내 기록에서 이미 다룬 과목은 짧게 잡아 시험일까지 주차별로 나눕니다.',
            style: muted,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              SizedBox(
                width: 220,
                child: FieldLabel(
                  label: '목표 시험일',
                  child: OutlinedButton.icon(
                    key: const ValueKey('study-exam-date'),
                    onPressed: _busy ? null : _pickDate,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      date == null
                          ? '날짜 선택'
                          : '${date.year}. ${date.month}. ${date.day}. (${dDay(date, _today)})',
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: FieldLabel(
                  label: '주당 공부 시간',
                  child: DropdownButtonFormField<int>(
                    key: const ValueKey('study-hours'),
                    initialValue: _hours,
                    isExpanded: true,
                    items: [
                      for (final h in studyHourOptions)
                        DropdownMenuItem(value: h, child: Text('$h시간')),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _hours = v ?? _hours),
                  ),
                ),
              ),
              FilledButton.icon(
                key: const ValueKey('study-plan-run'),
                onPressed: _busy || date == null || widget.consent == null
                    ? null
                    : _run,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: Text(_busy ? '만드는 중…' : '학습 계획 만들기'),
              ),
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (plan != null) ...[
            const SizedBox(height: 16),
            _planView(context, plan),
          ],
        ],
      ),
    );
  }

  Widget _planView(BuildContext context, StudyPlan plan) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (plan.status != 'completed') {
      return Text(switch (plan.status) {
        'needs_user_input' => '외부 전송 동의가 필요합니다. 다시 실행해 동의를 확인하세요.',
        'not_configured' => '학습 계획 기능 준비 중입니다. 서버 분석 설정이 필요합니다.',
        _ =>
          plan.failureReason != null
              ? recommendationFailureLabel(plan.failureReason!)
              : '학습 계획을 만들지 못했습니다.',
      });
    }
    return Column(
      key: const ValueKey('study-plan-result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (plan.scopeSource == null)
          NoteLine(
            key: const ValueKey('study-plan-no-scope'),
            icon: Icons.warning_amber_outlined,
            color: AppTone.warning.color(context),
            text: '공식 시험 과목을 불러오지 못해 AI가 일반 지식으로 짰습니다. 시험 범위는 공식 사이트에서 확인하세요.',
          )
        else
          Text('범위 · ${plan.scopeSource}의 공식 시험 과목', style: muted),
        if (plan.advice case final advice?) ...[
          const SizedBox(height: 6),
          Text(advice),
        ],
        const SizedBox(height: 8),
        for (final w in plan.weeks)
          Container(
            key: ValueKey('study-week-${w.week}'),
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ToneChip(label: '${w.week}주차', tone: AppTone.accent),
                    Text(
                      '${shortDate(w.start)} ~ ${shortDate(w.end)}',
                      style: muted,
                    ),
                    if (w.hours case final hours?)
                      ToneChip(label: '$hours시간', icon: Icons.schedule),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  w.focus,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (w.subjects.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final s in w.subjects)
                        ToneChip(label: s, tone: AppTone.info),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                for (final t in w.tasks) Text('· $t'),
                if (w.relatedRecords.isNotEmpty)
                  Text(
                    '참고할 내 기록 · ${w.relatedRecords.join(', ')}',
                    style: muted,
                  ),
              ],
            ),
          ),
        if (widget.onAddPlan != null && plan.weeks.isNotEmpty) ...[
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('study-plan-add'),
              onPressed: () => _addPlan(plan),
              icon: const Icon(Icons.event_available_outlined),
              label: const Text('주차 목표를 일정에 추가'),
            ),
          ),
        ],
      ],
    );
  }
}
