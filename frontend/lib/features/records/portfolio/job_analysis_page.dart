import 'dart:typed_data';
import '../../api/job_analysis_api.dart';
import '../../api/job_analysis_models.dart';
import '../../api/student_api.dart';
import '../../auth/auth_api.dart';
import '../../auth/guest_preview_scope.dart';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../shared/widgets/feature_line.dart';
import '../../../shared/widgets/feature_page.dart';
import '../../../shared/widgets/field_label.dart';
import '../../../shared/widgets/surface_card.dart';
import '../personal_record_repository.dart';
import '../personal_repository_scope.dart';

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
  const JobAnalysisPage({super.key, this.pickFile, this.studentApi});

  final StudentApi? studentApi;

  final Future<XFile?> Function()? pickFile;

  @override
  State<JobAnalysisPage> createState() => JobAnalysisPageState();
}

class JobAnalysisPageState extends State<JobAnalysisPage> {
  static const _kinds = [
    PersonalRecordKind.activity,
    PersonalRecordKind.experience,
    PersonalRecordKind.credential,
    PersonalRecordKind.portfolio,
  ];
  static const _kindLabels = {
    PersonalRecordKind.activity: '활동',
    PersonalRecordKind.experience: '경험',
    PersonalRecordKind.credential: '자격',
    PersonalRecordKind.portfolio: '성과',
  };

  final _posting = TextEditingController();
  final _url = TextEditingController();
  final _selected = <String>{};
  final _records = <PersonalRecordKind, List<PersonalRecord>>{};
  Uint8List? _fileBytes;
  String _fileName = '';
  String? _fileError;
  var _fileBusy = false;
  var _loading = true;
  var _failed = false;
  bool _busy = false;
  int _revision = 0;
  JobAnalysisResponse? _result;
  String? _error;
  List<String> _errorFields = [];

  @override
  void didUpdateWidget(covariant JobAnalysisPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studentApi?.ownerId != widget.studentApi?.ownerId || !identical(oldWidget.studentApi?.api, widget.studentApi?.api)) {
      _revision++;
      _busy = false;
      _selected.clear();
      _records.clear();
      _posting.clear();
      _url.clear();
      _fileBytes = null;
      _fileName = '';
      _result = null;
      _error = null;
      _load();
    }
  }


  @override
  void initState() {
    super.initState();
    _posting.addListener(_onInput);
    _url.addListener(_onInput);
    _load();
  }

  @override
  void dispose() {
    _posting.removeListener(_onInput);
    _url.removeListener(_onInput);
    _posting.dispose();
    _url.dispose();
    super.dispose();
  }

  void _onInput() {
    if (mounted) setState(() { _result = null; _error = null; _errorFields = []; });
  }

  bool get _urlInvalid {
    final text = _url.text.trim();
    if (text.isEmpty) return false;
    final uri = Uri.tryParse(text);
    return uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty;
  }

  String get _unavailableReason {
    final reasons = <String>[
      if (widget.studentApi == null) '로그인한 계정의 분석 연결이 필요합니다.',
      if (_posting.text.trim().isEmpty && _hasPostingInput) '주소·파일만 분석하는 기능은 연결 전입니다. 공고 텍스트를 붙여 넣으세요.',
      if (_posting.text.trim().length > 20000) '공고 텍스트는 20,000자 이내로 입력하세요.',
    ];
    if (!_hasPostingInput) {
      reasons.add('공고 텍스트, 주소, PDF·캡처 중 하나가 필요합니다.');
    }
    if (_urlInvalid) {
      reasons.add('주소가 http:// 또는 https:// 로 시작하는 형식이 아닙니다.');
    }
    if (_fileError != null) reasons.add(_fileError!);
    if (_selected.isEmpty) reasons.add('비교할 기록을 선택하세요.');
    if (_selected.length > 20) reasons.add('비교 기록은 20개까지 선택하세요.');
    if (widget.studentApi != null && _selected.isNotEmpty && _evidence.length != _selected.length) reasons.add('기록을 다시 불러온 뒤 서버에 저장된 기록을 선택하세요.');
    return reasons.join(' ');
  }

  bool get _hasPostingInput =>
      _posting.text.trim().isNotEmpty ||
      (_url.text.trim().isNotEmpty && !_urlInvalid) ||
      _fileBytes != null;

  List<PersonalEvidenceSelection> get _evidence => [
    for (final kind in _kinds)
      for (final record in _records[kind] ?? const <PersonalRecord>[])
        if (_selected.contains(_key(kind, record)) && record.version != null)
          PersonalEvidenceSelection(
            kind: kind == PersonalRecordKind.portfolio ? 'achievement' : kind.name,
            recordId: record.id, expectedVersion: record.version!,
          ),
  ];
  bool get _canAnalyze => widget.studentApi != null && !_busy && !_loading && !_failed &&
    !GuestPreviewScope.isActive(context) && _posting.text.trim().isNotEmpty &&
    _posting.text.trim().length <= 20000 && !_urlInvalid && _fileError == null &&
    _selected.isNotEmpty && _selected.length <= 20 && _evidence.length == _selected.length;

  Future<void> _analyze() async {
    if (!_canAnalyze) return;
    final revision = ++_revision;
    final api = widget.studentApi!;
    final request = JobAnalysisRequest(postingText: _posting.text.trim(), records: _evidence);
    setState(() { _busy = true; _result = null; _error = null; _errorFields = []; });
    try {
      final result = await JobAnalysisApi(api.api).analyze(request);
      if (!mounted || revision != _revision || widget.studentApi?.ownerId != api.ownerId || GuestPreviewScope.isActive(context)) return;
      setState(() => _result = result);
    } on AuthFailure catch (error) {
      if (mounted && revision == _revision) setState(() { _error = error.message; _errorFields = error.fields; });
    } catch (_) {
      if (mounted && revision == _revision) setState(() => _error = '분석 결과를 확인하지 못했습니다. 입력과 선택을 유지했으니 다시 시도하세요.');
    } finally {
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  String get _statusLabel => switch (_result?.status) {
    'completed' => '분석 완료',
    'needs_user_input' => '입력 확인 필요',
    'not_configured' => '분석기 연결 전',
    'insufficient_evidence' => '근거 부족',
    'failed' => '분석 실패',
    _ => _busy ? '분석 중' : '분석 준비',
  };
  String get _resultReason => switch (_result?.reason) {
    'compared_with_personal_evidence' => '선택한 기록과 공고를 비교했습니다.',
    'personal_records_required' => '비교할 기록을 선택하세요.',
    'analyzer_not_configured' => '서버 분석기가 아직 연결되지 않았습니다. 입력은 유지했습니다.',
    'no_requirements_found' => '공고에서 비교할 요건을 찾지 못했습니다.',
    'analysis_failed' => '서버가 분석을 완료하지 못했습니다. 다시 시도할 수 있습니다.',
    _ => _unavailableReason,
  };

  Future<void> _pickFile() async {
    if (_fileBusy) return;
    setState(() {
      _fileBusy = true;
      _fileError = null;
    });
    try {
      final file = await (widget.pickFile ?? pickJobPostingFile)();
      if (file == null) return;
      if (await file.length() > jobPostingFileMaxBytes) {
        throw StateError('PDF·캡처는 10MB 이하로 선택하세요.');
      }
      final bytes = await file.readAsBytes();
      validateJobPostingFile(file.name, bytes);
      if (!mounted) return;
      setState(() {
        _fileBytes = bytes;
        _fileName = file.name;
        _fileError = null;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _fileError = error is StateError
              ? error.message
              : '파일을 읽지 못했습니다. 이전 입력은 유지했습니다. 다시 선택하세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _fileBusy = false);
    }
  }

  Future<void> _load() async {
    final revision = _revision;
    setState(() {
      _result = null;
      _error = null;
      _loading = true;
      _failed = false;
    });
    try {
      final scope = PersonalRepositoryScope.read(context);
      final loaded = <PersonalRecordKind, List<PersonalRecord>>{};
      for (final kind in _kinds) {
        final repo = scope?.records(kind) ?? PersonalRecordRepository(kind);
        await repo.load();
        loaded[kind] = repo.records;
      }
      if (mounted && revision == _revision) {
        setState(() {
          _records
            ..clear()
            ..addAll(loaded);
          final valid = {for (final kind in _kinds) for (final record in _records[kind] ?? const <PersonalRecord>[]) _key(kind, record)};
          _selected.retainWhere(valid.contains);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  String _key(PersonalRecordKind kind, PersonalRecord record) =>
      '${kind.name}/${record.id}';

  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '채용공고 분석',
    description: '공고와 고른 기록으로 분석을 준비합니다.',
    body: [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FeatureLine.section(
              text: '공고 입력',
              padTop: false,
              padBottom: false,
            ),
            const SizedBox(height: 8),
            FieldLabel(
              label: '채용공고 텍스트',
              child: TextFormField(
                key: const ValueKey('job-posting-text'),
                controller: _posting,
                enabled: !_busy,
                maxLength: 20000,
                minLines: 6,
                maxLines: 12,
                decoration:
                    InputDecoration(hintText: '비교할 공고 본문을 붙여 넣으세요.', errorText: _errorFields.any((field) => field.contains('posting_text')) ? '공고 텍스트를 확인하세요.' : null),
              ),
            ),
            const SizedBox(height: 16),
            FieldLabel(
              label: '채용공고 주소',
              child: TextFormField(
                key: const ValueKey('job-posting-url'),
                controller: _url,
                enabled: !_busy,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  hintText: 'https://',
                  errorText: _urlInvalid
                      ? 'http:// 또는 https:// 로 시작하는 주소를 입력하세요.'
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FieldLabel(
              label: '공고 PDF·캡처',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('텍스트, 주소, PDF·캡처 중 하나만 있어도 됩니다.'),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      key: const ValueKey('job-posting-file'),
                      onPressed: _fileBusy || _busy ? null : _pickFile,
                      child: Text(_fileBusy ? '파일 읽는 중…' : 'PDF·캡처 선택'),
                    ),
                  ),
                  if (_fileError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _fileError!,
                      key: const ValueKey('job-posting-file-error'),
                    ),
                  ],
                  if (_fileBytes != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '$_fileName · ${(_fileBytes!.length / 1024).ceil()}KB',
                      key: const ValueKey('job-posting-file-name'),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: const ValueKey('job-posting-file-clear'),
                        onPressed: _busy ? null : () => setState(() {
                          _fileBytes = null;
                          _fileName = '';
                          _fileError = null;
                        }),
                        child: const Text('첨부 제외'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      SizedBox(height: FeatureLine.slotGap(context)),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FeatureLine.section(
              text: '비교에 넣을 개인 기록',
              trailing: FeatureLine.reload(onPressed: _busy || _loading ? null : _load),
              padTop: false,
              padBottom: false,
            ),
            const FeatureLine.one(text: '고른 항목만 포함합니다.'),
            if (_loading)
              const LinearProgressIndicator()
            else if (_failed)
              const FeatureLine.one(text: '개인 기록을 읽지 못했습니다. 선택한 항목은 유지합니다.')
            else if (_records.values.every((list) => list.isEmpty))
              const FeatureLine.one(
                text: '선택할 개인 기록이 없습니다. 활동·경험·자격·성과 메뉴에서 기록을 추가한 뒤 다시 열어 주세요.',
              )
            else
              for (final kind in _kinds)
                if ((_records[kind] ?? const []).isNotEmpty) ...[
                  FeatureLine.section(text: _kindLabels[kind]!),
                  for (final record in _records[kind]!)
                    FeatureLine.one(
                      text: record.value('title'),
                      leading: Checkbox(
                        key: ValueKey('job-record-${_key(kind, record)}'),
                        value: _selected.contains(_key(kind, record)),
                        onChanged: _busy ? null : (value) {
                          setState(() {
                            _result = null;
                            _error = null;
                            final key = _key(kind, record);
                            if (value == true) {
                              _selected.add(key);
                            } else {
                              _selected.remove(key);
                            }
                          });
                        },
                      ),
                    ),
                ],
            if (_selected.isNotEmpty)
              FeatureLine.one(text: '선택한 기록 ${_selected.length}개'),
          ],
        ),
      ),
      SizedBox(height: FeatureLine.slotGap(context)),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FeatureLine.section(
              text: '분석 상태',
              padTop: false,
              padBottom: false,
            ),
            if (_busy) const LinearProgressIndicator(),
            FeatureLine.one(text: '상태: $_statusLabel'),
            if (_error != null) Text(_error!, key: const ValueKey('job-analysis-error')),
            if (_url.text.trim().isNotEmpty || _fileBytes != null) const Text('이번 분석에는 붙여 넣은 텍스트와 선택한 기록만 보냅니다. 주소와 첨부 파일은 보내지 않습니다.'),
            FeatureLine.one(
              key: const ValueKey('job-analysis-reason'),
              text: '이유: $_resultReason',
            ),
            if (_result?.comparisons.isEmpty ?? true) const FeatureLine.one(text: '답변: 받은 답변 없음'),
            if (_result?.comparisons.isEmpty ?? true) const FeatureLine.one(text: '근거: 받은 근거 없음'),
            if (_result?.comparisons.isEmpty ?? true) const FeatureLine.one(text: '불확실한 부분: 받은 내용 없음'),
            for (final row in _result?.comparisons ?? const <JobRequirementComparison>[]) ...[
              FeatureLine.section(text: row.requirement),
              Text(switch (row.status) { 'supported' => '근거 있음', 'partially_supported' => '일부 근거 있음', _ => '근거 부족' }),
              Text(row.explanation),
              Text('공고 근거: ${row.postingEvidence.excerpt}'),
              for (final evidence in row.personalEvidence) Text('선택 기록 근거: ${evidence.excerpt}'),
            ],
          ],
        ),
      ),
    ],
    actions: [FilledButton(key: const ValueKey('job-analysis-run'), onPressed: _canAnalyze ? _analyze : null, child: Text(_busy ? '분석 중…' : '분석 실행'))],
  );
}
