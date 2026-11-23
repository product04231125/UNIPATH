import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../shared/widgets/feature_page.dart';
import '../../../shared/widgets/field_label.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../api/job_analysis_models.dart';
import '../../api/job_recommendation_api.dart';
import '../../career/career_goal.dart';
import '../../career/saved_analyses.dart';
import '../../career/job_category_fields.dart';
import '../../api/student_api.dart';
import '../../assistant/ai_record_catalog.dart';
import '../../auth/auth_api.dart';
import '../../auth/guest_preview_scope.dart';
import '../../settings/ai_consent_preferences.dart';
import '../../settings/ai_consent_section.dart';
import '../../api/academic_guidance_models.dart';
import 'job_recommendation_result.dart';
import 'material_selection.dart';
import '../../../shared/widgets/work_layout.dart';

const recommendationMaxBytes = 8 * 1024 * 1024;
Widget _surface({required Widget child}) => SurfaceCard(
  child: Material(type: MaterialType.transparency, child: child),
);
const recommendationExtensions = [
  'pdf',
  'docx',
  'txt',
  'md',
  'png',
  'jpg',
  'jpeg',
  'webp',
];

Future<List<XFile>> pickRecommendationFiles() => openFiles(
  acceptedTypeGroups: const [
    XTypeGroup(label: '개인 증빙자료', extensions: recommendationExtensions),
  ],
);

class JobRecommendationPage extends StatefulWidget {
  const JobRecommendationPage({
    super.key,
    this.api,
    this.consent,
    this.loadRecords,
    this.pickFiles,
    this.onBack,
    this.onBusyChanged,
    this.loadMaterials,
    this.loadDocuments,
    this.goal,
  });
  final StudentApi? api;

  /// The saved target job; fills an untouched search form.
  final CareerGoal? goal;
  final AiConsentPreferences? consent;
  final Future<List<AiRecordOption>> Function()? loadRecords;
  final Future<List<XFile>> Function()? pickFiles;
  final VoidCallback? onBack;
  final ValueChanged<bool>? onBusyChanged;
  // 내 자료 on this device; only the ones the student selects are sent.
  final Future<List<AssistantMaterial>> Function()? loadMaterials;
  final Future<List<GuidanceDocument>> Function(List<String> ids)?
  loadDocuments;
  @override
  State<JobRecommendationPage> createState() => _JobRecommendationPageState();
}

class _JobRecommendationPageState extends State<JobRecommendationPage> {
  final _keyword = TextEditingController();
  var _form = GlobalKey<FormState>();
  String? _error, _requestId;

  /// `전국` alone, or one or more regions searched together.
  final _regions = <String>{};
  List<String> get _orderedRegions => [
    for (final name in recommendationRegions)
      if (_regions.contains(name)) name,
  ];
  String get _regionLabel => _regions.contains(nationwideRegion)
      ? nationwideRegion
      : _orderedRegions.join('·');
  Future<List<JobCategory>>? _categories;
  String _categoryCode = '', _subcategoryCode = '';
  String get _selectedCode =>
      _subcategoryCode.isEmpty ? _categoryCode : _subcategoryCode;
  RecommendationAcademicStage? _academicStage;
  final _documents = <RecommendationDocument>[];
  final _materialIds = <String>{};
  bool _busy = false;
  int _revision = 0;
  JobRecommendationResponse? _result;
  List<AiRecordOption> _resultRecords = const [];

  /// Finished searches kept in the account; null before signing in.
  SavedAnalysesController? _saved;
  DateTime? _openedAt;

  static SavedAnalysesController? _savedFor(StudentApi? api) => api == null
      ? null
      : SavedAnalysesController(
          AnalysisResultsApi(api.api),
          AnalysisKind.search,
        );

  Future<void> _save(
    JobRecommendationResponse result,
    List<AiRecordOption> records,
    String region,
  ) async {
    if (result.items.isEmpty) return;
    // Record titles name the evidence when the result is opened again; keep the cited ones.
    final text = jsonEncode(result.raw);
    final cited = [
      for (final r in records)
        if (text.contains(r.id)) r,
    ];
    final title = [
      ?result.occupationLabel,
      if (result.queryKeyword?.isNotEmpty ?? false) result.queryKeyword!,
      region,
    ].where((s) => s.isNotEmpty).join(' · ');
    await _saved?.save(
      title: analysisTitle(title, fallback: '내 자료로 공고 찾기'),
      summary: {'postings': result.items.length},
      input: {
        'keyword': _keyword.text.trim(),
        'region': region,
        'category_codes': [if (_selectedCode.isNotEmpty) _selectedCode],
        'records': [for (final r in cited) r.toJson()],
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
      final result = JobRecommendationResponse.fromJson(saved.result);
      final records = [
        for (final raw in saved.input['records'] as List? ?? const [])
          AiRecordOption.fromJson(Map<String, dynamic>.from(raw as Map)),
      ];
      setState(() {
        _result = result;
        _resultRecords = records;
        _openedAt = saved.createdAt;
        _error = null;
        _requestId = null;
      });
    } catch (_) {
      setState(() => _error = '저장된 결과의 형식을 읽지 못했습니다.');
    }
  }

  List<String> _fields = const [];

  @override
  void initState() {
    super.initState();
    _applyGoal();
    _saved = _savedFor(widget.api);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateCategoryAccess();
  }

  // The goal values last put into the form; the form counts as untouched while it still has them.
  (String, String, String)? _goalValues;
  var _goalRevision = 0;

  void _applyGoal() {
    final goal = widget.goal;
    if (goal == null || !goal.isSet) return;
    final current = (_categoryCode, _subcategoryCode, _keyword.text.trim());
    final untouched = current == ('', '', '') || current == _goalValues;
    final next = (goal.topCode, goal.subCode, goal.keyword);
    if (!untouched || next == current) return;
    _categoryCode = goal.topCode;
    _subcategoryCode = goal.subCode;
    _keyword.text = goal.keyword;
    _goalValues = next;
    _goalRevision++;
  }

  void _updateCategoryAccess() {
    final api = widget.api;
    if (GuestPreviewScope.isActive(context) || api == null) {
      _categories = null;
      _categoryCode = '';
      _subcategoryCode = '';
    } else {
      _categories ??= JobRecommendationApi(api.api).loadCategories();
    }
  }

  @override
  void didUpdateWidget(covariant JobRecommendationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api?.ownerId != widget.api?.ownerId ||
        !identical(oldWidget.api?.api, widget.api?.api) ||
        !identical(oldWidget.consent, widget.consent)) {
      _revision++;
      _form = GlobalKey<FormState>();
      _busy = false;
      _regions.clear();
      _categories = null;
      _categoryCode = '';
      _subcategoryCode = '';
      _updateCategoryAccess();
      _academicStage = null;
      _keyword.clear();
      _documents.clear();
      _materialIds.clear();
      _result = null;
      _resultRecords = const [];
      _openedAt = null;
      _saved?.dispose();
      _saved = _savedFor(widget.api);
      _error = null;
      _requestId = null;
      _fields = [];
      _goalValues = null;
      _applyGoal();
    } else if (widget.goal != oldWidget.goal) {
      _applyGoal();
    }
  }

  @override
  void dispose() {
    _saved?.dispose();
    _keyword.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_busy) return;
    final revision = _revision;
    setState(() {
      _busy = true;
      _error = null;
    });
    widget.onBusyChanged?.call(true);
    try {
      final files = await (widget.pickFiles ?? pickRecommendationFiles)();
      if (!mounted || revision != _revision) return;
      if (_documents.length + files.length > 5) {
        throw const AuthFailure('파일은 최대 5개까지 선택하세요.');
      }
      final next = <RecommendationDocument>[];
      var total = _documents.fold(0, (n, d) => n + d.bytes.length);
      for (final file in files) {
        if (!recommendationExtensions.contains(
          file.name.split('.').last.toLowerCase(),
        )) {
          throw const AuthFailure('PDF·DOCX·TXT·MD·PNG·JPEG·WebP 파일을 선택하세요.');
        }
        final length = await file.length();
        if (file.name.length > 200 ||
            length == 0 ||
            total + length > recommendationMaxBytes) {
          throw const AuthFailure('빈 파일은 제외하고 파일명 200자·합계 8MiB 이하로 선택하세요.');
        }
        final bytes = await file.readAsBytes();
        total += bytes.length;
        if (bytes.isEmpty || total > recommendationMaxBytes) {
          throw const AuthFailure('파일 합계는 8MiB 이하여야 합니다.');
        }
        next.add(RecommendationDocument(file.name, bytes));
      }
      if (mounted && revision == _revision) {
        setState(() => _documents.addAll(next));
      }
    } on AuthFailure catch (e) {
      if (mounted && revision == _revision) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(() => _error = '파일을 읽지 못했습니다. 기존 선택은 유지했습니다.');
      }
    } finally {
      if (mounted && revision == _revision) {
        setState(() => _busy = false);
        widget.onBusyChanged?.call(false);
      }
    }
  }

  Future<void> _run() async {
    if (_busy ||
        widget.api == null ||
        widget.consent == null ||
        GuestPreviewScope.isActive(context)) {
      return;
    }
    setState(() {
      _error = null;
      _fields = [];
      _requestId = null;
    });
    if (!_form.currentState!.validate()) return;
    final revision = _revision;
    final api = widget.api!;
    final consent = widget.consent!;
    setState(() => _busy = true);
    widget.onBusyChanged?.call(true);
    var readingRecords = true;
    try {
      final records = await (widget.loadRecords?.call() ?? loadAiRecords(api));
      if (!mounted ||
          revision != _revision ||
          GuestPreviewScope.isActive(context)) {
        return;
      }
      final materials = _materialIds.isEmpty || widget.loadDocuments == null
          ? const <GuidanceDocument>[]
          : await widget.loadDocuments!(_materialIds.toList());
      if (!mounted || revision != _revision) return;
      final documents = [
        ..._documents,
        for (final m in materials)
          RecommendationDocument(m.filename, base64Decode(m.contentBase64)),
      ];
      if (documents.length > 5 ||
          documents.fold(0, (n, d) => n + d.bytes.length) > 8 * 1024 * 1024) {
        setState(() => _error = '기기 파일과 내 자료는 합계 5개·8MiB 이내로 골라 주세요.');
        return;
      }
      if (documents.isEmpty && records.isEmpty) {
        setState(
          () => _error = '기기 파일이나 내 자료를 고르거나 수강·활동·경험·자격·성과 기록을 등록해 주세요.',
        );
        return;
      }
      readingRecords = false;
      final request = JobRecommendationRequest(
        keyword: _keyword.text.trim(),
        categoryCodes: _selectedCode.isEmpty ? const [] : [_selectedCode],
        region: _regionLabel,
        regions: _orderedRegions,
        academicStage: _academicStage,
        documents: documents,
        records: [
          for (final record in records)
            PersonalEvidenceSelection(
              kind: record.kind,
              recordId: record.id,
              expectedVersion: record.version,
            ),
        ],
        consent: true,
      );
      if (!await requestAiConsent(
            context,
            consent,
            AiConsentFeature.jobRecommendation,
          ) ||
          !mounted ||
          revision != _revision ||
          GuestPreviewScope.isActive(context)) {
        return;
      }
      setState(() {
        _result = null;
        _openedAt = null;
      });
      final result = await JobRecommendationApi(api.api).recommend(request);
      if (mounted &&
          revision == _revision &&
          !GuestPreviewScope.isActive(context)) {
        setState(() {
          _result = result;
          _resultRecords = records;
        });
        // Kept in the account; a failed save leaves the result on screen.
        unawaited(_save(result, records, request.region));
      }
    } on AuthFailure catch (e) {
      if (mounted && revision == _revision) {
        setState(() {
          _error = readingRecords
              ? '저장 기록을 읽지 못했습니다. 입력과 첨부 파일을 유지했습니다. 다시 실행해 주세요.'
              : switch (e.status) {
                  404 =>
                    '공고 추천 API가 연결되지 않았거나 선택 자료를 찾을 수 없습니다. 입력과 선택은 유지했습니다.',
                  409 => '저장 기록이 변경되었습니다. 다시 실행하면 최신 기록을 불러옵니다.',
                  413 => '파일 용량이 서버 업로드 한도를 넘었습니다. 파일을 줄여 다시 시도하세요.',
                  422
                      when e.fields.any(
                        (field) => field.split('.').last == 'records',
                      ) =>
                    '서버가 전체 기록 요청을 받아들이지 못했습니다. 입력과 첨부 파일은 유지했습니다.',
                  422 => '검색 조건과 파일 형식·분량·판독 가능 여부를 확인하세요.',
                  503 => '문서 인식 서버를 사용할 수 없습니다. 잠시 후 다시 시도하세요.',
                  _ => e.message,
                };
          _fields = e.fields;
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
              ? '저장 기록을 읽지 못했습니다. 입력과 첨부 파일을 유지했습니다. 다시 실행해 주세요.'
              : '추천 응답을 확인하지 못했습니다. 입력과 첨부 파일은 유지했습니다.',
        );
      }
    } finally {
      if (mounted && revision == _revision) {
        setState(() => _busy = false);
        widget.onBusyChanged?.call(false);
      }
    }
  }

  bool _hasField(String name) =>
      _fields.any((f) => f.split('.').contains(name));

  String? _validateKeyword(String? value) {
    final keyword = value?.trim() ?? '';
    if (keyword.isEmpty) {
      return _selectedCode.isEmpty ? '직종을 선택하거나 세부 검색어를 입력하세요.' : null;
    }
    if (keyword.runes.length > 80) {
      return '세부 검색어를 80자 이내로 입력하세요.';
    }
    final terms = keyword
        .split(RegExp(r'[,，\n]+'))
        .map(
          (term) => term.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase(),
        )
        .where((term) => term.isNotEmpty)
        .toSet();
    if (terms.contains('벡엔드') && terms.contains('백엔드')) {
      terms.remove('벡엔드');
    }
    return terms.isEmpty || terms.length > 5
        ? '세부 검색어를 쉼표로 구분해 1~5개 입력하세요.'
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final region = FormField<Set<String>>(
      key: const ValueKey('recommend-region'),
      validator: (_) => _regions.isEmpty ? '근무 지역을 선택하세요.' : null,
      builder: (state) => FieldLabel(
        label: '근무 지역 (여러 곳 선택 가능)',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final name in [nationwideRegion, ...recommendationRegions])
                  FilterChip(
                    key: ValueKey('recommend-region-$name'),
                    label: Text(name),
                    selected: _regions.contains(name),
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: _busy
                        ? null
                        : (on) {
                            setState(() {
                              // 전국 and individual regions exclude each other.
                              if (name == nationwideRegion) {
                                _regions.clear();
                              } else {
                                _regions.remove(nationwideRegion);
                              }
                              on ? _regions.add(name) : _regions.remove(name);
                            });
                            state.didChange(_regions);
                          },
                  ),
              ],
            ),
            if (state.errorText != null || _hasField('region'))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  state.errorText ?? '지역을 확인하세요.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    final stage = FieldLabel(
      label: '현재 학년 (선택)',
      child: DropdownButtonFormField<RecommendationAcademicStage>(
        key: const ValueKey('recommend-academic-stage'),
        initialValue: _academicStage,
        isExpanded: true,
        decoration: InputDecoration(
          errorText: _hasField('academic_stage') ? '선택한 학년을 확인하세요.' : null,
        ),
        items: [
          const DropdownMenuItem(child: Text('선택 안 함')),
          for (final stage in RecommendationAcademicStage.values)
            DropdownMenuItem(value: stage, child: Text(stage.label)),
        ],
        onChanged: _busy
            ? null
            : (stage) => setState(() => _academicStage = stage),
      ),
    );
    final input = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _surface(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_categories case final future?)
                  JobCategoryFields(
                    key: ValueKey('recommend-goal-$_goalRevision'),
                    future: future,
                    categoryCode: _categoryCode,
                    subcategoryCode: _subcategoryCode,
                    enabled: !_busy,
                    error: _hasField('category_codes')
                        ? '선택한 직종을 확인하세요.'
                        : null,
                    onChanged: (category, subcategory) => setState(() {
                      _categoryCode = category;
                      _subcategoryCode = subcategory;
                    }),
                    onRetry: () => setState(() {
                      _categories = JobRecommendationApi(widget.api!.api)
                          .loadCategories();
                    }),
                  ),
                FieldLabel(
                  label: '세부 검색어',
                  child: TextFormField(
                    controller: _keyword,
                    enabled: !_busy,
                    key: const ValueKey('recommend-keyword'),
                    decoration: InputDecoration(
                      hintText: '예: 프론트엔드, 백엔드, 전산실',
                      helperText: _selectedCode.isEmpty
                          ? '직종을 선택하거나 검색어를 쉼표로 구분해 최대 5개 입력하세요.'
                          : '선택한 직종 전체를 검색하려면 비워 두세요.',
                      helperMaxLines: 2,
                      errorText: _hasField('keyword') ? '세부 검색어를 확인하세요.' : null,
                    ),
                    validator: _validateKeyword,
                  ),
                ),
                const SizedBox(height: 16),
                region,
                const SizedBox(height: 16),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: stage,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('비교할 기기 파일 (선택)', style: theme.textTheme.titleSmall),
                  const SizedBox(width: 4),
                  Tooltip(
                    message:
                        '저장 기록은 분석할 때 자동으로 포함합니다. 함께 비교할 기기 파일을 추가할 수 있습니다.\n'
                        'PDF·DOCX·TXT/MD·PNG/JPEG/WebP. PDF당 100쪽·OCR 합계 20장까지 서버에서 처리합니다.',
                    triggerMode: TooltipTriggerMode.tap,
                    child: Icon(
                      Icons.info_outline,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.attach_file),
                    label: const Text('기기 파일 선택'),
                  ),
                  Text(
                    '${_documents.length}/5개 · ${(_documents.fold(0, (n, d) => n + d.bytes.length) / 1024 / 1024).toStringAsFixed(1)}/8MiB',
                    style: muted,
                  ),
                ],
              ),
              for (final doc in _documents)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(doc.filename),
                  trailing: IconButton(
                    tooltip: '${doc.filename} 선택 해제',
                    onPressed: _busy
                        ? null
                        : () => setState(() => _documents.remove(doc)),
                    icon: const Icon(Icons.close),
                  ),
                ),
              if (_hasField('documents')) const Text('선택 파일의 형식과 분량을 확인하세요.'),
              if (widget.loadMaterials != null &&
                  widget.api != null &&
                  widget.consent != null) ...[
                const Divider(height: 28),
                MaterialSelection(
                  keyPrefix: 'job-recommendation',
                  load: widget.loadMaterials!,
                  selected: _materialIds,
                  enabled: !_busy,
                  onChanged: (id, selected) => setState(
                    () => selected
                        ? _materialIds.add(id)
                        : _materialIds.remove(id),
                  ),
                ),
              ],
              const Divider(height: 28),
              const NoteLine(
                icon: Icons.cloud_upload_outlined,
                text: '내 기록과 고른 파일을 외부 AI로 보내 공고와 비교합니다',
                detail: '저장된 수강·활동·경험·자격·성과 기록과 첨부 파일의 텍스트를 외부 Gemini에 보내 공고와 비교합니다. 다른 사람의 이름이나 민감한 정보가 없는지 확인하세요.',
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
              if (_requestId != null) SelectableText('문의 식별자: $_requestId'),
              const SizedBox(height: 16),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.icon(
                  onPressed:
                      _busy ||
                          widget.api == null ||
                          widget.consent == null ||
                          GuestPreviewScope.isActive(context)
                      ? null
                      : _run,
                  icon: const Icon(Icons.travel_explore_outlined),
                  label: Text(_busy ? '자료 확인·공고 비교 중…' : '분석 실행'),
                ),
              ),
              if (_busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                const SizedBox(height: 6),
                Text(
                  '파일 처리와 공고 비교에 시간이 걸릴 수 있습니다. 같은 요청을 자동으로 다시 보내지 않습니다.',
                  style: muted,
                ),
              ],
            ],
          ),
        ),
      ],
    );
    return FeaturePage(
      title: '내 자료로 공고 찾기',
      body: [
        if (widget.onBack != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : widget.onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('공고 본문 분석으로 돌아가기'),
            ),
          ),
        WorkLayout(
          input: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              input,
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
          result: _result == null
              ? null
              : JobRecommendationResult(
                  result: _result!,
                  selectedRecords: _resultRecords,
                  titleTrailing: _saved == null
                      ? null
                      : Padding(
                          padding: const EdgeInsetsDirectional.only(start: 4),
                          child: SavedAnalysisStar(controller: _saved!),
                        ),
                  openedNote: _openedAt == null
                      ? null
                      : '저장된 결과 · ${savedAnalysisTime(_openedAt)} 분석',
                  // Offered only while the form still has the category that found nothing.
                  onBrowseCategory:
                      _busy ||
                          _result!.occupationCodes.length != 1 ||
                          _result!.occupationCodes.single != _selectedCode
                      ? null
                      : () {
                          _keyword.clear();
                          _run();
                        },
                ),
          placeholder: const ResultPlaceholder(
            icon: Icons.travel_explore_outlined,
            title: '조건을 고르고 분석하면 맞는 공고가 여기에 나옵니다',
          ),
        ),
      ],
    );
  }
}
