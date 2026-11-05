import 'package:flutter/material.dart';

import '../api/official_records_api.dart';
import '../api/record_source_api.dart';
import '../api/student_catalog_api.dart';
import '../auth/auth_api.dart';
import '../../shared/widgets/input_dialog.dart';
import 'official_record_editor.dart';
import 'official_sources_dialog.dart';
import 'official_record_labels.dart';

class OfficialRecordsDialog extends StatefulWidget {
  const OfficialRecordsDialog({
    super.key,
    required this.auth,
    required this.ownerId,
    this.admin = false,
  });
  final AuthApi auth;
  final String ownerId;
  final bool admin;
  @override
  State<OfficialRecordsDialog> createState() => _RecordsState();
}

class _RecordsState extends State<OfficialRecordsDialog> {
  late final _api = OfficialRecordsApi.forOwner(
    widget.auth,
    widget.ownerId,
    admin: widget.admin,
  );
  final _changes = ChangeNotifier();
  List<SchoolRecordBatchHeader> _rows = [];
  String? _cursor, _error;
  bool _loading = true, _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _changes.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _api.list(cursor: more ? _cursor : null);
      if (mounted) {
        setState(() {
          _rows = [if (more) ..._rows, ...page.items];
          _cursor = page.nextCursor;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = sourceError(e);
          if (sourceAccessLost(e)) {
            _rows = [];
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(SchoolRecordBatchHeader row) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final detail = await _api.get(row.id);
      if (mounted) {
        await showInputDialog<void>(
          context: context,
          builder: (_) => OfficialRecordReviewDialog(
            auth: widget.auth,
            ownerId: widget.ownerId,
            admin: widget.admin,
            batch: detail,
            onAccessLost: () {
              if (mounted) setState(() => _rows = []);
            },
          ),
        );
      }
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = sourceError(e);
          if (sourceAccessLost(e)) _rows = [];
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (_busy || !widget.admin) return;
    setState(() => _busy = true);
    try {
      await showInputDialog<void>(
        context: context,
        builder: (_) =>
            _VerifiedSourcePicker(auth: widget.auth, ownerId: widget.ownerId),
      );
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = sourceError(e);
          if (sourceAccessLost(e)) _rows = [];
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => InputDialog(
    title: Text(widget.admin ? '학교 확인 학생 기록 검토' : '학교 확인 학생 기록'),
    changes: _changes,
    saving: _busy,
    hasContent: () => false,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('학교가 원본과 대조한 기록입니다. 승인된 기록도 졸업요건 충족 판정은 아닙니다.'),
        if (widget.admin)
          FilledButton(
            onPressed: _busy || _loading ? null : _create,
            child: const Text('확인된 원본에서 기록 등록'),
          ),
        TextButton(
          onPressed: _busy || _loading ? null : _load,
          child: const Text('학생 기록 다시 읽기'),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (!_loading && _rows.isEmpty) const Text('조회할 학교 확인 기록이 없습니다.'),
        for (final row in _rows)
          Card(
            child: ListTile(
              title: Text(
                '${recordLabel(row.kind)} · ${recordLabel(row.status)}',
              ),
              subtitle: Text(
                '${row.recordsAsOf} · ${row.recordCount}건 · ${recordLabel(row.coverage)}',
              ),
              onTap: _busy ? null : () => _open(row),
            ),
          ),
        if (_cursor != null)
          TextButton(
            onPressed: _busy || _loading ? null : () => _load(more: true),
            child: const Text('학생 기록 더 보기'),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => InputDialog.cancel<void>(context),
        child: const Text('닫기'),
      ),
    ],
  );
}

class _VerifiedSourcePicker extends StatefulWidget {
  const _VerifiedSourcePicker({required this.auth, required this.ownerId});
  final AuthApi auth;
  final String ownerId;
  @override
  State<_VerifiedSourcePicker> createState() => _PickerState();
}

class _PickerState extends State<_VerifiedSourcePicker> {
  final _changes = ChangeNotifier();
  late final _api = RecordSourceApi.forOwner(
    widget.auth,
    widget.ownerId,
    admin: true,
  );
  List<RecordSource> _rows = [];
  String? _cursor, _error;
  bool _loading = true, _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _changes.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() => _loading = true);
    try {
      final page = await _api.list(
        status: RecordSourceStatus.verified,
        cursor: more ? _cursor : null,
      );
      if (mounted) {
        setState(() {
          _rows = [if (more) ..._rows, ...page.items];
          _cursor = page.nextCursor;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = sourceError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _choose(RecordSource source) async {
    setState(() => _busy = true);
    try {
      final current = await _api.get(source.id);
      if (current.status != RecordSourceStatus.verified) {
        throw const AuthFailure('원본 확인 상태가 바뀌었습니다. 다시 읽으세요.');
      }
      if (!mounted) return;
      final saved = await showInputDialog<bool>(
        context: context,
        builder: (_) => OfficialRecordEditor(
          auth: widget.auth,
          ownerId: widget.ownerId,
          source: current,
        ),
      );
      if (saved == true && mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = sourceError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => InputDialog(
    title: const Text('확인된 원본 선택'),
    changes: _changes,
    saving: _busy,
    hasContent: () => false,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('기록의 소유자는 원본에서 결정됩니다. 다른 개인 기록을 가져오지 않습니다.'),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        TextButton(
          onPressed: _busy || _loading ? null : _load,
          child: const Text('원본 목록 다시 읽기'),
        ),
        if (!_loading && _rows.isEmpty)
          const Text('확인된 원본이 없습니다. 원본 검토를 먼저 완료하세요.'),
        for (final row in _rows)
          ListTile(
            title: Text(row.filename),
            subtitle: Text('${sourceKind(row.documentKind)} · ${row.issuedOn}'),
            onTap: _busy ? null : () => _choose(row),
          ),
        if (_cursor != null)
          TextButton(
            onPressed: _busy || _loading ? null : () => _load(more: true),
            child: const Text('원본 더 보기'),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => InputDialog.cancel<void>(context),
        child: const Text('취소'),
      ),
    ],
  );
}

class OfficialRecordReviewDialog extends StatefulWidget {
  const OfficialRecordReviewDialog({
    super.key,
    required this.auth,
    required this.ownerId,
    required this.admin,
    required this.batch,
    this.onAccessLost,
  });
  final AuthApi auth;
  final String ownerId;
  final bool admin;
  final SchoolRecordBatchView batch;
  final VoidCallback? onAccessLost;
  @override
  State<OfficialRecordReviewDialog> createState() => _ReviewState();
}

class _ReviewState extends State<OfficialRecordReviewDialog> {
  late final _api = OfficialRecordsApi.forOwner(
    widget.auth,
    widget.ownerId,
    admin: widget.admin,
  );
  late final _sources = RecordSourceApi.forOwner(
    widget.auth,
    widget.ownerId,
    admin: widget.admin,
  );
  late SchoolRecordBatchView _batch = widget.batch;
  final _changes = ChangeNotifier();
  final _reason = TextEditingController();
  List<SchoolRecordBatchEventView> _events = [];
  bool _records = false,
      _context = false,
      _coverage = false,
      _busy = false,
      _loading = true,
      _stale = false,
      _denied = false;
  String? _error;
  String _departmentLabel = '확인 중', _curriculumLabel = '확인 중';
  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _changes.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final batch = await _api.get(_batch.id);
      final events = await _api.events(_batch.id);
      final catalog = StudentCatalogApi(widget.auth.forOwner(widget.ownerId));
      final department = batch.context.departmentId == null
          ? '미확인'
          : (await catalog.get(
              StudentCatalogResources.departments,
              batch.context.departmentId!,
            )).name;
      final curriculum = batch.context.curriculumId == null
          ? '지정 안 함'
          : (await catalog.get(
              StudentCatalogResources.curricula,
              batch.context.curriculumId!,
            )).name;
      if (mounted) {
        setState(() {
          _batch = batch;
          _departmentLabel = department;
          _curriculumLabel = curriculum;
          _events = events.items;
          _records = _context = _coverage = false;
          _stale = false;
          _denied = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = sourceError(e);
          _stale = true;
          if (sourceAccessLost(e)) {
            _denied = true;
            widget.onAccessLost?.call();
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _source({bool edit = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final source = await _sources.get(_batch.sourceId);
      if (!mounted) return;
      await showInputDialog<void>(
        context: context,
        builder: (_) => edit
            ? OfficialRecordEditor(
                auth: widget.auth,
                ownerId: widget.ownerId,
                source: source,
                batch: _batch,
              )
            : SourceReviewDialog(
                api: _sources,
                source: source,
                actorId: widget.ownerId,
                admin: widget.admin,
              ),
      );
      if (mounted) await _reload();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = sourceError(e);
          _stale = true;
          if (sourceAccessLost(e)) {
            _denied = true;
            widget.onAccessLost?.call();
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _act(String action) async {
    if (_busy || _loading || _stale) return;
    if (action != 'approve' && _reason.text.trim().isEmpty) {
      setState(() => _error = '사유를 입력하세요.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('학생 기록 검토 결과를 저장할까요?'),
        content: const Text('승인 후에는 기록 내용을 수정할 수 없습니다. 수정본은 별도 검토해야 합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('돌아가기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _batch = switch (action) {
        'approve' => await _api.approve(
          _batch.id,
          SchoolRecordBatchApprove(
            expectedVersion: _batch.version,
            expectedSourceSha256: _batch.sourceSha256,
            recordsReviewed: _records,
            contextReviewed: _context,
            coverageReviewed: _coverage,
          ),
        ),
        'revoke' => await _api.revoke(
          _batch.id,
          SchoolRecordBatchRevoke(
            expectedVersion: _batch.version,
            reason: _reason.text.trim(),
          ),
        ),
        _ => await _api.discard(
          _batch.id,
          SchoolRecordBatchRevoke(
            expectedVersion: _batch.version,
            reason: _reason.text.trim(),
          ),
        ),
      };
      if (mounted) {
        _reason.clear();
        await _reload();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = sourceError(e);
          _stale = true;
          if (sourceAccessLost(e)) {
            _denied = true;
            widget.onAccessLost?.call();
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !_busy && !_loading && !_stale;
    final reviewer = widget.admin && _batch.ownerId != widget.ownerId;
    final b = _batch;
    return InputDialog(
      title: const Text('학교 확인 학생 기록 상세'),
      changes: Listenable.merge([_changes, _reason]),
      saving: _busy,
      hasContent: () =>
          _reason.text.isNotEmpty || _records || _context || _coverage,
      content: _denied
          ? recordAccessNotice(_busy || _loading ? null : _reload, _error)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${recordLabel(b.kind)} · ${recordLabel(b.status)} · 판 ${b.version}',
                ),
                Text(
                  '기록 기준일 ${b.recordsAsOf} · 원본 ${b.pageCount}쪽 · ${recordLabel(b.coverage)}',
                ),
                Text(
                  '입학연도 ${b.context.admissionYear?.toString() ?? '미확인'} · 이수 경로 ${b.context.track ?? '미확인'}',
                ),
                Text('학과 $_departmentLabel\n교육과정 $_curriculumLabel'),
                Text(
                  b.usableForAudit
                      ? '현재 졸업감사 입력으로 사용할 수 있는 기록입니다.'
                      : '현재 졸업감사 입력으로 사용할 수 없습니다.',
                ),
                const Text('학생 기록 승인은 졸업요건 충족 판정이 아닙니다.'),
                for (final issue in b.issues) Text(recordIssueLabel(issue)),
                if (_loading) const LinearProgressIndicator(),
                if (_error != null) Text(_error!),
                TextButton(
                  onPressed: _busy || _loading ? null : _reload,
                  child: const Text('기록·이력 다시 읽기'),
                ),
                TextButton(
                  onPressed: enabled ? () => _source() : null,
                  child: const Text('대조할 원본 상세·PDF 확인'),
                ),
                for (final row in recordRows(b.data))
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(recordSummary(row, b.references)),
                    ),
                  ),
                if (recordRows(b.data).isEmpty)
                  const Text('기록 0건. 전체/일부 검토 범위의 의미를 확인하세요.'),
                if (reviewer && b.status == 'draft') ...[
                  TextButton(
                    onPressed: enabled ? () => _source(edit: true) : null,
                    child: const Text('검토 초안 수정'),
                  ),
                  for (final entry in [
                    (
                      '원본의 기록과 각 페이지 대응을 대조했습니다.',
                      _records,
                      (bool v) => _records = v,
                    ),
                    (
                      '학과·교육과정·입학연도·이수 경로를 확인했습니다.',
                      _context,
                      (bool v) => _context = v,
                    ),
                    (
                      '전체/일부 검토 범위를 확인했습니다.',
                      _coverage,
                      (bool v) => _coverage = v,
                    ),
                  ])
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.$1),
                      value: entry.$2,
                      onChanged: enabled
                          ? (v) => setState(() => entry.$3(v ?? false))
                          : null,
                    ),
                  FilledButton(
                    onPressed: enabled && _records && _context && _coverage
                        ? () => _act('approve')
                        : null,
                    child: const Text('학생 기록 승인'),
                  ),
                ],
                if (reviewer &&
                    (b.status == 'draft' || b.status == 'approved')) ...[
                  TextField(
                    controller: _reason,
                    enabled: enabled,
                    maxLength: 500,
                    decoration: const InputDecoration(labelText: '회수·폐기 사유'),
                  ),
                  TextButton(
                    onPressed: enabled
                        ? () => _act(b.status == 'draft' ? 'discard' : 'revoke')
                        : null,
                    child: Text(
                      b.status == 'draft' ? '검토 초안 폐기' : '학생 기록 승인 회수',
                    ),
                  ),
                ],
                if (widget.admin && !reviewer)
                  const Text('본인의 학생 기록을 직접 승인할 수 없습니다.'),
                const Text('검토 이력'),
                for (final e in _events)
                  Text(
                    '${e.occurredAt.toLocal()} · ${recordLabel(e.action)}${e.reason.isEmpty ? '' : '\n${e.reason}'}',
                  ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => InputDialog.cancel<void>(context),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}
