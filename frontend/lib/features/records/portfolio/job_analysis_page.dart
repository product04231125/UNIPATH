import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../shared/app_tones.dart';
import '../../../shared/widgets/feature_page.dart';
import '../../../shared/widgets/page_tabs.dart';
import '../../../shared/widgets/responsive_grid.dart';
import '../../../shared/widgets/tone_chip.dart';
import '../../../shared/widgets/work_layout.dart';
import '../../../shared/widgets/field_label.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../api/student_api.dart';
import '../../api/academic_guidance_models.dart';
import '../../api/job_analysis_api.dart';
import '../../api/job_analysis_models.dart';
import '../../assistant/ai_record_catalog.dart';
import '../../auth/auth_api.dart';
import '../../../shared/pending_ui_action.dart';
import '../../career/career_gap.dart';
import '../../career/career_gap_view.dart';
import '../../career/career_goal.dart';
import '../../career/requirement_result.dart';
import '../../career/saved_analyses.dart';
import '../../planning/academic_stage.dart';
import '../../auth/guest_preview_scope.dart';
import '../../settings/ai_consent_preferences.dart';
import '../../settings/ai_consent_section.dart';
import 'job_recommendation_page.dart';
import 'material_selection.dart';
import '../../writing/posting_link.dart';
import '../../writing/writing_api.dart';

const jobPostingFileMaxBytes = 10 * 1024 * 1024;

Future<XFile?> pickJobPostingFile() => openFile(
  acceptedTypeGroups: const [
    XTypeGroup(
      label: 'PDF·캡처',
      extensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
      mimeTypes: ['application/pdf', 'image/png', 'image/jpeg', 'image/webp'],
    ),
  ],
);

/// Client-side check only. The bytes stay on this screen and are not uploaded.
void validateJobPostingFile(String name, Uint8List bytes) {
  if (bytes.length > jobPostingFileMaxBytes) {
    throw StateError('PDF·캡처는 10MB 이하로 선택하세요.');
  }
  final lower = name.toLowerCase();
  final pdf = lower.endsWith('.pdf') && _isPdf(bytes);
  final image =
      (lower.endsWith('.png') && _isPng(bytes)) ||
      ((lower.endsWith('.jpg') || lower.endsWith('.jpeg')) && _isJpeg(bytes)) ||
      (lower.endsWith('.webp') && _isWebp(bytes));
  if (!pdf && !image) {
    throw StateError('PDF 또는 캡처 이미지(PNG, JPEG, WEBP)를 선택하세요.');
  }
}

bool _isPdf(Uint8List bytes) =>
    bytes.length >= 5 && String.fromCharCodes(bytes.take(5)) == '%PDF-';

bool _isPng(Uint8List bytes) =>
    bytes.length >= 8 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4E &&
    bytes[3] == 0x47 &&
    bytes[4] == 0x0D &&
    bytes[5] == 0x0A &&
    bytes[6] == 0x1A &&
    bytes[7] == 0x0A;

bool _isJpeg(Uint8List bytes) =>
    bytes.length >= 3 &&
    bytes[0] == 0xFF &&
    bytes[1] == 0xD8 &&
    bytes[2] == 0xFF;

bool _isWebp(Uint8List bytes) =>
    bytes.length >= 12 &&
    String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
    String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';

class JobAnalysisPage extends StatefulWidget {
  const JobAnalysisPage({
    super.key,
    this.pickFile,
    this.api,
    this.consent,
    this.loadRecords,
    this.loadMaterials,
    this.loadDocuments,
    this.careerGoal,
    this.gapStore,
    this.onAddPlan,
    this.onGapReport,
    this.purposeRequest,
    this.onWrite,
    this.profileStage,
  });
  final Future<XFile?> Function()? pickFile;
  final StudentApi? api;
  final AiConsentPreferences? consent;
  final Future<List<AiRecordOption>> Function()? loadRecords;
  // 내 자료 on this device; only the ones the student selects are sent.
  final Future<List<AssistantMaterial>> Function()? loadMaterials;
  final Future<List<GuidanceDocument>> Function(List<String> ids)?
  loadDocuments;

  /// 목표 직무 분석: latest report on this device, 일정 추가 and the 홈 summary.
  final GapReportStore? gapStore;
  final AddPreparationPlan? onAddPlan;
  final ValueChanged<GapReport>? onGapReport;

  /// Opens a purpose once (홈 → 목표 직무 분석).
  final JobPurposeRequest? purposeRequest;

  /// Saved target job; fills the 공고 찾기 search form.
  final CareerGoalController? careerGoal;

  /// Opens 자기소개서·포트폴리오 with an analysed posting (here or in 공고 찾기).
  final WriteForPosting? onWrite;

  /// The 학업 프로필 stage 공고 찾기 starts at.
  final ValueListenable<AcademicStage?>? profileStage;
  @override
  State<JobAnalysisPage> createState() => _JobAnalysisPageState();
}

class _JobAnalysisPageState extends State<JobAnalysisPage> {
  final _posting = TextEditingController();
  bool _sending = false;
  bool _requesting = false;
  int _revision = 0;
  String? _error, _requestId;
  JobAnalysisResponse? _result;

  /// Finished results kept in the account; null before signing in.
  SavedAnalysesController? _saved;

  /// When the shown result is a saved one opened from the list.
  DateTime? _openedAt;
  DateTime? _resultAt;

  /// Titles of the records sent with the last run, to name the evidence.
  Map<String, String> _recordTitles = const {};
  final _materialIds = <String>{};
  var _purpose = JobPurpose.posting;
  final _visited = <JobPurpose>{JobPurpose.posting};
  bool _recommendationBusy = false;

  bool get _connected => widget.api != null && widget.consent != null;
  bool get _canAnalyze =>
      _connected && !GuestPreviewScope.isActive(context) && !_sending;

  @override
  void initState() {
    super.initState();
    widget.careerGoal?.addListener(_goalChanged);
    _consumeRequest();
    _saved = _savedFor(widget.api);
  }

  static SavedAnalysesController? _savedFor(StudentApi? api) => api == null
      ? null
      : SavedAnalysesController(
          AnalysisResultsApi(api.api),
          AnalysisKind.posting,
        );

  Future<void> _save(
    String posting,
    JobAnalysisResponse result,
    Map<String, dynamic> raw,
  ) async {
    if (result.status != 'completed') return;
    final cited = {
      for (final row in result.comparisons)
        for (final cite in row.personalEvidence) cite.recordId,
    };
    await _saved?.save(
      title: analysisTitle(posting, fallback: '공고 1개 비교'),
      summary: {
        'ready': result.comparisons
            .where((c) => c.status == 'supported')
            .length,
        'total': result.comparisons.length,
      },
      input: {
        'posting_text': posting,
        // Names the evidence when the result is opened again.
        'record_titles': {
          for (final entry in _recordTitles.entries)
            if (cited.contains(entry.key)) entry.key: entry.value,
        },
      },
      result: raw,
    );
  }

  Future<void> _openSaved(SavedAnalysisSummary item) async {
    if (_sending) return;
    final revision = _revision;
    final saved = await _saved?.open(item.id);
    if (saved == null || !mounted || revision != _revision) return;
    try {
      final result = JobAnalysisResponse.fromJson(saved.result);
      setState(() {
        _result = result;
        _openedAt = saved.createdAt;
        _posting.text = saved.input['posting_text'] as String? ?? '';
        _recordTitles = Map<String, String>.from(
          saved.input['record_titles'] as Map? ?? const {},
        );
        _error = null;
        _requestId = null;
      });
    } catch (_) {
      setState(() => _error = '저장된 결과의 형식을 읽지 못했습니다.');
    }
  }

  void _goalChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant JobAnalysisPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.purposeRequest, widget.purposeRequest)) {
      _consumeRequest();
    }
    if (!identical(oldWidget.careerGoal, widget.careerGoal)) {
      oldWidget.careerGoal?.removeListener(_goalChanged);
      widget.careerGoal?.addListener(_goalChanged);
    }
    if (oldWidget.api?.ownerId != widget.api?.ownerId ||
        !identical(oldWidget.api?.api, widget.api?.api) ||
        !identical(oldWidget.consent, widget.consent)) {
      _revision++;
      _recommendationBusy = false;
      _sending = false;
      _requesting = false;
      _posting.clear();
      _materialIds.clear();
      _result = null;
      _openedAt = null;
      _saved?.dispose();
      _saved = _savedFor(widget.api);
      _error = null;
      _requestId = null;
    }
  }

  @override
  void dispose() {
    _saved?.dispose();
    widget.careerGoal?.removeListener(_goalChanged);
    _posting.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    if (!_canAnalyze) return;
    final revision = _revision;
    final api = widget.api!;
    final consent = widget.consent!;
    final posting = _posting.text.trim();
    setState(() {
      _error = null;
      _requestId = null;
    });
    if (posting.isEmpty || posting.runes.length > 20000) {
      setState(() => _error = '공고 본문을 1~20,000자로 입력해 주세요.');
      return;
    }
    setState(() => _sending = true);
    var readingRecords = true;
    try {
      final records = await (widget.loadRecords?.call() ?? loadAiRecords(api));
      if (!mounted ||
          revision != _revision ||
          GuestPreviewScope.isActive(context)) {
        return;
      }
      final documents = _materialIds.isEmpty || widget.loadDocuments == null
          ? const <GuidanceDocument>[]
          : await widget.loadDocuments!(_materialIds.toList());
      if (!mounted || revision != _revision) return;
      if (records.isEmpty && documents.isEmpty) {
        setState(
          () => _error = '비교할 기록이 없습니다. 수강·활동·경험·자격·성과 기록을 추가하거나 내 자료를 골라 주세요.',
        );
        return;
      }
      readingRecords = false;
      if (!await requestAiConsent(
            context,
            consent,
            AiConsentFeature.jobAnalysis,
          ) ||
          !mounted ||
          revision != _revision ||
          GuestPreviewScope.isActive(context)) {
        return;
      }
      setState(() {
        _result = null;
        _openedAt = null;
        _requesting = true;
      });
      final (result, raw) = await JobAnalysisApi(api.api).analyzeWithRaw(
        JobAnalysisRequest(
          postingText: posting,
          records: [
            for (final record in records)
              PersonalEvidenceSelection(
                kind: record.kind,
                recordId: record.id,
                expectedVersion: record.version,
              ),
          ],
          documents: [
            for (final document in documents)
              AnalysisDocument(
                filename: document.filename,
                contentBase64: document.contentBase64,
              ),
          ],
          externalProcessingConsent: true,
        ),
      );
      if (mounted &&
          revision == _revision &&
          !GuestPreviewScope.isActive(context)) {
        setState(() {
          _result = result;
          _resultAt = DateTime.now();
          _recordTitles = {for (final r in records) r.id: r.title};
        });
        // Kept in the account; a failed save leaves the result on screen.
        unawaited(_save(posting, result, raw));
      }
    } on AuthFailure catch (e) {
      if (mounted && revision == _revision) {
        setState(() {
          _error = readingRecords
              ? '저장 기록을 읽지 못했습니다. 공고 본문을 유지했습니다. 다시 실행해 주세요.'
              : e.status == 409
              ? '저장 기록이 변경되었습니다. 다시 실행하면 최신 기록을 불러옵니다.'
              : e.status == 422 &&
                    e.fields.any(
                      (field) =>
                          field.split('.').last ==
                          'external_processing_consent',
                    )
              ? '전송 동의 항목을 서버가 처리하지 못했습니다. 앱과 서버의 API 버전을 확인해 주세요. 입력은 유지했습니다.'
              : e.status == 422 &&
                    e.fields.any((field) => field.split('.').last == 'records')
              ? '서버가 전체 기록 요청을 받아들이지 못했습니다. 공고 본문은 유지했습니다.'
              : e.message;
          _requestId = e.requestId;
        });
      }
    } on StateError catch (e) {
      // 내 자료 changed on this device or the selection is over 5 files / 8 MiB.
      if (mounted && revision == _revision) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(
          () => _error = readingRecords
              ? '저장 기록을 읽지 못했습니다. 공고 본문을 유지했습니다. 다시 실행해 주세요.'
              : '분석 응답을 확인하지 못했습니다. 입력을 유지했습니다. 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted && revision == _revision) {
        setState(() {
          _sending = false;
          _requesting = false;
        });
      }
    }
  }

  String _citationLabel(
    JobAnalysisResponse result,
    PersonalEvidenceCitation citation,
  ) {
    for (final source in result.documentSources) {
      if (source.recordId == citation.recordId) {
        final ocr = source.ocr ? ' · 자동 문자 인식, 원본 확인' : '';
        return '내 자료 근거 (${source.filename} · ${source.location}$ocr): ${citation.excerpt}';
      }
    }
    if (_recordTitles[citation.recordId] case final title?) {
      return '$title · ${citation.excerpt}';
    }
    return '내 기록 근거 (버전 ${citation.version}): ${citation.excerpt}';
  }

  String _status(JobAnalysisResponse result) => switch (result.status) {
    'completed' => '분석 완료',
    'not_configured' => '분석 기능 준비 중',
    'needs_user_input' => '추가 입력 필요',
    'insufficient_evidence' => '분석 근거 부족',
    _ => '분석 실패',
  };
  String _reason(JobAnalysisResponse result) => switch (result.reason) {
    'analyzer_not_configured' => '분석 모델이 아직 설정되지 않았습니다. 입력을 유지했습니다.',
    'external_processing_consent_required' =>
      'Google 외부 전송 동의를 확인하고 다시 실행해 주세요.',
    'personal_records_required' => '비교할 수강·활동·경험·자격·성과 기록을 추가해 주세요.',
    'no_requirements_found' => '공고에서 비교할 요건을 찾지 못했습니다.',
    _ => '분석을 완료하지 못했습니다. 입력을 유지하고 다시 시도할 수 있습니다.',
  };
  void _select(JobPurpose purpose) => setState(() {
    _purpose = purpose;
    _visited.add(purpose);
  });

  void _consumeRequest() {
    final request = widget.purposeRequest;
    if (request != null && request.consume()) {
      _purpose = request.purpose;
      _visited.add(request.purpose);
    }
  }

  @override
  Widget build(BuildContext context) => PageTabsScope(
    // The three purposes are sibling pages: their titles are the tabs.
    data: PageTabsData(
      labels: [for (final purpose in JobPurpose.values) purpose.label],
      selected: JobPurpose.values.indexOf(_purpose),
      onSelected: (i) => _select(JobPurpose.values[i]),
      enabled: !_sending && !_recommendationBusy,
      groupKey: const ValueKey('job-purpose-tabs'),
      tabKeys: [
        for (final purpose in JobPurpose.values)
          ValueKey('job-purpose-${purpose.name}'),
      ],
    ),
    child: IndexedStack(
      index: switch (_purpose) {
        JobPurpose.posting => 0,
        JobPurpose.search => 1,
        JobPurpose.gap => 2,
      },
      children: [
        _buildAnalysis(context),
        if (_visited.contains(JobPurpose.search))
          JobRecommendationPage(
            goal: widget.careerGoal?.goal,
            onWrite: widget.onWrite,
            profileStage: widget.profileStage,
            api: widget.api,
            consent: widget.consent,
            loadRecords: widget.loadRecords,
            loadMaterials: widget.loadMaterials,
            loadDocuments: widget.loadDocuments,
            onBusyChanged: (busy) {
              if (mounted) setState(() => _recommendationBusy = busy);
            },
          )
        else
          const SizedBox.shrink(),
        if (_visited.contains(JobPurpose.gap))
          CareerGapView(
            api: widget.api,
            consent: widget.consent,
            careerGoal: widget.careerGoal,
            store: widget.gapStore,
            loadRecords: widget.loadRecords,
            onAddPlan: widget.onAddPlan,
            onReport: widget.onGapReport,
          )
        else
          const SizedBox.shrink(),
      ],
    ),
  );

  Widget _buildAnalysis(BuildContext context) {
    final theme = Theme.of(context);
    return FeaturePage(
      title: '채용공고 분석',
      body: [
        WorkLayout(
          input: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FieldLabel(
                      label: '채용공고 본문',
                      child: TextFormField(
                        key: const ValueKey('job-posting-text'),
                        controller: _posting,
                        enabled: !_sending,
                        minLines: 12,
                        maxLines: 24,
                        decoration: const InputDecoration(
                          hintText: '비교할 공고 본문을 붙여 넣으세요.',
                        ),
                      ),
                    ),
                    if (widget.loadMaterials != null && _connected) ...[
                      const SizedBox(height: 16),
                      MaterialSelection(
                        keyPrefix: 'job-analysis',
                        load: widget.loadMaterials!,
                        selected: _materialIds,
                        enabled: !_sending,
                        onChanged: (id, selected) => setState(
                          () => selected
                              ? _materialIds.add(id)
                              : _materialIds.remove(id),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (!_connected)
                      const NoteLine(
                        icon: Icons.lock_outline,
                        text: '채용 분석을 사용하려면 로그인해 주세요. 공고와 개인 기록은 전송하지 않았습니다.',
                      ),
                    if (widget.consent != null)
                      AnimatedBuilder(
                        animation: widget.consent!,
                        builder: (context, _) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            NoteLine(
                              icon: Icons.cloud_upload_outlined,
                              text:
                                  widget.consent!.allows(
                                    AiConsentFeature.jobAnalysis,
                                  )
                                  ? 'Google 외부 AI 전송 허용 중 · 설정에서 변경'
                                  : 'Google 외부 AI 전송 · 실행 전 동의 확인',
                              detail: '공고 본문, 저장된 수강·활동·경험·자격·성과 기록 전체, 고른 내 자료를 비교에 사용합니다.',
                            ),
                            if (widget.consent!.error != null)
                              Text(widget.consent!.error!),
                            if (widget.consent!.loadFailed)
                              TextButton(
                                onPressed: widget.consent!.retry,
                                child: const Text('전송 설정 다시 읽기'),
                              ),
                          ],
                        ),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    if (_requestId != null)
                      SelectableText('문의 식별자: $_requestId'),
                    const SizedBox(height: 16),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: FilledButton.icon(
                        key: const ValueKey('job-analysis-run'),
                        onPressed: _canAnalyze ? _analyze : null,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: Text(_sending ? '분석 중…' : '공고 분석'),
                      ),
                    ),
                    if (_requesting) ...[
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
                  enabled: !_sending,
                  onOpen: _openSaved,
                ),
              ],
            ],
          ),
          result: _result == null ? null : _resultCard(context, _result!),
          placeholder: const ResultPlaceholder(
            icon: Icons.fact_check_outlined,
            title: '공고를 붙여 넣고 분석하면 비교 결과가 여기에 나옵니다',
          ),
        ),
      ],
    );
  }

  Widget _resultCard(BuildContext context, JobAnalysisResponse result) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tone = switch (result.status) {
      'completed' => AppTone.success,
      'needs_user_input' || 'insufficient_evidence' => AppTone.warning,
      'not_configured' => AppTone.neutral,
      _ => AppTone.danger,
    };
    List<JobRequirementComparison> group(String priority) =>
        result.comparisons.where((c) => c.priority == priority).toList()..sort(
          (a, b) =>
              RequirementStatus.parse(a.status).order
                  .compareTo(RequirementStatus.parse(b.status).order),
        );
    (int, int) coverage(List<JobRequirementComparison> items) =>
        (items.where((c) => c.status == 'supported').length, items.length);
    final required = group('required'), preferred = group('preferred');
    final write = widget.onWrite;
    final text = _posting.text.trim();
    Widget grid(List<JobRequirementComparison> items) => ResponsiveGrid(
      targetItemWidth: 420,
      minItemWidth: 320,
      maxColumns: 3,
      minHeightFactor: 0,
      children: [for (final item in items) _comparison(context, result, item)],
    );
    return SurfaceCard(
      key: const ValueKey('job-analysis-result'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('비교 결과', style: theme.textTheme.titleMedium),
                  const SizedBox(width: 10),
                  ToneChip(label: _status(result), tone: tone),
                  if (_saved case final saved?) ...[
                    const SizedBox(width: 4),
                    SavedAnalysisStar(controller: saved),
                  ],
                ],
              ),
              if (write != null && text.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final type in WritingType.values)
                      FilledButton.tonalIcon(
                        key: ValueKey('job-analysis-write-${type.value}'),
                        onPressed: _sending
                            ? null
                            : () => write(
                                PostingLink.fromJobAnalysis(
                                  text,
                                  result,
                                  analyzedAt: _openedAt ?? _resultAt,
                                ),
                                type,
                              ),
                        icon: Icon(
                          type == WritingType.coverLetter
                              ? Icons.edit_note_outlined
                              : Icons.folder_open_outlined,
                        ),
                        label: Text('이 공고로 ${type.label} 쓰기'),
                      ),
                  ],
                ),
            ],
          ),
          if (_openedAt != null) ...[
            const SizedBox(height: 8),
            NoteLine(
              key: const ValueKey('job-analysis-opened'),
              icon: Icons.history,
              text: '저장된 결과 · ${savedAnalysisTime(_openedAt)} 분석',
            ),
          ],
          if (result.status != 'completed') ...[
            const SizedBox(height: 8),
            Text(_reason(result)),
          ],
          // Records left out over the text budget, or items that could not be verified.
          for (final warning in result.warnings) ...[
            const SizedBox(height: 8),
            Text(
              warning,
              key: const ValueKey('job-analysis-warning'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          if (result.comparisons.isNotEmpty) ...[
            const SizedBox(height: 16),
            ReadinessSummary(
              statuses: [
                for (final c in result.comparisons)
                  RequirementStatus.parse(c.status),
              ],
              required: coverage(required),
              preferred: coverage(preferred),
            ),
            if (required.isNotEmpty) ...[
              RequirementGroupHeading(title: '필수 요건', count: required.length),
              grid(required),
            ],
            if (preferred.isNotEmpty) ...[
              RequirementGroupHeading(title: '우대 요건', count: preferred.length),
              grid(preferred),
            ],
          ],
        ],
      ),
    );
  }

  Widget _comparison(
    BuildContext context,
    JobAnalysisResponse result,
    JobRequirementComparison item,
  ) {
    final required = item.priority == 'required';
    return RequirementCard(
      key: ValueKey('job-analysis-requirement-${item.requirementId}'),
      requirement: item.requirement,
      status: RequirementStatus.parse(item.status),
      explanation: item.explanation,
      chips: [
        ToneChip(
          label: required ? '필수' : '우대',
          tone: required ? AppTone.accent : AppTone.info,
        ),
      ],
      evidence: [
        for (final citation in item.personalEvidence)
          _citationLabel(result, citation),
      ],
      postingEvidence: ['공고 근거: ${item.postingEvidence.excerpt}'],
    );
  }
}

/// What 채용공고 분석 shows; 공고 1개 비교 stays the default.
enum JobPurpose {
  gap('목표 직무 분석'),
  posting('공고 1개 비교'),
  search('내 자료로 공고 찾기');

  const JobPurpose(this.label);
  final String label;
}

class JobPurposeRequest extends PendingUiAction {
  JobPurposeRequest(this.purpose);
  final JobPurpose purpose;
}
