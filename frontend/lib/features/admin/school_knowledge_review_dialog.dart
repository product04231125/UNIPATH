import 'package:flutter/material.dart';

import '../api/school_knowledge_api.dart';
import '../api/school_knowledge_models.dart';
import '../auth/auth_api.dart';
import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/anchored_select_field.dart';

String knowledgeStatus(String status) => switch (status) {
  'draft' => '검토 대기',
  'approved' => '근거 승인',
  'revoked' => '승인 회수',
  _ => '상태 확인 필요',
};

bool _accessLost(Object e) =>
    e is AuthFailure && {401, 403, 404}.contains(e.status);
String _failure(Object e) =>
    e is AuthFailure ? e.message : '결과를 확인하지 못했습니다. 연결과 최신 문서 상태를 확인하세요.';

/// Reads and reviews existing server extractions. It does not extract or index.
class SchoolKnowledgeReviewDialog extends StatefulWidget {
  const SchoolKnowledgeReviewDialog({
    super.key,
    required this.auth,
    required this.ownerId,
  });
  final AuthApi auth;
  final String ownerId;
  @override
  State<SchoolKnowledgeReviewDialog> createState() => _ListState();
}

class _ListState extends State<SchoolKnowledgeReviewDialog> {
  late final _api = SchoolKnowledgeAdminApi(
    widget.auth.forOwner(widget.ownerId),
  );
  List<SchoolKnowledgeView> _items = [];
  String _filter = '';
  String? _cursor, _error;
  bool _loading = false, _opening = false, _denied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_loading || _opening) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _api.list(
        status: _filter.isEmpty ? null : _filter,
        cursor: more ? _cursor : null,
      );
      if (!mounted) return;
      setState(() {
        _items = [if (more) ..._items, ...page.items];
        _cursor = page.nextCursor;
        _denied = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _failure(e);
          if (_accessLost(e)) {
            _items = [];
            _cursor = null;
            _denied = true;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(SchoolKnowledgeView item) async {
    if (_loading || _opening || _denied) return;
    setState(() => _opening = true);
    try {
      await showInputDialog<void>(
        context: context,
        builder: (_) => _ReviewDialog(
          api: _api,
          id: item.id,
          onAccessLost: () {
            if (mounted) {
              setState(() {
                _items = [];
                _cursor = null;
                _denied = true;
                _error = '현재 권한으로 문서를 검토할 수 없습니다.';
              });
            }
          },
        ),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
    if (mounted && !_denied) await _load();
  }

  @override
  Widget build(BuildContext context) => InputDialog(
    title: const Text('학교 문서 근거 검토'),
    hasContent: () => false,
    changes: const AlwaysStoppedAnimation(0),
    saving: _opening,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '문서 적용과 검색 근거 승인은 별도입니다. 이 화면의 승인은 졸업 판정이나 LLM 답변 생성을 뜻하지 않습니다.',
        ),
        const SizedBox(height: 12),
        AnchoredSelectField<String>(
          value: _filter,
          label: '검토 상태',
          options: [
            const SelectOption('', '전체'),
            for (final status in ['draft', 'approved', 'revoked'])
              SelectOption(status, knowledgeStatus(status)),
          ],
          onChanged: (value) {
            if (!_loading && !_opening) {
              _filter = value;
              _items = [];
              _cursor = null;
              _load();
            }
          },
        ),
        TextButton.icon(
          onPressed: _loading || _opening ? null : _load,
          icon: const Icon(Icons.refresh),
          label: const Text('문서 목록 다시 읽기'),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
        if (!_loading && !_denied && _items.isEmpty)
          const Text('등록된 추출본이 없습니다. 적용 문서와 추출본을 먼저 등록한 뒤 다시 읽어 주세요.'),
        for (final item in _items)
          Card(
            child: ListTile(
              title: Text(item.name),
              subtitle: Text(
                '${knowledgeStatus(item.status)} · ${item.pageCount}쪽 · 추출본 v${item.version}',
              ),
              onTap: _loading || _opening || _denied ? null : () => _open(item),
            ),
          ),
        if (_cursor != null)
          TextButton(
            onPressed: _loading || _opening ? null : () => _load(more: true),
            child: const Text('문서 더 보기'),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _opening ? null : () => InputDialog.cancel<void>(context),
        child: const Text('닫기'),
      ),
    ],
  );
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({
    required this.api,
    required this.id,
    required this.onAccessLost,
  });
  final SchoolKnowledgeAdminApi api;
  final String id;
  final VoidCallback onAccessLost;
  @override
  State<_ReviewDialog> createState() => _ReviewState();
}

class _ReviewState extends State<_ReviewDialog> {
  final _note = TextEditingController(), _hash = TextEditingController();
  final _checksChanged = ValueNotifier(0);
  late final _changes = Listenable.merge([_note, _hash, _checksChanged]);
  final _checks = [false, false, false, false];
  SchoolKnowledgeView? _document;
  List<SchoolKnowledgePageSummary> _pages = [];
  SchoolKnowledgePageView? _page;
  String? _error;
  List<String> _fields = [];
  bool _busy = false, _loading = false, _denied = false, _stale = false;
  bool get _dirty =>
      _note.text.isNotEmpty || _hash.text.isNotEmpty || _checks.any((v) => v);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    _hash.dispose();
    _checksChanged.dispose();
    super.dispose();
  }

  void _handle(Object e) {
    _error = _failure(e);
    if (_accessLost(e)) {
      _denied = true;
      _document = null;
      _pages = [];
      _page = null;
      widget.onAccessLost();
    }
  }

  Future<void> _load() async {
    if (_loading || _busy || _denied) return;
    if (_dirty && !await confirmInputDiscard(context)) return;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _document = null;
      _page = null;
      _pages = [];
    });
    try {
      final document = await widget.api.get(widget.id);
      if (document.id != widget.id) {
        throw const FormatException('Unexpected document');
      }
      final pages = <SchoolKnowledgePageSummary>[];
      final cursors = <int>{};
      int? cursor;
      do {
        final page = await widget.api.pages(widget.id, cursor: cursor);
        pages.addAll(page.items);
        cursor = page.nextCursor;
        if (cursor != null && !cursors.add(cursor)) {
          throw const FormatException('Repeated page cursor');
        }
      } while (cursor != null);
      if (!mounted) return;
      setState(() {
        _document = document;
        _pages = pages;
        _stale = false;
        _fields = [];
        _note.clear();
        _hash.clear();
        _checks.fillRange(0, _checks.length, false);
        _checksChanged.value++;
      });
    } catch (e) {
      if (mounted) setState(() => _handle(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _readPage(int number) async {
    if (_loading || _busy || _denied || _stale) return;
    setState(() {
      _loading = true;
      _error = null;
      _page = null;
    });
    try {
      final page = await widget.api.page(widget.id, number);
      if (page.knowledgeDocumentId != widget.id ||
          page.page != number ||
          page.version != _document!.version) {
        throw const FormatException('Document changed during review');
      }
      if (mounted) setState(() => _page = page);
    } catch (e) {
      if (mounted) {
        setState(() {
          _handle(e);
          _stale = true;
          if (!_denied) _error = '${_failure(e)}\n최신 자료를 다시 읽고 페이지를 확인하세요.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _fieldError(String name) =>
      _fields.any((v) => v.split('.').last == name)
      ? '서버가 입력을 거부했습니다. 형식과 내용을 확인하세요.'
      : null;

  Future<void> _decide(bool approve) async {
    final document = _document;
    if (document == null || _busy || _loading || _denied || _stale) return;
    final note = _note.text.trim(), hash = _hash.text.trim();
    if (note.isEmpty ||
        note.runes.length > 500 ||
        (approve &&
            (!_checks.every((v) => v) ||
                !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
                hash != document.documentHash))) {
      setState(
        () => _error = approve
            ? '네 가지 검토 확인과 등록된 원본에 일치하는 SHA-256, 검토 사유(1~500자)가 필요합니다.'
            : '회수 사유를 1~500자로 입력하세요.',
      );
      return;
    }
    if (approve && document.status != 'draft' ||
        !approve && document.status != 'approved') {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _fields = [];
    });
    try {
      final result = approve
          ? await widget.api.approve(
              widget.id,
              SchoolKnowledgeApprove(
                expectedVersion: document.version,
                reviewedDocumentHash: hash,
                sourceVerified: _checks[0],
                applicabilityVerified: _checks[1],
                extractionVerified: _checks[2],
                completeDocumentVerified: _checks[3],
                reviewNote: note,
              ),
            )
          : await widget.api.revoke(
              widget.id,
              SchoolKnowledgeRevoke(
                expectedVersion: document.version,
                reason: note,
              ),
            );
      if (result.id != widget.id ||
          result.status != (approve ? 'approved' : 'revoked')) {
        throw const FormatException('Unexpected review result');
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _handle(e);
          _fields = e is AuthFailure ? e.fields : [];
          _stale = e is! AuthFailure || e.status != 422;
          if (_stale) _page = null;
          if (!_denied) {
            _error =
                '${_failure(e)}\n작성한 입력은 유지했습니다.${_stale ? ' 최신 자료를 다시 읽고 검토하세요.' : ''}';
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    final editable = !_busy && !_loading && !_denied && !_stale;
    return InputDialog(
      title: const Text('추출본·적용 범위 검토'),
      changes: _changes,
      hasContent: () => _dirty,
      saving: _busy,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading || _busy) const LinearProgressIndicator(),
          if (_denied) const Text('현재 권한으로 이 문서를 볼 수 없습니다. 닫고 관리 권한을 확인하세요.'),
          if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
          if (!_denied)
            TextButton.icon(
              onPressed: _busy || _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              label: const Text('최신 자료 다시 읽기'),
            ),
          if (document != null && !_denied) ...[
            Text(document.name, style: Theme.of(context).textTheme.titleMedium),
            Text(
              '${knowledgeStatus(document.status)} · 문서 ${document.pageCount}쪽 · 원문 메타데이터 v${document.sourceDocumentVersion}',
            ),
            Text(
              '출처 확인일: ${document.sourceCheckedOn} · 추출기: ${document.extractorVersion}',
            ),
            const Text(
              '공식 원본을 별도로 열어 본문·페이지·적용 범위와 대조하세요. 원본 해시를 확인한 검토자가 직접 승인합니다.',
            ),
            ExpansionTile(
              title: const Text('원본 해시·문서 식별 정보'),
              children: [
                SelectableText(
                  '원본 SHA-256: ${document.documentHash}\n추출본 v${document.version}\n학교: ${document.institutionId}\n학과: ${document.departmentId ?? '학교 공통'}\n교육과정: ${document.curriculumId ?? '교육과정 공통'}\n원문 문서: ${document.sourceDocumentId}',
                ),
              ],
            ),
            if (document.reviewNote.isNotEmpty)
              Text('승인 검토 사유: ${document.reviewNote}'),
            if (document.approvedAt != null)
              Text('승인 시각: ${document.approvedAt!.toLocal()}'),
            if (document.revocationReason.isNotEmpty)
              Text('회수 사유: ${document.revocationReason}'),
            if (document.revokedAt != null)
              Text('회수 시각: ${document.revokedAt!.toLocal()}'),
            const SizedBox(height: 16),
            Text('등록된 페이지 ${_pages.length}개 / 원본 ${document.pageCount}쪽'),
            if (_pages.isEmpty) const Text('등록된 페이지가 없습니다. 추출본 등록 상태를 확인하세요.'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in _pages)
                  OutlinedButton(
                    onPressed: editable ? () => _readPage(p.page) : null,
                    child: Text('${p.page}쪽 ${p.isBlank ? '빈 페이지' : '본문 보기'}'),
                  ),
              ],
            ),
            if (_page case final page?) ...[
              const SizedBox(height: 12),
              Text(
                '${page.page}쪽 · ${page.isBlank ? '검토된 빈 페이지' : '${page.parts.length}개 분할'}',
              ),
              if (page.isBlank)
                const Text('원본에서 확인한 빈 페이지입니다. 검색 본문이나 인용으로 사용하지 않습니다.'),
              for (final part in page.parts)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '분할 ${part.partIndex + 1}/${part.partCount} · 문자 ${part.characterStart}~${part.characterEnd}',
                        ),
                        Text(
                          '입학연도: ${part.admissionYears?.join(', ') ?? '미확인'}\n이수 경로: ${part.tracks?.map((v) => v == 'single_major' ? '단일 전공' : v).join(', ') ?? '미확인'}',
                        ),
                        for (final warning in part.warnings)
                          Text(
                            warning == 'table_structure_requires_review'
                                ? '추출 경고: 표 구조를 원본과 대조해야 합니다.'
                                : '추출 경고: $warning',
                          ),
                        SelectableText(part.content),
                        ExpansionTile(
                          title: const Text('분할 해시'),
                          children: [SelectableText(part.contentHash)],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            if (document.status == 'draft') ...[
              for (var i = 0; i < 4; i++)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    const [
                      '공식 출처와 원본을 확인했습니다',
                      '학교·입학연도·이수 경로 적용 범위를 확인했습니다',
                      '추출 본문과 원본을 대조했습니다',
                      '빈 페이지를 포함한 원본 전체를 검토했습니다',
                    ][i],
                  ),
                  value: _checks[i],
                  onChanged: editable
                      ? (value) => setState(() {
                          _checks[i] = value!;
                          _checksChanged.value++;
                        })
                      : null,
                ),
              TextFormField(
                controller: _hash,
                enabled: editable,
                maxLength: 64,
                decoration: InputDecoration(
                  labelText: '검토한 원본 SHA-256',
                  helperText: '직접 확인한 소문자 16진수 64자',
                  errorText: _fieldError('reviewed_document_hash'),
                ),
              ),
            ],
            if (document.status == 'draft' ||
                document.status == 'approved') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _note,
                enabled: editable,
                maxLength: 500,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: document.status == 'draft' ? '검토 사유' : '승인 회수 사유',
                  helperText: '필수 · 1~500자',
                  errorText: _fieldError(
                    document.status == 'draft' ? 'review_note' : 'reason',
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => InputDialog.cancel<void>(context),
          child: const Text('닫기'),
        ),
        if (document?.status == 'draft' && !_denied)
          FilledButton(
            onPressed: editable && _checks.every((v) => v)
                ? () => _decide(true)
                : null,
            child: const Text('검색 근거로 승인'),
          ),
        if (document?.status == 'approved' && !_denied)
          FilledButton(
            onPressed: editable ? () => _decide(false) : null,
            child: const Text('근거 승인 회수'),
          ),
      ],
    );
  }
}
