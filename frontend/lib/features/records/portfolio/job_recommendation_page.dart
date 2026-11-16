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
  });
  final StudentApi? api;
  final AiConsentPreferences? consent;
  final Future<List<AiRecordOption>> Function()? loadRecords;
  final Future<List<XFile>> Function()? pickFiles;
  final VoidCallback? onBack;
  @override
  State<JobRecommendationPage> createState() => _JobRecommendationPageState();
}

class _JobRecommendationPageState extends State<JobRecommendationPage> {
  final _keyword = TextEditingController();
  var _form = GlobalKey<FormState>();
  String? _region, _error, _requestId, _recordError;
  List<AiRecordOption> _options = [];
  final _selected = <String, AiRecordOption>{};
  final _documents = <RecommendationDocument>[];
  bool _loading = false, _busy = false;
  int _revision = 0, _loadRevision = 0;
  JobRecommendationResponse? _result;
  List<AiRecordOption> _resultRecords = const [];
  List<String> _fields = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant JobRecommendationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api?.ownerId != widget.api?.ownerId ||
        !identical(oldWidget.api?.api, widget.api?.api) ||
        !identical(oldWidget.consent, widget.consent)) {
      _revision++;
      _form = GlobalKey<FormState>();
      _loadRevision++;
      _busy = false;
      _region = null;
      _keyword.clear();
      _documents.clear();
      _selected.clear();
      _options = [];
      _result = null;
      _error = null;
      _requestId = null;
      _fields = [];
      _load();
    }
  }

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final revision = _revision, load = ++_loadRevision;
    setState(() {
      _loading = true;
      _recordError = null;
    });
    try {
      final values = widget.loadRecords != null
          ? await widget.loadRecords!()
          : widget.api == null
          ? <AiRecordOption>[]
          : await loadAiRecords(widget.api!, includeCourses: false);
      if (!mounted || revision != _revision || load != _loadRevision) return;
      final before = _selected.length;
      _selected.removeWhere(
        (key, value) =>
            !values.any((r) => r.key == key && r.version == value.version),
      );
      setState(() {
        _options = values;
        if (before != _selected.length) {
          _recordError = '변경되거나 삭제된 기록은 다시 선택해 주세요.';
        }
      });
    } catch (_) {
      if (mounted && revision == _revision && load == _loadRevision) {
        setState(() {
          _recordError = '저장 기록을 읽지 못했습니다. 다시 읽거나 기기 파일만 선택할 수 있습니다.';
        });
      }
    } finally {
      if (mounted && revision == _revision && load == _loadRevision) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pick() async {
    if (_busy) return;
    final revision = _revision;
    setState(() {
      _busy = true;
      _error = null;
    });
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
      if (mounted && revision == _revision) setState(() => _busy = false);
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
    if (_documents.isEmpty && _selected.isEmpty) {
      setState(() => _error = '기기 파일 또는 저장 기록을 하나 이상 선택하세요.');
      return;
    }
    if (_loading || (_recordError != null && _selected.isNotEmpty)) {
      setState(() => _error = '선택한 저장 기록을 다시 읽고 확인한 뒤 실행하세요.');
      return;
    }
    final revision = _revision;
    final request = JobRecommendationRequest(
      keyword: _keyword.text.trim(),
      region: _region!,
      documents: List.of(_documents),
      records: _selected.values
          .map(
            (r) => PersonalEvidenceSelection(
              kind: r.kind,
              recordId: r.id,
              expectedVersion: r.version,
            ),
          )
          .toList(),
      consent: true,
    );
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      if (!await requestAiConsent(
            context,
            widget.consent!,
            AiConsentFeature.jobRecommendation,
          ) ||
          !mounted ||
          revision != _revision ||
          GuestPreviewScope.isActive(context)) {
        return;
      }
      final result = await JobRecommendationApi(widget.api!.api)
          .recommend(request);
      if (mounted &&
          revision == _revision &&
          !GuestPreviewScope.isActive(context)) {
        setState(() {
          _result = result;
          _resultRecords = _selected.values.toList();
        });
      }
    } on AuthFailure catch (e) {
      if (mounted && revision == _revision) {
        setState(() {
          _error = switch (e.status) {
            404 => '공고 추천 API가 연결되지 않았거나 선택 자료를 찾을 수 없습니다. 입력과 선택은 유지했습니다.',
            409 => '저장 기록이 변경되었습니다. 기록을 다시 읽고 선택해 주세요.',
            413 => '파일 용량이 서버 업로드 한도를 넘었습니다. 파일을 줄여 다시 시도하세요.',
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
        setState(() => _error = '추천 응답을 확인하지 못했습니다. 입력과 선택은 유지했습니다.');
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  bool _hasField(String name) =>
      _fields.any((f) => f.split('.').contains(name));
  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '내 자료로 공고 찾기',
    description: '직무와 지역을 고르고, 내 자료에서 확인된 근거로 공고를 비교합니다.',
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
                    hintText: '예: 개발자, Engineer',
                    errorText: _hasField('keyword') ? '직무 입력을 확인하세요.' : null,
                  ),
                  validator: (v) =>
                      v == null ||
                          v.trim().isEmpty ||
                          v.trim().runes.length > 80
                      ? '직무를 1~80자로 입력하세요.'
                      : null,
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
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      _surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('비교할 내 자료', style: Theme.of(context).textTheme.titleMedium),
            const Text('기기 파일 또는 저장 기록을 선택하세요. 선택한 자료만 이번 요청에 전송합니다.'),
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
            const Divider(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy || _loading ? null : _load,
                icon: const Icon(Icons.refresh),
                label: const Text('저장 기록 다시 읽기'),
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_recordError != null) Text(_recordError!),
            if (!_loading && _options.isEmpty && _recordError == null)
              const Text(
                '선택할 저장 기록이 없습니다. 기기 파일을 선택하거나 활동·경험·자격·성과를 먼저 등록하세요.',
              ),
            for (final r in _options)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(r.title),
                subtitle: Text('${r.kindLabel} · 버전 ${r.version}'),
                value: _selected.containsKey(r.key),
                onChanged: _busy || _loading
                    ? null
                    : (v) => setState(() {
                        if (v == true && _selected.length < 20) {
                          _selected[r.key] = r;
                        } else if (v != true) {
                          _selected.remove(r.key);
                        } else {
                          _error = '저장 기록은 최대 20개까지 선택하세요.';
                        }
                      }),
              ),
            Text('선택 기록 ${_selected.length}/20개 · 파일에서 추출한 조각과 합계 20개 이내'),
            if (_hasField('records')) const Text('저장 기록을 다시 읽고 선택해 주세요.'),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '선택 자료에서 추출한 텍스트를 외부 Gemini에 보내 공고와 비교합니다. 다른 사람의 이름이나 민감한 정보가 없는지 확인하세요.',
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
