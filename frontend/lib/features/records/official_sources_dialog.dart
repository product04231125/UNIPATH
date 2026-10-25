import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/record_source_api.dart';
import '../auth/auth_api.dart';
import '../graduation/school_context_form.dart';
import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/anchored_select_field.dart';
import 'personal_record_repository.dart';

String sourceStatus(RecordSourceStatus s) => switch (s) {
  RecordSourceStatus.submitted => '검토 대기',
  RecordSourceStatus.verified => '원본 확인됨',
  RecordSourceStatus.rejected => '반려',
  RecordSourceStatus.revoked => '확인 회수',
  RecordSourceStatus.withdrawn => '검토 허용 철회',
};
String sourceKind(RecordSourceKind s) => switch (s) {
  RecordSourceKind.transcript => '성적',
  RecordSourceKind.volunteer => '봉사',
  RecordSourceKind.certificate => '자격',
  RecordSourceKind.thesis => '논문',
  RecordSourceKind.other => '기타',
};
String sourceError(Object e) =>
    e is AuthFailure ? e.message : '처리 결과를 확인하지 못했습니다. 다시 읽기로 현재 상태를 확인하세요.';
bool sourceAccessLost(Object e) =>
    e is AuthFailure && {401, 403, 404}.contains(e.status);
Widget recordAccessNotice(VoidCallback? retry, String? error) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    const Text('현재 계정이나 학교 범위로 이 자료를 확인할 수 없습니다.'),
    if (error != null) Text(error),
    if (retry == null) const LinearProgressIndicator(),
    TextButton(onPressed: retry, child: const Text('접근 상태 다시 확인')),
  ],
);

Future<void> saveSourcePdf(String name, Uint8List bytes) async {
  final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
  final file = XFile.fromData(
    bytes,
    name: safeName,
    mimeType: 'application/pdf',
  );
  if (kIsWeb) {
    await file.saveTo(safeName);
  } else {
    final location = await getSaveLocation(
      suggestedName: safeName,
      acceptedTypeGroups: [
        const XTypeGroup(label: 'PDF', extensions: ['pdf']),
      ],
    );
    if (location != null) await file.saveTo(location.path);
  }
}

class OfficialSourcesDialog extends StatefulWidget {
  const OfficialSourcesDialog({
    super.key,
    required this.auth,
    required this.ownerId,
    this.admin = false,
    this.pickPdf,
    this.exportPdf,
  });
  final AuthApi auth;
  final String ownerId;
  final bool admin;
  final Future<XFile?> Function()? pickPdf;
  final Future<void> Function(String, Uint8List)? exportPdf;
  @override
  State<OfficialSourcesDialog> createState() => _SourcesState();
}

class _SourcesState extends State<OfficialSourcesDialog> {
  late final api = RecordSourceApi.forOwner(
    widget.auth,
    widget.ownerId,
    admin: widget.admin,
  );
  final _changes = ChangeNotifier();
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await api.list(cursor: more ? _cursor : null);
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

  Future<void> _open(RecordSource row) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final detail = await api.get(row.id);
      if (!mounted) return;
      await showInputDialog<void>(
        context: context,
        builder: (_) => SourceReviewDialog(
          api: api,
          source: detail,
          actorId: widget.ownerId,
          admin: widget.admin,
          exportPdf: widget.exportPdf,
          onAccessLost: () {
            if (mounted) setState(() => _rows = []);
          },
        ),
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

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    await showInputDialog<void>(
      context: context,
      builder: (_) => _SourceUploadDialog(
        api: api,
        auth: widget.auth,
        ownerId: widget.ownerId,
        pickPdf: widget.pickPdf,
      ),
    );
    if (!mounted) return;
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => InputDialog(
    title: Text(widget.admin ? '학교 발급 원본 검토' : '학교 발급 PDF 제출'),
    hasContent: () => false,
    changes: _changes,
    saving: _busy,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '원본 확인은 학생 기록 승인이나 졸업 판정과 별개입니다. 제출 자료는 선택한 학교의 관리자만 검토할 수 있습니다.',
        ),
        if (!widget.admin)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _busy || _loading ? null : _submit,
              child: const Text('학교 발급 PDF 제출하기'),
            ),
          ),
        TextButton(
          onPressed: _busy || _loading ? null : _load,
          child: const Text('제출 목록 다시 읽기'),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (!_loading && _rows.isEmpty) const Text('확인할 제출 자료가 없습니다.'),
        for (final row in _rows)
          Card(
            child: ListTile(
              title: Text(row.filename),
              subtitle: Text(
                '${sourceKind(row.documentKind)} · ${row.issuedOn} · ${sourceStatus(row.status)}',
              ),
              onTap: _busy ? null : () => _open(row),
            ),
          ),
        if (_cursor != null)
          TextButton(
            onPressed: _busy || _loading ? null : () => _load(more: true),
            child: const Text('제출 목록 더 보기'),
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

class _SourceUploadDialog extends StatefulWidget {
  const _SourceUploadDialog({
    required this.api,
    required this.auth,
    required this.ownerId,
    this.pickPdf,
  });
  final RecordSourceApi api;
  final AuthApi auth;
  final String ownerId;
  final Future<XFile?> Function()? pickPdf;
  @override
  State<_SourceUploadDialog> createState() => _UploadState();
}

class _UploadState extends State<_SourceUploadDialog> {
  final _context = GlobalKey<SchoolContextFormState>();
  final _date = TextEditingController();
  final _changes = ValueNotifier(0);
  RecordSourceKind _kind = RecordSourceKind.transcript;
  Uint8List? _pdf;
  String _filename = '', _clientId = PersonalRecord.newId();
  String? _error, _fingerprint;
  bool _consent = false, _busy = false, _uncertain = false;
  List<String> _fields = [];
  @override
  void dispose() {
    _date.dispose();
    _changes.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() => _busy = true);
    try {
      final file =
          await (widget.pickPdf?.call() ??
              openFile(
                acceptedTypeGroups: [
                  const XTypeGroup(
                    label: 'PDF',
                    extensions: ['pdf'],
                    mimeTypes: ['application/pdf'],
                  ),
                ],
              ));
      if (file == null) return;
      if (await file.length() > 2 * 1024 * 1024) throw const FormatException();
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty ||
          bytes.length > 2 * 1024 * 1024 ||
          !file.name.toLowerCase().endsWith('.pdf') ||
          file.name.length > 128 ||
          RegExp(r'[\\/\x00-\x1f]').hasMatch(file.name) ||
          !latin1.decode(bytes.take(5).toList()).startsWith('%PDF-')) {
        throw const FormatException();
      }
      if (mounted) {
        setState(() {
          _pdf = bytes;
          _filename = file.name;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '파일명 128자 이내의 2 MiB 이하 PDF를 선택하세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    if (_busy) return;
    final school = _context.currentState?.institutionId;
    final raw = _date.text.trim();
    final date = DateTime.tryParse(raw);
    final now = DateTime.now().toUtc();
    if (school == null ||
        _pdf == null ||
        !_consent ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw) ||
        date == null ||
        date.toIso8601String().split('T').first != raw ||
        date.isAfter(DateTime(now.year, now.month, now.day))) {
      setState(() => _error = '학교·PDF·올바른 발급일과 검토 동의를 확인하세요.');
      return;
    }
    final fingerprint =
        '$school|${_context.currentState?.departmentId}|${_context.currentState?.curriculumId}|$_kind|$raw|$_filename|${base64Encode(_pdf!)}';
    if (_fingerprint != null && _fingerprint != fingerprint) {
      if (_uncertain) {
        setState(
          () => _error = '이전 제출 결과를 확인하지 못했습니다. 원래 입력으로 재시도하거나 목록에서 확인하세요.',
        );
        return;
      }
      _clientId = PersonalRecord.newId();
    }
    _fingerprint = fingerprint;
    setState(() {
      _busy = true;
      _error = null;
      _fields = [];
    });
    try {
      await widget.api.upload(
        RecordSourceUpload(
          clientId: _clientId,
          institutionId: school,
          departmentId: _context.currentState?.departmentId,
          curriculumId: _context.currentState?.curriculumId,
          documentKind: _kind,
          issuedOn: raw,
          filename: _filename,
          reviewConsentConfirmed: _consent,
        ),
        _pdf!,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _uncertain =
              e is! AuthFailure || e.status == null || e.status! >= 500;
          _fields = e is AuthFailure ? e.fields : [];
          _context.currentState?.showErrors(_fields);
          _error = '${sourceError(e)}\n선택한 PDF와 입력을 유지했습니다.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => InputDialog(
    title: const Text('학교 발급 원본 제출'),
    changes: Listenable.merge([_changes, _date]),
    saving: _busy,
    hasContent: () =>
        _pdf != null ||
        _date.text.isNotEmpty ||
        _consent ||
        _kind != RecordSourceKind.transcript ||
        (_context.currentState?.hasSelection ?? false),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SchoolContextForm(
          key: _context,
          api: widget.auth.forOwner(widget.ownerId),
          disabled: _busy,
          showStudy: false,
          showDate: false,
          onChanged: () => _changes.value++,
        ),
        AnchoredSelectField(
          value: _kind,
          label: '자료 종류',
          options: RecordSourceKind.values
              .map((k) => SelectOption(k, sourceKind(k)))
              .toList(),
          onChanged: (v) {
            if (!_busy) setState(() => _kind = v);
          },
        ),
        TextField(
          controller: _date,
          enabled: !_busy,
          decoration: InputDecoration(
            labelText: '발급일 (YYYY-MM-DD)',
            errorText: _fields.contains('issued_on') ? '발급일을 확인하세요.' : null,
          ),
        ),
        TextButton(
          onPressed: _busy ? null : _pick,
          child: const Text('PDF 선택 (최대 2 MiB)'),
        ),
        if (_pdf != null) Text('$_filename · ${_pdf!.length}바이트'),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _consent,
          onChanged: _busy
              ? null
              : (v) => setState(() => _consent = v ?? false),
          title: const Text('선택한 학교 관리자가 이 원본과 검토 이력을 확인하는 데 동의합니다.'),
        ),
        const Text('다른 개인 기록의 열람 권한은 부여하지 않습니다. 제출 후 검토 허용을 철회할 수 있습니다.'),
        if (_error != null) Text(_error!),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => InputDialog.cancel<void>(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: _busy ? null : _send,
        child: Text(_busy ? '제출 중…' : '검토 요청 제출'),
      ),
    ],
  );
}

class SourceReviewDialog extends StatefulWidget {
  const SourceReviewDialog({
    super.key,
    required this.api,
    required this.source,
    required this.actorId,
    required this.admin,
    this.exportPdf,
    this.onAccessLost,
  });
  final RecordSourceApi api;
  final RecordSource source;
  final String actorId;
  final bool admin;
  final Future<void> Function(String, Uint8List)? exportPdf;
  final VoidCallback? onAccessLost;
  @override
  State<SourceReviewDialog> createState() => _SourceReviewState();
}

class _SourceReviewState extends State<SourceReviewDialog> {
  late RecordSource _source = widget.source;
  final _reason = TextEditingController();
  final _changes = ChangeNotifier();
  List<RecordSourceEvent> _events = [];
  bool _issuer = false,
      _subject = false,
      _downloaded = false,
      _busy = false,
      _loading = true,
      _stale = false,
      _denied = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _reason.dispose();
    _changes.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final source = await widget.api.get(_source.id);
      final events = await widget.api.events(_source.id);
      if (mounted) {
        setState(() {
          _source = source;
          _events = events;
          _stale = false;
          _denied = false;
          _error = null;
          _issuer = false;
          _subject = false;
          _downloaded = false;
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

  Future<void> _download() async {
    setState(() => _busy = true);
    try {
      final bytes = await widget.api.download(_source.id);
      await (widget.exportPdf ?? saveSourcePdf)(_source.filename, bytes);
      if (mounted) setState(() => _downloaded = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = sourceError(e);
          if (sourceAccessLost(e)) {
            _denied = true;
            widget.onAccessLost?.call();
            _stale = true;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _act(String action) async {
    if (_busy || _loading || _stale) return;
    if (action != 'verify' &&
        action != 'withdraw' &&
        _reason.text.trim().isEmpty) {
      setState(() => _error = '처리 사유를 입력하세요.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          action == 'withdraw' ? '학교의 원본 검토 허용을 철회할까요?' : '검토 결과를 저장할까요?',
        ),
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
      final s = _source;
      _source = switch (action) {
        'verify' => await widget.api.verify(
          s.id,
          expectedVersion: s.version,
          expectedSha256: s.sha256,
          schoolIssuedConfirmed: _issuer,
          subjectIdentityConfirmed: _subject,
        ),
        'reject' => await widget.api.reject(
          s.id,
          expectedVersion: s.version,
          reason: _reason.text.trim(),
        ),
        'revoke' => await widget.api.revoke(
          s.id,
          expectedVersion: s.version,
          reason: _reason.text.trim(),
        ),
        _ => await widget.api.withdraw(s.id, expectedVersion: s.version),
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
    final editable = !_busy && !_loading && !_stale;
    final reviewer = widget.admin && _source.ownerId != widget.actorId;
    return InputDialog(
      title: const Text('제출 원본 상세·검토'),
      changes: Listenable.merge([_changes, _reason]),
      saving: _busy,
      hasContent: () => _reason.text.isNotEmpty || _issuer || _subject,
      content: _denied
          ? recordAccessNotice(_busy || _loading ? null : _reload, _error)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_source.filename}\n${sourceKind(_source.documentKind)} · ${_source.issuedOn} · ${sourceStatus(_source.status)}',
                ),
                Text('원본 판 ${_source.version} · ${_source.byteCount}바이트'),
                const Text('원본 확인은 학교 확인 학생 기록 승인과 별개이며 졸업요건 충족을 뜻하지 않습니다.'),
                TextButton(
                  onPressed: editable ? _download : null,
                  child: const Text('원본 PDF 내려받기'),
                ),
                TextButton(
                  onPressed: _busy || _loading ? null : _reload,
                  child: const Text('상세·검토 이력 다시 읽기'),
                ),
                if (_busy || _loading) const LinearProgressIndicator(),
                if (_error != null) Text(_error!),
                if (reviewer &&
                    _source.status == RecordSourceStatus.submitted) ...[
                  const Text('원본을 확인한 뒤 학교가 발급했는지, 제출자와 대상자가 일치하는지 별도로 검증하세요.'),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _issuer,
                    onChanged: editable
                        ? (v) => setState(() => _issuer = v ?? false)
                        : null,
                    title: const Text('학교 발급 원본임을 확인했습니다.'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _subject,
                    onChanged: editable
                        ? (v) => setState(() => _subject = v ?? false)
                        : null,
                    title: const Text('제출자와 원본 대상자의 신원을 확인했습니다.'),
                  ),
                  FilledButton(
                    onPressed: editable && _downloaded && _issuer && _subject
                        ? () => _act('verify')
                        : null,
                    child: const Text('원본 확인 승인'),
                  ),
                ],
                if (reviewer &&
                    {_source.status}.intersection({
                      RecordSourceStatus.submitted,
                      RecordSourceStatus.verified,
                    }).isNotEmpty) ...[
                  TextField(
                    controller: _reason,
                    enabled: editable,
                    maxLength: 500,
                    decoration: const InputDecoration(labelText: '처리 사유'),
                  ),
                  TextButton(
                    onPressed: editable
                        ? () => _act(
                            _source.status == RecordSourceStatus.submitted
                                ? 'reject'
                                : 'revoke',
                          )
                        : null,
                    child: Text(
                      _source.status == RecordSourceStatus.submitted
                          ? '원본 반려'
                          : '원본 확인 회수',
                    ),
                  ),
                ],
                if (!widget.admin &&
                    _source.status != RecordSourceStatus.withdrawn)
                  TextButton(
                    onPressed: editable ? () => _act('withdraw') : null,
                    child: const Text('학교 검토 허용 철회'),
                  ),
                if (widget.admin && !reviewer)
                  const Text('본인의 원본을 직접 승인할 수 없습니다.'),
                const Text('검토 이력'),
                for (final e in _events)
                  Text(
                    '${e.occurredAt.toLocal()} · ${sourceStatus(e.action)}${e.reason.isEmpty ? '' : '\n${e.reason}'}',
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
