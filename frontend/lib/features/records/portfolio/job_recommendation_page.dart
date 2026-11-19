import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../shared/widgets/feature_page.dart';
import '../../../shared/widgets/field_label.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../api/job_analysis_models.dart';
import '../../api/job_recommendation_api.dart';
import '../../api/student_api.dart';
import '../../assistant/ai_record_catalog.dart';
import '../../auth/auth_api.dart';
import '../../auth/guest_preview_scope.dart';
import '../../settings/ai_consent_preferences.dart';
import '../../settings/ai_consent_section.dart';
import 'job_recommendation_result.dart';

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
    this.purposeSelector,
  });
  final StudentApi? api;
  final AiConsentPreferences? consent;
  final Future<List<AiRecordOption>> Function()? loadRecords;
  final Future<List<XFile>> Function()? pickFiles;
  final VoidCallback? onBack;
  final Widget? purposeSelector;
  final ValueChanged<bool>? onBusyChanged;
  @override
  State<JobRecommendationPage> createState() => _JobRecommendationPageState();
}

class _JobRecommendationPageState extends State<JobRecommendationPage> {
  final _keyword = TextEditingController();
  var _form = GlobalKey<FormState>();
  String? _region, _error, _requestId;
  RecommendationAcademicStage? _academicStage;
  final _documents = <RecommendationDocument>[];
  bool _busy = false;
  int _revision = 0;
  JobRecommendationResponse? _result;
  List<AiRecordOption> _resultRecords = const [];
  List<String> _fields = const [];

  @override
  void didUpdateWidget(covariant JobRecommendationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api?.ownerId != widget.api?.ownerId ||
        !identical(oldWidget.api?.api, widget.api?.api) ||
        !identical(oldWidget.consent, widget.consent)) {
      _revision++;
      _form = GlobalKey<FormState>();
      _busy = false;
      _region = null;
      _academicStage = null;
      _keyword.clear();
      _documents.clear();
      _result = null;
      _resultRecords = const [];
      _error = null;
      _requestId = null;
      _fields = [];
    }
  }

  @override
  void dispose() {
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
      final records =
          await (widget.loadRecords?.call() ??
              loadAiRecords(api, includeCourses: false));
      if (!mounted ||
          revision != _revision ||
          GuestPreviewScope.isActive(context)) {
        return;
      }
      if (_documents.isEmpty && records.isEmpty) {
        setState(() => _error = '기기 파일을 첨부하거나 활동·경험·자격·성과 기록을 등록해 주세요.');
        return;
      }
      readingRecords = false;
      final request = JobRecommendationRequest(
        keyword: _keyword.text.trim(),
        region: _region!,
        academicStage: _academicStage,
        documents: List.of(_documents),
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
      setState(() => _result = null);
      final result = await JobRecommendationApi(api.api).recommend(request);
      if (mounted &&
          revision == _revision &&
          !GuestPreviewScope.isActive(context)) {
        setState(() {
          _result = result;
          _resultRecords = records;
        });
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
    if (keyword.isEmpty || keyword.runes.length > 80) {
      return '직무를 1~80자로 입력하세요.';
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
    return terms.isEmpty || terms.length > 5 ? '직무를 쉼표로 구분해 1~5개 입력하세요.' : null;
  }

  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '내 자료로 공고 찾기',
    description: '직무와 지역을 고르고, 내 자료에서 확인된 근거로 공고를 비교합니다.',
    body: [
      if (widget.purposeSelector != null) widget.purposeSelector!,
      if (widget.onBack != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : widget.onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('공고 본문 분석으로 돌아가기'),
          ),
        ),
      _surface(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FieldLabel(
                label: '찾는 직무',
                child: TextFormField(
                  controller: _keyword,
                  enabled: !_busy,
                  key: const ValueKey('recommend-keyword'),
                  decoration: InputDecoration(
                    hintText: '예: 프론트엔드, 백엔드, 전산실',
                    helperText: '쉼표로 구분해 최대 5개 직무를 입력할 수 있습니다.',
                    helperMaxLines: 2,
                    errorText: _hasField('keyword') ? '직무 입력을 확인하세요.' : null,
                  ),
                  validator: _validateKeyword,
                ),
              ),
              const SizedBox(height: 16),
              FieldLabel(
                label: '근무 지역',
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('recommend-region'),
                  initialValue: _region,
                  decoration: InputDecoration(
                    hintText: '지역을 직접 선택하세요.',
                    errorText: _hasField('region') ? '지역을 확인하세요.' : null,
                  ),
                  items: const [
                    DropdownMenuItem(value: '전국', child: Text('전국')),
                    DropdownMenuItem(
                      value: '지역',
                      enabled: false,
                      child: Text('특정 지역 · 준비 중'),
                    ),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _region = v),
                  validator: (v) => v == null ? '근무 지역을 선택하세요.' : null,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '특정 지역 검색은 지역 목록 연결 후 제공됩니다. 현재는 전국을 직접 선택해 검색할 수 있습니다.',
              ),
              const SizedBox(height: 16),
              FieldLabel(
                label: '현재 학년 (선택)',
                child: DropdownButtonFormField<RecommendationAcademicStage>(
                  key: const ValueKey('recommend-academic-stage'),
                  initialValue: _academicStage,
                  isExpanded: true,
                  decoration: InputDecoration(
                    helperText: '선택한 학년에 맞춰 다음 준비 활동을 안내합니다.',
                    helperMaxLines: 2,
                    errorText: _hasField('academic_stage')
                        ? '선택한 학년을 확인하세요.'
                        : null,
                  ),
                  items: const [
                    DropdownMenuItem(child: Text('선택 안 함')),
                    DropdownMenuItem(
                      value: RecommendationAcademicStage.year1,
                      child: Text('1학년'),
                    ),
                    DropdownMenuItem(
                      value: RecommendationAcademicStage.year2,
                      child: Text('2학년'),
                    ),
                    DropdownMenuItem(
                      value: RecommendationAcademicStage.year3,
                      child: Text('3학년'),
                    ),
                    DropdownMenuItem(
                      value: RecommendationAcademicStage.year4,
                      child: Text('4학년'),
                    ),
                    DropdownMenuItem(
                      value: RecommendationAcademicStage.graduate,
                      child: Text('졸업'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (stage) => setState(() => _academicStage = stage),
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
            Text(
              '비교할 기기 파일 (선택)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text('저장 기록은 분석할 때 자동으로 포함합니다. 함께 비교할 기기 파일을 추가할 수 있습니다.'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('기기 파일 선택'),
                ),
                Text(
                  '${_documents.length}/5개 · ${(_documents.fold(0, (n, d) => n + d.bytes.length) / 1024 / 1024).toStringAsFixed(1)}/8MiB',
                ),
              ],
            ),
            const Text(
              'PDF·DOCX·TXT/MD·PNG/JPEG/WebP. PDF당 100쪽·OCR 합계 20장까지 서버에서 처리합니다.',
            ),
            for (final doc in _documents)
              ListTile(
                contentPadding: EdgeInsets.zero,
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
          ],
        ),
      ),
      const SizedBox(height: 16),
      _surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '저장된 활동·경험·자격·성과 기록과 첨부 파일의 텍스트를 외부 Gemini에 보내 공고와 비교합니다. 다른 사람의 이름이나 민감한 정보가 없는지 확인하세요.',
            ),
            if (widget.api == null || widget.consent == null)
              const Text('로그인 후 이용할 수 있습니다.'),
            if (GuestPreviewScope.isActive(context))
              const Text('게스트 미리보기에서는 자료를 전송하지 않습니다.'),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_requestId != null) SelectableText('문의 식별자: $_requestId'),
            FilledButton(
              onPressed:
                  _busy ||
                      widget.api == null ||
                      widget.consent == null ||
                      GuestPreviewScope.isActive(context)
                  ? null
                  : _run,
              child: Text(_busy ? '자료 확인·공고 비교 중…' : '분석 실행'),
            ),
            if (_busy) ...[
              const LinearProgressIndicator(),
              const Text(
                '파일 처리와 공고 비교에 시간이 걸릴 수 있습니다. 같은 요청을 자동으로 다시 보내지 않습니다.',
              ),
            ],
          ],
        ),
      ),
      if (_result != null) ...[
        const SizedBox(height: 16),
        JobRecommendationResult(
          result: _result!,
          selectedRecords: _resultRecords,
        ),
      ],
    ],
  );
}
