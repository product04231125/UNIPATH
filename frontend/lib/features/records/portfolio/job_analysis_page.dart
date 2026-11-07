import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../shared/widgets/content_scroll_view.dart';
import '../../../shared/widgets/field_label.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../api/student_api.dart';
import '../../api/guidance_api.dart';
import '../../api/job_analysis_models.dart';
import '../../assistant/ai_record_catalog.dart';
import '../../auth/auth_api.dart';
import '../../settings/ai_consent_preferences.dart';
import '../../settings/ai_consent_section.dart';

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
    bytes[3] == 0x47;

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
  });
  final Future<XFile?> Function()? pickFile;
  final StudentApi? api;
  final AiConsentPreferences? consent;
  final Future<List<AiRecordOption>> Function()? loadRecords;
  @override
  State<JobAnalysisPage> createState() => JobAnalysisPageState();
}

class JobAnalysisPageState extends State<JobAnalysisPage> {
  final _posting = TextEditingController();
  List<AiRecordOption> _options = const [];
  final _selected = <String, AiRecordOption>{};
  bool _loading = true, _failed = false, _sending = false;
  bool _requesting = false;
  String? _error, _recordMessage, _requestId;
  JobAnalysisResponse? _result;
  bool get _connected => widget.api != null && widget.consent != null;
  bool get _canAnalyze => _connected && !_loading && !_failed && !_sending;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _posting.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_sending) return;
    setState(() {
      _loading = true;
      _failed = false;
      _recordMessage = null;
    });
    try {
      final options = widget.loadRecords != null
          ? await widget.loadRecords!()
          : widget.api == null
          ? <AiRecordOption>[]
          : await loadAiRecords(widget.api!, includeCourses: false);
      if (!mounted) return;
      final removed = _selected.entries
          .where(
            (e) => !options.any(
              (r) => r.key == e.key && r.version == e.value.version,
            ),
          )
          .map((e) => e.key)
          .toList();
      for (final key in removed) {
        _selected.remove(key);
      }
      setState(() {
        _options = options;
        _loading = false;
        if (removed.isNotEmpty) _recordMessage = '변경되거나 삭제된 기록은 다시 선택해 주세요.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
          _recordMessage = '개인 기록을 읽지 못했습니다. 입력과 기존 선택을 유지했습니다.';
        });
      }
    }
  }

  Future<void> _analyze() async {
    if (!_canAnalyze) return;
    final posting = _posting.text.trim();
    setState(() {
      _error = null;
      _requestId = null;
    });
    if (posting.isEmpty ||
        posting.runes.length > 20000 ||
        _selected.isEmpty ||
        _selected.length > 20) {
      setState(() => _error = '공고 본문(1~20,000자)과 비교할 기록 1~20개를 선택해 주세요.');
      return;
    }
    final choices = _selected.values
        .map(
          (r) => PersonalEvidenceSelection(
            kind: r.kind,
            recordId: r.id,
            expectedVersion: r.version,
          ),
        )
        .toList(growable: false);
    setState(() => _sending = true);
    try {
      if (!await requestAiConsent(
            context,
            widget.consent!,
            AiConsentFeature.jobAnalysis,
          ) ||
          !mounted) {
        return;
      }
      setState(() {
        _result = null;
        _requesting = true;
      });
      final result = await GuidanceApi(widget.api!.api).analyze(
        JobAnalysisRequest(
          postingText: posting,
          records: choices,
          externalProcessingConsent: true,
        ),
      );
      if (mounted) setState(() => _result = result);
    } on AuthFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e.status == 409
              ? '선택한 기록이 변경되었습니다. 입력을 유지했습니다. 기록을 다시 읽고 선택해 주세요.'
              : e.message;
          _requestId = e.requestId;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '분석 응답을 확인하지 못했습니다. 입력을 유지했습니다. 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _requesting = false;
        });
      }
    }
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
    'personal_records_required' => '비교할 개인 기록을 선택해 주세요.',
    'no_requirements_found' => '공고에서 비교할 요건을 찾지 못했습니다.',
    _ => '분석을 완료하지 못했습니다. 입력을 유지하고 다시 시도할 수 있습니다.',
  };
  @override
  Widget build(BuildContext context) => ContentScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(title: '채용공고 분석', description: '공고 본문과 고른 기록을 비교합니다.'),
        const SizedBox(height: 16),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FieldLabel(
                label: '채용공고 텍스트',
                child: TextFormField(
                  key: const ValueKey('job-posting-text'),
                  controller: _posting,
                  enabled: !_sending,
                  minLines: 6,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    hintText: '비교할 공고 본문을 붙여 넣으세요.',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const FieldLabel(
                label: '채용공고 주소 · 준비 중',
                child: TextField(
                  key: ValueKey('job-posting-url'),
                  enabled: false,
                  decoration: InputDecoration(hintText: '주소 분석은 준비 중입니다.'),
                ),
              ),
              const SizedBox(height: 16),
              const Text('PDF·캡처 분석은 준비 중입니다. 현재는 공고 본문을 붙여 넣어 분석할 수 있습니다.'),
              const Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  key: ValueKey('job-posting-file'),
                  onPressed: null,
                  child: Text('PDF·캡처 선택 · 준비 중'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '비교에 넣을 개인 기록',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: _loading || _sending ? null : _load,
                    child: const Text('기록 다시 읽기'),
                  ),
                ],
              ),
              const Text('직접 고른 서버 기록만 포함합니다. 개인 PDF는 전송하지 않습니다.'),
              if (_loading) const LinearProgressIndicator(),
              if (_recordMessage != null) Text(_recordMessage!),
              if (!_loading && !_failed && _options.isEmpty)
                const Text('선택할 개인 기록이 없습니다. 활동·경험·자격·성과 기록을 추가한 뒤 다시 읽어 주세요.'),
              for (final record in _options)
                Material(
                  type: MaterialType.transparency,
                  child: CheckboxListTile(
                    key: ValueKey('job-record-${record.key}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(record.title),
                    subtitle: Text(
                      '${record.kindLabel} · 버전 ${record.version}',
                    ),
                    value: _selected.containsKey(record.key),
                    onChanged: _sending
                        ? null
                        : (value) => setState(() {
                            if (value == true) {
                              if (_selected.length >= 20) {
                                _recordMessage = '최대 20개까지 선택할 수 있습니다.';
                              } else {
                                _selected[record.key] = record;
                              }
                            } else {
                              _selected.remove(record.key);
                            }
                          }),
                  ),
                ),
              Text('선택한 기록 ${_selected.length}/20개'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_connected)
                const Text('채용 분석을 사용하려면 로그인해 주세요. 공고와 개인 기록은 전송하지 않았습니다.'),
              if (widget.consent != null)
                AnimatedBuilder(
                  animation: widget.consent!,
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.consent!.allows(AiConsentFeature.jobAnalysis)
                            ? 'Google 외부 AI 전송 허용 중 · 설정에서 변경'
                            : 'Google 외부 AI 전송 · 실행 전 동의 확인',
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
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_requestId != null) SelectableText('문의 식별자: $_requestId'),
              FilledButton(
                onPressed: _canAnalyze ? _analyze : null,
                child: Text(_sending ? '분석 중…' : '공고 분석'),
              ),
              if (_requesting) const LinearProgressIndicator(),
              if (_result != null) ...[
                Text(
                  _status(_result!),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (_result!.status != 'completed') Text(_reason(_result!)),
                for (final item in _result!.comparisons) ...[
                  const Divider(),
                  Text(
                    '${item.priority == "required" ? "필수" : "우대"} · ${item.requirement}',
                  ),
                  Text(switch (item.status) {
                    'supported' => '근거 있음',
                    'partially_supported' => '일부 근거 있음',
                    _ => '근거 부족',
                  }),
                  SelectableText('공고 근거: ${item.postingEvidence.excerpt}'),
                  for (final citation in item.personalEvidence)
                    SelectableText(
                      '내 기록 근거 (버전 ${citation.version}): ${citation.excerpt}',
                    ),
                  SelectableText(item.explanation),
                ],
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
