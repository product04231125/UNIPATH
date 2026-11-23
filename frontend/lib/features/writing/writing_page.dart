import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/pending_ui_action.dart';
import '../../shared/widgets/feature_page.dart';
import '../../shared/widgets/field_label.dart';
import '../../shared/widgets/surface_card.dart';
import '../api/academic_guidance_models.dart';
import '../api/student_api.dart';
import '../assistant/ai_record_catalog.dart';
import '../auth/auth_api.dart';
import '../auth/guest_preview_scope.dart';
import '../career/career_goal.dart';
import '../records/portfolio/material_selection.dart';
import '../settings/ai_consent_preferences.dart';
import '../settings/ai_consent_section.dart';
import '../auth/file_export_gateway.dart';
import 'export_file_save.dart';
import 'writing_api.dart';

/// 채용공고 분석 → 자기소개서: opens this page once with the posting filled in.
class WritingRequest extends PendingUiAction {
  WritingRequest({required this.postingText});
  final String postingText;
}

const maxQuestions = 6;

/// 자기소개서·포트폴리오: a draft whose every paragraph cites the student's records, edited here
/// and saved as an editable Word file. Only the latest draft is kept, on this device.
class WritingPage extends StatefulWidget {
  const WritingPage({
    super.key,
    this.api,
    this.consent,
    this.careerGoal,
    this.store,
    this.loadRecords,
    this.loadMaterials,
    this.loadDocuments,
    this.request,
    this.saveFile = saveExportFile,
  });

  final StudentApi? api;
  final AiConsentPreferences? consent;
  final CareerGoalController? careerGoal;
  final WritingSessionStore? store;
  final Future<List<AiRecordOption>> Function()? loadRecords;
  final Future<List<AssistantMaterial>> Function()? loadMaterials;
  final Future<List<GuidanceDocument>> Function(List<String> ids)?
  loadDocuments;
  final WritingRequest? request;
  final Future<bool> Function(
    Uint8List bytes,
    String filename,
    ExportFormat format,
  )
  saveFile;

  @override
  State<WritingPage> createState() => _WritingPageState();
}

class _EditablePart {
  _EditablePart(WritingPart part)
    : label = part.label == null
          ? null
          : TextEditingController(text: part.label),
      text = TextEditingController(text: part.text),
      citations = part.citations;
  final TextEditingController? label;
  final TextEditingController text;
  final List<WritingCitation> citations;
  bool open = false;

  WritingPart get value => WritingPart(
    label: label?.text.trim(),
    text: text.text.trim(),
    citations: citations,
  );

  void dispose() {
    label?.dispose();
    text.dispose();
  }
}

class _EditableSection {
  _EditableSection(WritingSection section)
    : heading = TextEditingController(text: section.heading),
      facts = [for (final f in section.facts) _EditablePart(f)],
      paragraphs = [for (final p in section.paragraphs) _EditablePart(p)];
  final TextEditingController heading;
  final List<_EditablePart> facts, paragraphs;

  int get length => paragraphs.fold(0, (n, p) => n + p.text.text.trim().length);

  WritingSection get value => WritingSection(
    heading: heading.text.trim(),
    facts: [
      for (final f in facts)
        if (f.text.text.trim().isNotEmpty) f.value,
    ],
    paragraphs: [
      for (final p in paragraphs)
        if (p.text.text.trim().isNotEmpty) p.value,
    ],
  );

  void dispose() {
    heading.dispose();
    for (final part in [...facts, ...paragraphs]) {
      part.dispose();
    }
  }
}

class _WritingPageState extends State<WritingPage> {
  var _type = WritingType.coverLetter;
  var _improve = false;
  final _role = TextEditingController();
  final _company = TextEditingController();
  final _posting = TextEditingController();
  final _charLimit = TextEditingController();
  final _original = TextEditingController();
  final _questions = <TextEditingController>[TextEditingController()];
  final _materialIds = <String>{};
  final _title = TextEditingController();

  WritingInput? _input;
  WritingResult? _result;
  List<_EditableSection> _sections = [];
  Map<String, String> _labels = {};
  bool _sending = false, _exporting = false, _restored = false;
  String? _error, _status;
  int _revision = 0;
  Timer? _autosave;

  // The saved document being edited, if any, and its text when last saved.
  String? _documentId, _savedSnapshot;
  int? _documentVersion;
  bool _saving = false, _documentsLoading = false;
  List<WritingDocumentSummary> _documents = const [];
  String? _documentsError;
  int _documentsRequest = 0;

  bool get _connected => widget.api != null && widget.consent != null;
  bool get _canRun =>
      _connected && !GuestPreviewScope.isActive(context) && !_sending;

  @override
  void initState() {
    super.initState();
    widget.careerGoal?.addListener(_fillRole);
    _fillRole();
    _consumeRequest();
    unawaited(_restore());
    unawaited(_loadDocuments());
  }

  @override
  void didUpdateWidget(covariant WritingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.careerGoal, widget.careerGoal)) {
      oldWidget.careerGoal?.removeListener(_fillRole);
      widget.careerGoal?.addListener(_fillRole);
    }
    if (!identical(oldWidget.request, widget.request)) _consumeRequest();
    if (oldWidget.api?.ownerId != widget.api?.ownerId) {
      _revision++;
      _sending = _exporting = false;
      _materialIds.clear();
      _clearDraft();
      _documents = const [];
      _restored = false;
      unawaited(_restore());
      unawaited(_loadDocuments());
    }
  }

  @override
  void dispose() {
    _autosave?.cancel();
    widget.careerGoal?.removeListener(_fillRole);
    for (final c in [
      _role,
      _company,
      _posting,
      _charLimit,
      _original,
      _title,
      ..._questions,
    ]) {
      c.dispose();
    }
    for (final s in _sections) {
      s.dispose();
    }
    super.dispose();
  }

  /// The saved target job fills an empty 목표 직무 once.
  void _fillRole() {
    final goal = widget.careerGoal?.goal;
    if (goal == null || !goal.isSet || _role.text.trim().isNotEmpty) return;
    _role.text = goal.keyword.isNotEmpty
        ? goal.keyword
        : (goal.categoryLabel ?? '');
  }

  void _consumeRequest() {
    final request = widget.request;
    if (request == null || !request.consume()) return;
    setState(() {
      _type = WritingType.coverLetter;
      _improve = false;
      _posting.text = request.postingText;
    });
  }

  Future<void> _restore() async {
    final store = widget.store;
    if (store == null || _restored) return;
    _restored = true;
    final revision = _revision;
    final saved = await store.load();
    if (saved == null || !mounted || revision != _revision || _result != null) {
      return;
    }
    setState(() {
      _fillForm(saved.input);
      _show(
        saved.input,
        saved.result,
        saved.draft,
        saved.labels,
        title: saved.title,
        documentId: saved.documentId,
        documentVersion: saved.documentVersion,
        savedSnapshot: saved.savedSnapshot,
      );
      _status = '이 기기에 저장된 마지막 초안을 불러왔습니다.';
    });
  }

  void _fillForm(WritingInput input) {
    _type = input.type;
    _improve = input.improve;
    _role.text = input.targetRole;
    _company.text = input.targetCompany;
    if (_posting.text.trim().isEmpty) _posting.text = input.postingText;
    _charLimit.text = input.charLimit?.toString() ?? '';
    _original.text = input.originalText;
    for (final q in _questions) {
      q.dispose();
    }
    _questions
      ..clear()
      ..addAll([
        for (final q in input.questions) TextEditingController(text: q),
        if (input.questions.isEmpty) TextEditingController(),
      ]);
  }

  void _show(
    WritingInput input,
    WritingResult result,
    WritingDraft draft,
    Map<String, String> labels, {
    required String title,
    String? documentId,
    int? documentVersion,
    String? savedSnapshot,
  }) {
    for (final s in _sections) {
      s.dispose();
    }
    _input = input;
    _result = result;
    _labels = labels;
    _documentId = documentId;
    _documentVersion = documentVersion;
    _title.removeListener(_edited);
    _title.text = title;
    _title.addListener(_edited);
    _sections = [for (final s in draft.sections) _EditableSection(s)];
    _savedSnapshot = savedSnapshot;
    for (final s in _sections) {
      for (final c in [
        s.heading,
        for (final p in [...s.facts, ...s.paragraphs]) ?p.label,
        for (final p in [...s.facts, ...s.paragraphs]) p.text,
      ]) {
        c.addListener(_edited);
      }
    }
  }

  void _clearDraft() {
    for (final s in _sections) {
      s.dispose();
    }
    _sections = [];
    _input = null;
    _result = null;
    _labels = {};
    _error = _status = null;
    _documentId = _savedSnapshot = null;
    _documentVersion = null;
    _title.removeListener(_edited);
    _title.clear();
  }

  WritingDraft get _draft => WritingDraft(
    sections: [for (final s in _sections) s.value],
    questionsForUser: _result?.draft?.questionsForUser ?? const [],
    revisions: _result?.draft?.revisions ?? const [],
  );

  /// What saving compares: the title and every edited text.
  String _snapshot() =>
      jsonEncode({'title': _title.text.trim(), ..._draft.toStoredJson()});

  /// Edits not yet saved on the server (a new draft counts as unsaved).
  bool get _unsaved => _sections.isNotEmpty && _snapshot() != _savedSnapshot;

  String _defaultTitle(WritingInput input) => [
    if (input.targetCompany.isNotEmpty)
      input.targetCompany
    else
      input.targetRole,
    input.type.label,
  ].join(' ');

  void _edited() {
    if (!mounted) return;
    setState(() {});
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 800), _persist);
  }

  void _persist() {
    final input = _input, result = _result, store = widget.store;
    if (input == null || result == null || store == null) return;
    unawaited(
      store.save(
        WritingSession(
          input: input,
          result: result,
          draft: _draft,
          labels: _labels,
          title: _title.text.trim(),
          documentId: _documentId,
          documentVersion: _documentVersion,
          savedSnapshot: _savedSnapshot,
        ),
      ),
    );
  }

  WritingInput? _readForm() {
    final role = _role.text.trim();
    final limitText = _charLimit.text.trim();
    final limit = int.tryParse(limitText);
    final questions = [
      for (final q in _questions)
        if (q.text.trim().isNotEmpty) q.text.trim(),
    ];
    String? error;
    if (role.isEmpty || role.length > 120) {
      error = '목표 직무를 1~120자로 입력해 주세요.';
    } else if (_company.text.trim().length > 120) {
      error = '지원처는 120자 이하로 입력해 주세요.';
    } else if (_posting.text.trim().length > 20000) {
      error = '공고 본문은 20,000자 이하로 입력해 주세요.';
    } else if (questions.any((q) => q.length > 300)) {
      error = '문항은 300자 이하로 입력해 주세요.';
    } else if (limitText.isNotEmpty &&
        (limit == null || limit < 200 || limit > 5000)) {
      error = '문항별 글자 수는 200~5,000자로 입력해 주세요.';
    } else if (_improve &&
        (_original.text.trim().isEmpty ||
            _original.text.trim().length > 20000)) {
      error = '다듬을 원문을 1~20,000자로 붙여 넣어 주세요.';
    }
    if (error != null) {
      setState(() => _error = error);
      return null;
    }
    final cover = _type == WritingType.coverLetter;
    return WritingInput(
      type: _type,
      improve: _improve,
      targetRole: role,
      targetCompany: _company.text.trim(),
      postingText: _posting.text.trim(),
      questions: cover ? questions : const [],
      charLimit: cover ? limit : null,
      originalText: _improve ? _original.text.trim() : '',
    );
  }

  Future<void> _run() async {
    if (!_canRun) return;
    setState(() {
      _error = null;
      _status = null;
    });
    final input = _readForm();
    if (input == null) return;
    if (_unsaved && !await _confirmDiscard('새 초안 만들기')) return;
    if (!mounted) return;
    final revision = ++_revision;
    final api = widget.api!;
    setState(() => _sending = true);
    try {
      final records = await (widget.loadRecords?.call() ?? loadAiRecords(api));
      if (!mounted || revision != _revision) return;
      final documents = _materialIds.isEmpty || widget.loadDocuments == null
          ? const <GuidanceDocument>[]
          : await widget.loadDocuments!(_materialIds.toList());
      if (!mounted || revision != _revision) return;
      if (records.isEmpty && documents.isEmpty && !input.improve) {
        setState(
          () =>
              _error = '초안에 쓸 기록이 없습니다. 수강·활동·경험·자격·성과 기록을 추가하거나 내 자료를 골라 주세요.',
        );
        return;
      }
      if (!await requestAiConsent(
            context,
            widget.consent!,
            AiConsentFeature.writing,
          ) ||
          !mounted ||
          revision != _revision ||
          GuestPreviewScope.isActive(context)) {
        return;
      }
      final result = await WritingApi(api)
          .generate(input, records: records, documents: documents);
      if (!mounted || revision != _revision) return;
      final draft = result.draft;
      if (draft == null) {
        setState(() => _error = result.message);
        return;
      }
      final labels = {
        for (final r in records) r.id: '${r.kindLabel} · ${r.title}',
        for (final s in result.sources)
          s.recordId:
              '내 자료 · ${s.filename} ${s.location}${s.ocr ? ' (자동 문자 인식, 원본 확인)' : ''}',
        for (final id in result.originalRecordIds) id: '붙여 넣은 원문',
      };
      setState(
        () => _show(input, result, draft, labels, title: _defaultTitle(input)),
      );
      _persist();
    } catch (error) {
      if (mounted && revision == _revision) {
        setState(() => _error = writingFailureMessage(error));
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _sending = false);
    }
  }

  Future<bool> _confirmDiscard(String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(action),
          content: const Text(
            '지금 고치던 초안에 저장하지 않은 내용이 있습니다. 계속하면 그 내용은 사라집니다. 필요하면 먼저 저장하세요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              key: const ValueKey('writing-replace'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('계속'),
            ),
          ],
        ),
      ) ??
      false;

  WritingDocumentApi? get _documentApi =>
      widget.api == null ? null : WritingDocumentApi(widget.api!.api);

  Future<void> _loadDocuments() async {
    final api = _documentApi;
    if (api == null || GuestPreviewScope.isActive(context)) return;
    final request = ++_documentsRequest;
    setState(() {
      _documentsLoading = true;
      _documentsError = null;
    });
    try {
      final documents = await api.list();
      if (mounted && request == _documentsRequest) {
        setState(() => _documents = documents);
      }
    } catch (_) {
      if (mounted && request == _documentsRequest) {
        setState(() => _documentsError = '저장한 문서를 읽지 못했습니다. 다시 읽어 주세요.');
      }
    } finally {
      if (mounted && request == _documentsRequest) {
        setState(() => _documentsLoading = false);
      }
    }
  }

  Future<void> _save() async {
    final api = _documentApi, input = _input, result = _result;
    if (api == null || input == null || result == null || _saving) return;
    final title = _title.text.trim();
    final draft = _draft;
    if (title.isEmpty || title.length > 120) {
      setState(() => _error = '문서 이름을 1~120자로 입력해 주세요.');
      return;
    }
    if (draft.isEmpty) {
      setState(() => _error = '저장할 문단이 없습니다.');
      return;
    }
    final snapshot = _snapshot();
    setState(() {
      _saving = true;
      _error = _status = null;
    });
    try {
      final id = _documentId, version = _documentVersion;
      final saved = id == null || version == null
          ? await api.create(title, input, draft, _labels)
          : await api.update(
              id,
              expectedVersion: version,
              title: title,
              input: input,
              draft: draft,
              labels: _labels,
            );
      if (!mounted) return;
      setState(() {
        _documentId = saved.id;
        _documentVersion = saved.version;
        _savedSnapshot = snapshot;
        _status = '저장했습니다.';
      });
      _persist();
      unawaited(_loadDocuments());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = documentFailureMessage(error);
        // Gone on the server: the next save creates a new document from these edits.
        if (error is AuthFailure && error.status == 404) {
          _documentId = _documentVersion = null;
        }
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _open(WritingDocumentSummary summary) async {
    final api = _documentApi;
    if (api == null || _sending) return;
    if (summary.id == _documentId && !_unsaved) return;
    if (_unsaved && !await _confirmDiscard('저장한 문서 열기')) return;
    if (!mounted) return;
    final revision = ++_revision;
    setState(() => _error = _status = null);
    try {
      final document = await api.get(summary.id);
      if (!mounted || revision != _revision) return;
      final result = WritingResult.fromJson({
        'status': 'draft_ready',
        'draft': document.draft.toStoredJson(),
      });
      setState(() {
        _fillForm(document.input);
        _show(
          document.input,
          result,
          document.draft,
          document.labels,
          title: document.title,
          documentId: document.id,
          documentVersion: document.version,
        );
        _savedSnapshot = _snapshot();
        _status = '저장한 문서를 열었습니다.';
      });
      _persist();
    } catch (error) {
      if (mounted && revision == _revision) {
        setState(() => _error = documentFailureMessage(error));
      }
    }
  }

  Future<void> _delete(WritingDocumentSummary summary) async {
    final api = _documentApi;
    if (api == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('저장한 문서 삭제'),
        content: Text('${summary.title} 문서를 삭제할까요? 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey('writing-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await api.delete(summary.id, expectedVersion: summary.version);
      if (!mounted) return;
      setState(() {
        // The open copy stays on screen as an unsaved draft.
        if (summary.id == _documentId) {
          _documentId = _savedSnapshot = null;
          _documentVersion = null;
        }
        _status = '${summary.title} 문서를 삭제했습니다.';
      });
      _persist();
    } catch (error) {
      if (mounted) {
        setState(() => _documentsError = documentFailureMessage(error));
      }
    }
    unawaited(_loadDocuments());
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _draft.plainText));
    if (mounted) setState(() => _status = '본문을 복사했습니다.');
  }

  Future<void> _export(ExportFormat format) async {
    final input = _input;
    if (input == null || _exporting || widget.api == null) return;
    final draft = _draft;
    if (draft.isEmpty) {
      setState(() => _error = '내보낼 문단이 없습니다.');
      return;
    }
    final profile = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _ExportDialog(type: input.type, format: format),
    );
    if (profile == null || !mounted) return;
    setState(() {
      _exporting = true;
      _error = _status = null;
    });
    try {
      final bytes = await WritingApi(widget.api!).exportFile(
        input.type,
        draft,
        format,
        name: profile['name']!,
        email: profile['email']!,
        phone: profile['phone']!,
        link: profile['link']!,
      );
      final base = input.type == WritingType.coverLetter
          ? 'cover-letter'
          : 'portfolio';
      final saved = await widget.saveFile(
        bytes,
        '$base.${format.extension}',
        format,
      );
      if (mounted) {
        setState(
          () => _status = saved
              ? '${format.label} 파일을 저장했습니다.'
              : '${format.label} 파일 저장을 취소했습니다.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = writingFailureMessage(error));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '자기소개서·포트폴리오',
    description: '저장된 수강·활동·경험·자격·성과 기록과 고른 내 자료에서 근거를 확인한 문장만으로 초안을 만들고, 고친 뒤 저장하거나 Word·PDF로 받습니다.',
    body: [
      if (_documentApi != null) ...[
        _savedDocuments(context),
        const SizedBox(height: 16),
      ],
      _form(context),
      if (_sections.isNotEmpty) ...[
        const SizedBox(height: 16),
        _editor(context),
      ],
    ],
  );

  String _when(DateTime? value) {
    final local = value?.toLocal();
    if (local == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.month}월 ${local.day}일 ${two(local.hour)}:${two(local.minute)}';
  }

  Widget _savedDocuments(BuildContext context) {
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    return SurfaceCard(
      key: const ValueKey('writing-documents'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '저장한 문서 ${_documents.length}개',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              TextButton(
                key: const ValueKey('writing-documents-refresh'),
                onPressed: _documentsLoading ? null : _loadDocuments,
                child: const Text('다시 읽기'),
              ),
            ],
          ),
          if (_documentsLoading) const LinearProgressIndicator(),
          if (_documentsError != null)
            Text(
              _documentsError!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          if (!_documentsLoading &&
              _documents.isEmpty &&
              _documentsError == null)
            Text('초안을 만든 뒤 저장하면 여기에서 다시 열 수 있습니다.', style: muted),
          for (final d in _documents)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.title,
                          style: d.id == _documentId
                              ? const TextStyle(fontWeight: FontWeight.w700)
                              : null,
                        ),
                        Text(
                          [
                            d.type.label,
                            if (_when(d.updatedAt).isNotEmpty)
                              '${_when(d.updatedAt)} 저장',
                            if (d.id == _documentId) '편집 중',
                          ].join(' · '),
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    key: ValueKey('writing-open-${d.id}'),
                    onPressed: _sending ? null : () => _open(d),
                    child: const Text('열기'),
                  ),
                  TextButton(
                    key: ValueKey('writing-delete-${d.id}'),
                    onPressed: () => _delete(d),
                    child: const Text('삭제'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _form(BuildContext context) {
    final cover = _type == WritingType.coverLetter;
    final enabled = !_sending;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<WritingType>(
                key: const ValueKey('writing-type'),
                showSelectedIcon: false,
                segments: [
                  for (final t in WritingType.values)
                    ButtonSegment(value: t, label: Text(t.label)),
                ],
                selected: {_type},
                onSelectionChanged: enabled
                    ? (value) => setState(() => _type = value.first)
                    : null,
              ),
              FilterChip(
                key: const ValueKey('writing-improve'),
                label: const Text('기존 글 다듬기'),
                selected: _improve,
                onSelected: enabled
                    ? (value) => setState(() => _improve = value)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          FieldLabel(
            label: '목표 직무',
            child: TextField(
              key: const ValueKey('writing-role'),
              controller: _role,
              enabled: enabled,
              decoration: const InputDecoration(hintText: '예: 프론트엔드 개발'),
            ),
          ),
          const SizedBox(height: 12),
          FieldLabel(
            label: '지원처 (선택)',
            child: TextField(
              key: const ValueKey('writing-company'),
              controller: _company,
              enabled: enabled,
            ),
          ),
          const SizedBox(height: 12),
          FieldLabel(
            label: '채용공고 본문 (선택)',
            child: TextField(
              key: const ValueKey('writing-posting'),
              controller: _posting,
              enabled: enabled,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: '붙여 넣으면 공고의 업무와 자격에 맞는 경험을 골라 씁니다.',
              ),
            ),
          ),
          if (cover) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < _questions.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: ValueKey('writing-question-$i'),
                        controller: _questions[i],
                        enabled: enabled,
                        decoration: InputDecoration(
                          labelText: '문항 ${i + 1} (선택)',
                          hintText: '예: 지원 직무와 관련된 경험을 적어 주세요.',
                        ),
                      ),
                    ),
                    if (_questions.length > 1)
                      IconButton(
                        tooltip: '문항 삭제',
                        onPressed: enabled
                            ? () => setState(
                                () => _questions.removeAt(i).dispose(),
                              )
                            : null,
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_questions.length < maxQuestions)
                  TextButton.icon(
                    key: const ValueKey('writing-add-question'),
                    onPressed: enabled
                        ? () => setState(
                            () => _questions.add(TextEditingController()),
                          )
                        : null,
                    icon: const Icon(Icons.add),
                    label: const Text('문항 추가'),
                  ),
                SizedBox(
                  width: 180,
                  child: TextField(
                    key: const ValueKey('writing-char-limit'),
                    controller: _charLimit,
                    enabled: enabled,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: '문항별 글자 수 (선택)',
                      hintText: '예: 1000',
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_improve) ...[
            const SizedBox(height: 12),
            FieldLabel(
              label: '다듬을 원문',
              child: TextField(
                key: const ValueKey('writing-original'),
                controller: _original,
                enabled: enabled,
                minLines: 4,
                maxLines: 12,
                decoration: const InputDecoration(
                  hintText: '이미 쓴 자기소개서나 포트폴리오 글을 붙여 넣으세요. 새 경험은 지어내지 않습니다.',
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (!_connected)
            const Text('로그인하면 저장된 기록으로 초안을 만들 수 있습니다. 아직 아무것도 전송하지 않았습니다.'),
          if (widget.loadMaterials != null && _connected) ...[
            MaterialSelection(
              keyPrefix: 'writing',
              title: '함께 쓸 내 자료 (선택)',
              load: widget.loadMaterials!,
              selected: _materialIds,
              enabled: enabled,
              onChanged: (id, selected) => setState(
                () => selected ? _materialIds.add(id) : _materialIds.remove(id),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (widget.consent != null)
            AnimatedBuilder(
              animation: widget.consent!,
              builder: (context, _) => Text(
                widget.consent!.allows(AiConsentFeature.writing)
                    ? 'Google 외부 AI 전송 허용 중 · 설정에서 변경'
                    : 'Google 외부 AI 전송 · 실행 전 동의 확인',
              ),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(
              key: const ValueKey('writing-run'),
              onPressed: _canRun ? _run : null,
              child: Text(_sending ? '작성 중… (20초 안팎)' : '초안 만들기'),
            ),
          ),
          if (_sending) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              key: const ValueKey('writing-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  String _citation(WritingCitation c) =>
      '${_labels[c.recordId] ?? '내 기록'}: ${c.excerpt}';

  Widget _editor(BuildContext context) {
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    final result = _result!;
    final input = _input!;
    final limit = input.type == WritingType.coverLetter
        ? input.charLimit
        : null;
    final asks = result.draft?.questionsForUser ?? const <String>[];
    final revisions = result.draft?.revisions ?? const <WritingRevision>[];
    return SurfaceCard(
      key: const ValueKey('writing-draft'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${input.type.label} 초안${input.targetCompany.isEmpty ? '' : ' · ${input.targetCompany}'}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 360,
                child: TextField(
                  key: const ValueKey('writing-title'),
                  controller: _title,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: '문서 이름',
                    counterText: '',
                  ),
                ),
              ),
              if (_documentApi != null)
                FilledButton.tonalIcon(
                  key: const ValueKey('writing-save'),
                  onPressed: _saving || !_unsaved ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    _saving
                        ? '저장 중…'
                        : _documentId == null
                        ? '저장'
                        : '변경 저장',
                  ),
                ),
              if (_documentApi != null)
                Text(
                  _documentId == null
                      ? '아직 저장하지 않은 초안'
                      : _unsaved
                      ? '저장하지 않은 변경이 있습니다'
                      : '저장됨',
                  key: const ValueKey('writing-save-state'),
                  style: muted,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(result.notice ?? '초안입니다. 검토 후 내보내세요.', style: muted),
          Text('직접 고친 문장은 다시 검증하지 않습니다. 사실과 다른 내용이 없는지 확인하세요.', style: muted),
          for (final warning in result.warnings)
            Text(warning, key: const ValueKey('writing-warning'), style: muted),
          if (_status != null) ...[
            const SizedBox(height: 4),
            Text(_status!, key: const ValueKey('writing-status')),
          ],
          if (asks.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('더 구체적으로 쓰려면', style: theme.textTheme.titleSmall),
            Text('아래 내용을 활동·경험 기록에 적어 두고 다시 만들면 반영됩니다.', style: muted),
            for (final ask in asks) Text('· $ask'),
          ],
          if (revisions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('고친 부분', style: theme.textTheme.titleSmall),
            for (final r in revisions)
              Text('· "${r.originalExcerpt}" → ${r.reason}'),
          ],
          for (var i = 0; i < _sections.length; i++) ...[
            const Divider(height: 32),
            _sectionEditor(context, i, limit),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const ValueKey('writing-export'),
                onPressed: _exporting ? null : () => _export(ExportFormat.docx),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Word로 받기'),
              ),
              FilledButton.icon(
                key: const ValueKey('writing-export-pdf'),
                onPressed: _exporting ? null : () => _export(ExportFormat.pdf),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF로 받기'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('writing-copy'),
                onPressed: _copy,
                icon: const Icon(Icons.copy_outlined),
                label: const Text('본문 복사'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionEditor(BuildContext context, int index, int? limit) {
    final section = _sections[index];
    final theme = Theme.of(context);
    final over = limit != null && section.length > limit;
    return Column(
      key: ValueKey('writing-section-$index'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: ValueKey('writing-heading-$index'),
          controller: section.heading,
          style: theme.textTheme.titleSmall,
          maxLength: 300,
          decoration: const InputDecoration(
            labelText: '제목·문항',
            counterText: '',
          ),
        ),
        Text(
          limit == null
              ? '${section.length}자 (공백 포함)'
              : '${section.length}자 / $limit자 (공백 포함)',
          key: ValueKey('writing-length-$index'),
          style: TextStyle(
            color: over
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        for (final fact in section.facts) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 140,
                child: TextField(
                  controller: fact.label,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: '항목',
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: fact.text,
                  maxLength: 1200,
                  maxLines: null,
                  decoration: const InputDecoration(
                    labelText: '내용',
                    counterText: '',
                  ),
                ),
              ),
            ],
          ),
          _evidence(fact),
        ],
        for (var p = 0; p < section.paragraphs.length; p++) ...[
          const SizedBox(height: 8),
          TextField(
            key: ValueKey('writing-paragraph-$index-$p'),
            controller: section.paragraphs[p].text,
            maxLength: 1200,
            minLines: 2,
            maxLines: null,
            decoration: const InputDecoration(counterText: ''),
          ),
          _evidence(section.paragraphs[p]),
        ],
      ],
    );
  }

  Widget _evidence(_EditablePart part) {
    if (part.citations.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(
          onPressed: () => setState(() => part.open = !part.open),
          child: Text(part.open ? '근거 접기' : '근거 ${part.citations.length}개 보기'),
        ),
        if (part.open)
          for (final c in part.citations) SelectableText(_citation(c)),
      ],
    );
  }
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.type, required this.format});
  final WritingType type;
  final ExportFormat format;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _link = TextEditingController();
  bool _reviewed = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _link]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 120) {
      setState(() => _error = '문서 첫 줄에 넣을 이름을 1~120자로 입력해 주세요.');
      return;
    }
    if (!_reviewed) {
      setState(() => _error = '초안을 검토했는지 확인해 주세요.');
      return;
    }
    Navigator.pop(context, {
      'name': name,
      'email': _email.text.trim(),
      'phone': _phone.text.trim(),
      'link': _link.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.type.label} ${widget.format.label}로 받기'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('이름과 연락처는 문서에만 들어가며 AI에 보내지 않습니다.'),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('writing-export-name'),
              controller: _name,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: '이름',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              maxLength: 160,
              decoration: const InputDecoration(
                labelText: '이메일 (선택)',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: '전화번호 (선택)',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _link,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: '링크 (선택, 예: GitHub)',
                counterText: '',
              ),
            ),
            CheckboxListTile(
              key: const ValueKey('writing-export-reviewed'),
              contentPadding: EdgeInsets.zero,
              value: _reviewed,
              onChanged: (value) => setState(() => _reviewed = value ?? false),
              title: const Text('초안의 사실 관계를 검토했습니다.'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        key: const ValueKey('writing-export-confirm'),
        onPressed: _submit,
        child: Text('${widget.format.label} 만들기'),
      ),
    ],
  );
}
