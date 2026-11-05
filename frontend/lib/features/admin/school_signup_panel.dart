import 'package:flutter/material.dart';

import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/input_dialog.dart';
import '../api/school_signup_api.dart';
import '../auth/auth_api.dart';
import '../records/personal_record_repository.dart';
import 'unregistered_school_application_form.dart';

String _status(String value) => switch (value) {
  'pending' => '승인 대기',
  'approved' => '승인',
  'rejected' => '반려',
  'cancelled' => '취소',
  _ => '상태 확인 필요',
};

class SchoolSignupPanel extends StatefulWidget {
  const SchoolSignupPanel({
    super.key,
    required this.auth,
    required this.ownerId,
    this.admin = false,
    this.inline = false,
    this.draft,
    this.onBusyChanged,
    this.applicantName,
    this.initialReviewId,
    this.onDenied,
  });
  final AuthApi auth;
  final String ownerId;
  final bool admin, inline;
  final UnregisteredSchoolApplicationDraft? draft;
  final ValueChanged<bool>? onBusyChanged;
  final String? applicantName;
  final String? initialReviewId;
  final VoidCallback? onDenied;
  @override
  State<SchoolSignupPanel> createState() => _SchoolSignupPanelState();
}

class _SchoolSignupPanelState extends State<SchoolSignupPanel> {
  late final _api = SchoolSignupApi.forOwner(widget.auth, widget.ownerId);
  late final _draft = widget.draft ?? UnregisteredSchoolApplicationDraft();
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _url = TextEditingController(),
      _note = TextEditingController();
  List<SchoolAdminSignupView> _rows = [];
  List<Map<String, dynamic>> _schools = [];
  SchoolAdminSignupReviewView? _selected;
  String? _cursor, _error, _notice, _existingId;
  String _filter = '', _clientId = PersonalRecord.newId();
  SchoolAdminSignupDetails? _sent;
  bool _busy = false,
      _loading = true,
      _denied = false,
      _uncertain = false,
      _reviewUncertain = false;
  bool _newSchool = false, _identity = false, _affiliation = false;
  bool get _dirty =>
      _draft.hasContent ||
      _note.text.isNotEmpty ||
      _newSchool ||
      _existingId != null ||
      _identity ||
      _affiliation;
  @override
  void initState() {
    super.initState();
    _initialLoad();
  }

  Future<void> _initialLoad() async {
    await _load();
    final id = widget.initialReviewId;
    if (id != null && mounted && !_denied) await _fetchReview(id);
  }

  @override
  void dispose() {
    if (widget.draft == null) _draft.dispose();
    _name.dispose();
    _url.dispose();
    _note.dispose();
    super.dispose();
  }

  void _setBusy(bool value) {
    if (mounted) setState(() => _busy = value);
    widget.onBusyChanged?.call(value);
  }

  void _failure(Object error) {
    if (!mounted) return;
    setState(() {
      _error = error is AuthFailure
          ? error.message
          : '요청 결과를 확인하지 못했습니다. 입력을 유지하고 다시 확인해 주세요.';
      if (error is AuthFailure && {401, 403}.contains(error.status)) {
        _denied = true;
        _rows = [];
        _selected = null;
        _schools = [];
        _note.clear();
        _name.clear();
        _url.clear();
        _newSchool = false;
        _existingId = null;
        _identity = false;
        _affiliation = false;
      }
    });
    if (_denied) widget.onDenied?.call();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final queryStatus = _filter.isEmpty ? null : _filter;
      if (widget.admin) {
        final page = await _api.reviews(
          cursor: more ? _cursor : null,
          status: queryStatus,
        );
        final schools = await _api.institutions();
        if (!mounted) return;
        setState(() {
          _rows = [
            if (more) ..._rows,
            ...page.items.map(
              (row) => SchoolAdminSignupView.fromJson(row.toJson()),
            ),
          ];
          _cursor = page.nextCursor;
          _schools = schools;
        });
      } else {
        final page = await _api.ownList(
          cursor: more ? _cursor : null,
          status: queryStatus,
        );
        if (!mounted) return;
        setState(() {
          _rows = [if (more) ..._rows, ...page.items];
          _cursor = page.nextCursor;
        });
      }
    } catch (error) {
      _failure(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    _sent ??= SchoolAdminSignupDetails(
      clientId: _clientId,
      schoolName: _draft.schoolName.text.trim(),
      officialUrl: _draft.officialUrl.text.trim(),
      position: _draft.position.text.trim(),
      contactEmail: _draft.email.text.trim(),
      reason: _draft.reason.text.trim(),
    );
    _setBusy(true);
    try {
      final result = await _api.submit(_sent!);
      if (!mounted) return;
      for (final controller in _draft.controllers) {
        controller.clear();
      }
      setState(() {
        _notice = '신청 접수 완료 · 접수 번호 ${result.id}';
        _uncertain = false;
        _sent = null;
        _clientId = PersonalRecord.newId();
      });
      await _load();
    } catch (error) {
      if (error is! AuthFailure ||
          error.status == null ||
          (error.status ?? 0) >= 500) {
        _uncertain = true;
      } else {
        _sent = null;
      }
      _failure(error);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _open(SchoolAdminSignupView row) async {
    if (_busy) return;
    if (widget.admin && widget.inline) {
      await showInputDialog<void>(
        context: context,
        builder: (_) => SchoolSignupPanel(
          auth: widget.auth,
          ownerId: widget.ownerId,
          admin: true,
          initialReviewId: row.id,
          onDenied: () {
            if (mounted) {
              setState(() {
                _denied = true;
                _rows = [];
                _schools = [];
              });
            }
          },
        ),
      );
      if (mounted) await _load();
      return;
    }
    await _fetchReview(row.id);
  }

  Future<void> _fetchReview(String id) async {
    if (_selected != null && _dirty && !await confirmInputDiscard(context)) {
      return;
    }
    if (!mounted) return;
    _setBusy(true);
    try {
      final detail = await _api.review(id);
      if (!mounted) return;
      setState(() {
        _selected = detail;
        _reviewUncertain = false;
        _identity = false;
        _affiliation = false;
        _newSchool = false;
        _existingId = null;
        _name.text = detail.schoolName;
        _url.text = detail.officialUrl;
        _note.clear();
        _error = null;
      });
    } catch (error) {
      _failure(error);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _decide(bool approve) async {
    final row = _selected;
    if (row == null || _busy || _reviewUncertain) return;
    if (_note.text.trim().isEmpty) {
      setState(() => _error = '신청자에게 표시할 검토 사유를 입력해 주세요.');
      return;
    }
    if (approve &&
        (!_identity ||
            !_affiliation ||
            (_newSchool ? _name.text.trim().isEmpty : _existingId == null))) {
      setState(() => _error = '학교 연결 방법과 신원·학교 담당자 확인을 모두 완료해 주세요.');
      return;
    }
    _setBusy(true);
    try {
      if (approve) {
        final school = _schools
            .where((value) => value['id'] == _existingId)
            .firstOrNull;
        await _api.approve(
          row.id,
          SchoolAdminSignupApprove(
            expectedVersion: row.version,
            expectedUserVersion: row.applicant.version,
            identityVerified: true,
            affiliationVerified: true,
            reviewNote: _note.text.trim(),
            institutionId: _newSchool ? null : _existingId,
            expectedInstitutionVersion: _newSchool
                ? null
                : school?['version'] as int?,
            newInstitution: _newSchool
                ? SignupNewInstitution(
                    name: _name.text.trim(),
                    officialUrl: _url.text.trim(),
                  )
                : null,
          ),
        );
      } else {
        await _api.reject(row.id, row.version, _note.text.trim());
      }
      if (!mounted) return;
      setState(() {
        _selected = null;
        _note.clear();
        _newSchool = false;
        _existingId = null;
        _identity = false;
        _affiliation = false;
        _reviewUncertain = false;
        _name.clear();
        _url.clear();
        _notice = approve ? '학교 연결·관리자 권한 부여를 완료했습니다.' : '신청을 반려했습니다.';
      });
      await _load();
    } catch (error) {
      _failure(error);
      if (mounted &&
          (!_denied) &&
          (error is! AuthFailure ||
              error.status == null ||
              error.status == 409 ||
              (error.status ?? 0) >= 500)) {
        setState(() => _reviewUncertain = true);
      }
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _refreshDecision() async {
    final row = _selected;
    if (row == null || _busy) return;
    _setBusy(true);
    try {
      final current = await _api.review(row.id);
      final schools = await _api.institutions();
      if (mounted) {
        setState(() {
          _selected = current;
          _schools = schools;
          _reviewUncertain = false;
          _identity = false;
          _affiliation = false;
          _error = null;
        });
      }
    } catch (error) {
      _failure(error);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _cancel(SchoolAdminSignupView row) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('학교 신청을 취소할까요?'),
        content: const Text('계정과 개인 자료는 유지됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('유지'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('신청 취소'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    _setBusy(true);
    try {
      await _api.cancel(row.id, row.version);
      await _load();
    } catch (error) {
      _failure(error);
    } finally {
      _setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _busy || _loading || _denied;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.admin
              ? '최초 가입·미등록 학교 신청을 검토합니다. 학교 등록과 관리자 권한은 승인 시 함께 처리됩니다.'
              : '가입·미등록 학교 신청 이력입니다. 승인 전에는 관리자 권한이 없습니다.',
        ),
        if (_notice != null) Semantics(liveRegion: true, child: Text(_notice!)),
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_loading) const LinearProgressIndicator(),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: _busy || _loading || _denied ? null : () => _load(),
              child: const Text('신청 목록 다시 읽기'),
            ),
            for (final status in [
              '',
              'pending',
              'approved',
              'rejected',
              'cancelled',
            ])
              ChoiceChip(
                label: Text(status.isEmpty ? '전체' : _status(status)),
                selected: _filter == status,
                onSelected: disabled
                    ? null
                    : (_) async {
                        if (widget.admin &&
                            _selected != null &&
                            _dirty &&
                            !await confirmInputDiscard(context)) {
                          return;
                        }
                        if (!mounted) return;
                        setState(() {
                          _filter = status;
                          _cursor = null;
                          _rows = [];
                          _selected = null;
                          _note.clear();
                          _newSchool = false;
                          _existingId = null;
                          _identity = false;
                          _affiliation = false;
                          _reviewUncertain = false;
                        });
                        _load();
                      },
              ),
          ],
        ),
        if (!widget.admin && !_denied)
          Form(
            key: _form,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              children: [
                SchoolAdminApplicationFields(
                  draft: _draft,
                  applicantName: widget.applicantName,
                  enabled: !_busy && !_uncertain,
                ),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(
                    _busy
                        ? '접수 중…'
                        : _uncertain
                        ? '같은 신청 재확인'
                        : '미등록 학교 신청',
                  ),
                ),
              ],
            ),
          ),
        if (_rows.isEmpty && !_loading && !_denied) const Text('접수된 신청이 없습니다.'),
        for (final row in _rows)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${row.schoolName} · ${_status(row.status)}'),
                  SelectableText('접수 번호: ${row.id}'),
                  if (row.reviewNote.isNotEmpty)
                    Text('검토 사유: ${row.reviewNote}'),
                  if (row.institutionName != null)
                    Text('연결 학교: ${row.institutionName}'),
                  if (widget.admin)
                    TextButton(
                      onPressed: disabled ? null : () => _open(row),
                      child: const Text('신청 상세·심사'),
                    ),
                  if (!widget.admin && row.status == 'pending')
                    TextButton(
                      onPressed: disabled ? null : () => _cancel(row),
                      child: const Text('신청 취소'),
                    ),
                ],
              ),
            ),
          ),
        if (_cursor != null)
          TextButton(
            onPressed: disabled ? null : () => _load(more: true),
            child: const Text('더 보기'),
          ),
        if (_selected case final row?) ...[
          const Divider(),
          Text('${row.applicant.displayName} · ${row.applicant.email}'),
          Text(
            '학교: ${row.schoolName}\n홈페이지: ${row.officialUrl}\n직책: ${row.position}\n연락: ${row.contactEmail}\n사유: ${row.reason}',
          ),
          if (_reviewUncertain) ...[
            const Text(
              '심사 결과가 변경되었거나 불명확합니다. 입력을 유지했습니다. 현재 결과를 확인한 뒤 다시 심사하세요.',
            ),
            TextButton(
              onPressed: _busy ? null : _refreshDecision,
              child: const Text('심사 결과 다시 확인'),
            ),
          ],
          if (row.status == 'pending' && !_denied && !_reviewUncertain) ...[
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('기존 학교 연결'),
                  selected: !_newSchool,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _newSchool = false),
                ),
                ChoiceChip(
                  label: const Text('새 학교 등록'),
                  selected: _newSchool,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _newSchool = true),
                ),
              ],
            ),
            if (_newSchool) ...[
              TextField(
                key: const ValueKey('signup-approved-school-name'),
                controller: _name,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: '등록할 학교명'),
                maxLength: 128,
              ),
              TextField(
                controller: _url,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: '공식 홈페이지'),
                maxLength: 2048,
              ),
            ] else
              AnchoredSelectField<String>(
                value: _existingId ?? '',
                label: '연결할 기존 학교',
                searchable: true,
                options: [
                  const SelectOption('', '학교 선택'),
                  for (final school in _schools)
                    SelectOption(
                      school['id'] as String,
                      school['name'] as String,
                    ),
                ],
                onChanged: (value) {
                  if (!_busy) {
                    setState(() => _existingId = value.isEmpty ? null : value);
                  }
                },
              ),
            CheckboxListTile(
              title: const Text('신청자 신원을 별도로 확인했습니다'),
              value: _identity,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _identity = value ?? false),
            ),
            CheckboxListTile(
              title: const Text('해당 학교 담당자 자격을 확인했습니다'),
              value: _affiliation,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _affiliation = value ?? false),
            ),
            TextField(
              controller: _note,
              enabled: !_busy,
              maxLength: 500,
              decoration: const InputDecoration(labelText: '검토 사유 (신청자에게 표시)'),
            ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy ? null : () => _decide(true),
                  child: const Text('승인·학교 연결 및 권한 부여'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _decide(false),
                  child: const Text('신청 반려'),
                ),
              ],
            ),
          ],
        ],
      ],
    );
    if (widget.inline) return content;
    return InputDialog(
      changes: Listenable.merge([_draft, _note, _name, _url]),
      editing: false,
      saving: _busy,
      hasContent: () => _dirty,
      title: Text(widget.admin ? '최초 학교 신청 심사' : '가입·미등록 학교 신청'),
      content: content,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => InputDialog.cancel<void>(context),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}
