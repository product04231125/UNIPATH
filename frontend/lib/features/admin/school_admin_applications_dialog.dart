import 'package:flutter/material.dart';

import '../api/admin_application_api.dart';
import '../api/student_catalog_api.dart';
import '../api/student_api_models.dart';
import '../auth/auth_api.dart';
import '../auth/app_role.dart';
import '../records/personal_record_repository.dart';
import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/anchored_select_field.dart';
import 'unregistered_school_application_form.dart';

String applicationStatus(String status) => switch (status) {
  'pending' => '승인 대기',
  'approved' => '승인',
  'rejected' => '반려',
  'cancelled' => '취소',
  _ => '상태 확인 필요',
};

String _failure(Object error) => error is AuthFailure
    ? '${error.message}\n작성한 입력을 유지했습니다.${error.fields.isEmpty ? '' : '\n확인할 입력: ${error.fields.map((field) => switch (field.split('.').last) {
              'position' => '직책',
              'contact_email' => '연락 이메일',
              'reason' => '신청 사유',
              'institution_id' => '신청 학교',
              'review_note' => '검토 사유',
              _ => '입력 정보',
            }).join(', ')}'}'
    : '요청 결과를 확인하지 못했습니다. 입력을 유지했습니다. 연결을 확인하고 다시 시도하세요.';

/// Uses an owner-bound capability captured for this login, never a selected role.
class SchoolAdminApplicationsDialog extends StatefulWidget {
  const SchoolAdminApplicationsDialog({
    super.key,
    required this.auth,
    required this.identity,
  });
  final AuthApi auth;
  final AuthIdentity identity;
  @override
  State<SchoolAdminApplicationsDialog> createState() => _ApplicationsState();
}

class _ApplicationsState extends State<SchoolAdminApplicationsDialog> {
  late final _own = SchoolAdminApplicationsApi.forOwner(
    widget.auth,
    widget.identity.id,
  );
  late final _reviews = SchoolAdminApplicationReviewsApi.forOwner(
    widget.auth,
    widget.identity.id,
  );
  late final _catalog = StudentCatalogApi(
    widget.auth.forOwner(widget.identity.id),
  );
  final _form = GlobalKey<FormState>();
  final _position = TextEditingController(),
      _email = TextEditingController(),
      _reason = TextEditingController();
  final _unregisteredDraft = UnregisteredSchoolApplicationDraft();
  late final _changes = Listenable.merge([
    _position,
    _email,
    _reason,
    _unregisteredDraft,
  ]);
  List<StudentInstitutionView> _schools = [];
  List<SchoolAdminApplicationView> _items = [];
  List<SchoolAdminApplicationReviewView> _reviewItems = [];
  String? _school, _cursor, _error, _notice, _requestFingerprint;
  String _filter = '', _clientId = PersonalRecord.newId();
  bool _loading = true, _busy = false, _uncertain = false;
  bool _unregistered = false;
  List<String> _fieldErrors = [];
  String? _fieldError(String key) =>
      _fieldErrors.any((f) => f.split('.').last == key)
      ? '입력 형식과 내용을 확인하세요.'
      : null;
  bool get _review => widget.identity.role == AppRole.superAdmin;
  bool get _dirty =>
      _school != null ||
      _unregisteredDraft.hasContent ||
      [_position, _email, _reason].any((c) => c.text.isNotEmpty);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_position, _email, _reason]) {
      c.dispose();
    }
    _unregisteredDraft.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_review) {
        final page = await _reviews.list(
          status: _filter.isEmpty ? null : _filter,
          cursor: more ? _cursor : null,
        );
        if (!mounted) return;
        setState(() {
          _reviewItems = [if (more) ..._reviewItems, ...page.items];
          _cursor = page.nextCursor;
        });
      } else {
        final schools = <StudentInstitutionView>[];
        String? cursor;
        do {
          final page = await _catalog.list(
            StudentCatalogResources.institutions,
            cursor: cursor,
          );
          schools.addAll(page.items);
          cursor = page.nextCursor;
        } while (cursor != null);
        final page = await _own.list(cursor: more ? _cursor : null);
        if (!mounted) return;
        setState(() {
          _schools = schools;
          _items = [if (more) ..._items, ...page.items];
          _cursor = page.nextCursor;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _failure(e);
          if (e is AuthFailure && {401, 403, 404}.contains(e.status)) {
            _items = [];
            _reviewItems = [];
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || _unregistered) return;
    _fieldErrors = [];
    if (!_form.currentState!.validate()) return;
    final fingerprint = [
      _school,
      _position.text.trim(),
      _email.text.trim(),
      _reason.text.trim(),
    ].join('\n');
    if (_requestFingerprint != null && fingerprint != _requestFingerprint) {
      if (_uncertain) {
        setState(
          () => _error = '앞선 신청의 결과가 불명확합니다. 원래 입력으로 재시도하거나 신청 이력을 확인하세요.',
        );
        return;
      }
      _clientId = PersonalRecord.newId();
    }
    _requestFingerprint = fingerprint;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await _own.submit(
        SchoolAdminApplicationCreate(
          institutionId: _school!,
          clientId: _clientId,
          position: _position.text.trim(),
          contactEmail: _email.text.trim(),
          reason: _reason.text.trim(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _uncertain = false;
        _school = null;
        _position.clear();
        _email.clear();
        _reason.clear();
        _clientId = PersonalRecord.newId();
        _requestFingerprint = null;
        _notice = '신청이 접수됐습니다. 승인 전에는 관리 권한이 부여되지 않습니다.';
      });
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _uncertain =
              e is! AuthFailure || e.status == null || e.status! >= 500;
          _error = _failure(e);
          _fieldErrors = e is AuthFailure ? e.fields : [];
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(SchoolAdminApplicationView item) async {
    if (_busy) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('학교관리자 신청을 취소할까요?'),
        content: Text(item.institutionName),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('유지'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('신청 취소'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _own.cancel(item.id, item.version);
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _failure(e);
          if (e is AuthFailure && {401, 403, 404}.contains(e.status)) {
            _items = [];
            _reviewItems = [];
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _inspect(SchoolAdminApplicationReviewView item) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final current = await _reviews.get(item.id);
      if (!mounted) return;
      await showInputDialog<void>(
        context: context,
        builder: (_) => _ApplicationReviewDialog(
          api: _reviews,
          application: current,
          reviewer: widget.identity.id,
          onAccessLost: () {
            if (mounted) {
              setState(() {
                _items = [];
                _reviewItems = [];
              });
            }
          },
        ),
      );
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _failure(e);
          if (e is AuthFailure && {401, 403, 404}.contains(e.status)) {
            _items = [];
            _reviewItems = [];
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => InputDialog(
    title: Text(_review ? '학교관리자 신청 접수' : '학교관리자 가입 신청'),
    hasContent: () => _dirty,
    changes: _changes,
    saving: _busy,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _review
              ? '신청자의 신원과 학교 담당자 자격을 별도로 확인한 뒤 심사하세요.'
              : '일반 계정으로 학교 관리 권한을 신청합니다. 승인 결과와 사유는 아래 이력에서 확인할 수 있습니다.',
        ),
        if (_notice != null && !_unregistered)
          Semantics(liveRegion: true, child: Text(_notice!)),
        if (_error != null && !_unregistered) ...[
          Semantics(liveRegion: true, child: Text(_error!)),
          TextButton(
            onPressed: _busy || _loading ? null : _load,
            child: const Text('신청 이력 다시 읽기'),
          ),
        ],
        if (_loading) const LinearProgressIndicator(),
        if (!_review) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('등록된 학교'),
                selected: !_unregistered,
                onSelected: _busy
                    ? null
                    : (_) => setState(() => _unregistered = false),
              ),
              ChoiceChip(
                label: const Text('미등록 학교'),
                selected: _unregistered,
                onSelected: _busy
                    ? null
                    : (_) => setState(() => _unregistered = true),
              ),
            ],
          ),
        ],
        if (!_review && _unregistered)
          UnregisteredSchoolApplicationForm(
            draft: _unregisteredDraft,
            applicantName: widget.identity.displayName,
            enabled: !_busy,
          ),
        if (!_review && !_unregistered) ...[
          TextButton(
            onPressed: _busy || _loading ? null : _load,
            child: const Text('학교 목록 다시 읽기'),
          ),
          Form(
            key: _form,
            child: Column(
              children: [
                const SizedBox(height: 16),
                AnchoredSelectField<String?>(
                  value: _schools.any((s) => s.id == _school) ? _school : null,
                  label: '신청 학교',
                  searchable: true,
                  options: [
                    const SelectOption(null, '학교 선택'),
                    ..._schools.map((s) => SelectOption(s.id, s.name)),
                  ],
                  onChanged: (v) {
                    if (!_busy && !_loading) setState(() => _school = v);
                  },
                ),
                ...[
                  (c: _position, label: '직책', max: 128),
                  (c: _email, label: '연락 이메일', max: 254),
                  (c: _reason, label: '신청 사유', max: 1000),
                ].map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextFormField(
                      controller: f.c,
                      enabled: !_busy,
                      decoration: InputDecoration(
                        labelText: f.label,
                        errorText: _fieldError(
                          f.c == _position
                              ? 'position'
                              : f.c == _email
                              ? 'contact_email'
                              : 'reason',
                        ),
                      ),
                      maxLength: f.max,
                      maxLines: f.c == _reason ? 3 : 1,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? '${f.label}을 입력하세요.'
                          : null,
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: _busy || _loading || _schools.isEmpty
                      ? null
                      : () {
                          if (_school == null ||
                              !_schools.any((s) => s.id == _school)) {
                            setState(() => _error = '신청 학교를 선택하세요.');
                            return;
                          }
                          _submit();
                        },
                  child: Text(_busy ? '처리 중…' : '신청 제출'),
                ),
              ],
            ),
          ),
        ],
        if (!_review &&
            !_unregistered &&
            !_loading &&
            _schools.isEmpty &&
            _error == null)
          const Text('신청 가능한 학교가 없습니다. 미등록 학교 유형에서 정보를 작성할 수 있습니다.'),
        const SizedBox(height: 20),
        Text(
          _review ? '접수 목록' : '내 신청 이력',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (!_review)
          const Text('서버에 접수된 신청만 표시합니다. 미등록 학교 작성 내용은 이력에 포함되지 않습니다.'),
        if (_review)
          AnchoredSelectField(
            value: _filter,
            label: '신청 상태',
            options: [
              const SelectOption('', '전체'),
              ...[
                'pending',
                'approved',
                'rejected',
                'cancelled',
              ].map((s) => SelectOption(s, applicationStatus(s))),
            ],
            onChanged: (v) {
              if (!_busy && !_loading) {
                _filter = v;
                _load();
              }
            },
          ),
        if (!_loading && (_review ? _reviewItems.isEmpty : _items.isEmpty))
          const Text('신청 내역이 없습니다.'),
        if (_review)
          ..._reviewItems.map(
            (r) => Card(
              child: ListTile(
                title: Text(
                  '${r.institutionName} · ${applicationStatus(r.status)}',
                ),
                subtitle: Text('${r.applicant.displayName} · ${r.position}'),
                onTap: _busy ? null : () => _inspect(r),
              ),
            ),
          )
        else
          ..._items.map(
            (r) => Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r.institutionName} · ${applicationStatus(r.status)}',
                    ),
                    Text(
                      '${r.createdAt.toLocal()}\n${r.position}\n${r.reason}',
                    ),
                    if (r.reviewNote.isNotEmpty) Text('검토 사유: ${r.reviewNote}'),
                    if (r.status == 'pending')
                      TextButton(
                        onPressed: _busy ? null : () => _cancel(r),
                        child: const Text('신청 취소'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        if (_cursor != null)
          TextButton(
            onPressed: _busy || _loading ? null : () => _load(more: true),
            child: const Text('더 보기'),
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

class _ApplicationReviewDialog extends StatefulWidget {
  const _ApplicationReviewDialog({
    required this.api,
    required this.application,
    required this.reviewer,
    required this.onAccessLost,
  });
  final SchoolAdminApplicationReviewsApi api;
  final SchoolAdminApplicationReviewView application;
  final String reviewer;
  final VoidCallback onAccessLost;
  @override
  State<_ApplicationReviewDialog> createState() => _ReviewState();
}

class _ReviewState extends State<_ApplicationReviewDialog> {
  final _note = TextEditingController();
  final _changes = ChangeNotifier();
  bool _identity = false,
      _affiliation = false,
      _busy = false,
      _denied = false,
      _stale = false;
  String? _error;
  @override
  void dispose() {
    _note.dispose();
    _changes.dispose();
    super.dispose();
  }

  Future<void> _decide(bool approve) async {
    if (_busy) return;
    if (_note.text.trim().isEmpty) {
      setState(() => _error = '신청자에게 전달할 검토 사유를 입력하세요.');
      return;
    }
    final r = widget.application;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (approve) {
        await widget.api.approve(
          r.id,
          SchoolAdminApplicationApprove(
            expectedVersion: r.version,
            expectedUserVersion: r.applicant.version,
            reviewNote: _note.text.trim(),
            identityVerified: _identity,
            affiliationVerified: _affiliation,
          ),
        );
      } else {
        await widget.api.reject(
          r.id,
          SchoolAdminApplicationReject(
            expectedVersion: r.version,
            reviewNote: _note.text.trim(),
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '${_failure(e)}\n닫고 목록을 다시 읽어 최신 상태를 확인하세요.';
          _denied = e is AuthFailure && {401, 403, 404}.contains(e.status);
          _stale = e is! AuthFailure || e.status != 422;
          if (_denied) widget.onAccessLost();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.application;
    final canReview =
        !_denied &&
        !_stale &&
        r.status == 'pending' &&
        r.applicantId != widget.reviewer;
    return InputDialog(
      title: const Text('학교관리자 신청 검토'),
      changes: Listenable.merge([_note, _changes]),
      hasContent: () => _note.text.isNotEmpty || _identity || _affiliation,
      saving: _busy,
      content: _denied
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('현재 권한으로 이 신청을 검토할 수 없습니다. 닫고 접수 목록을 다시 확인하세요.'),
                if (_error != null) Text(_error!),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${r.institutionName} · ${applicationStatus(r.status)}'),
                Text(
                  '${r.applicant.displayName}\n${r.applicant.email}\n${r.position}\n${r.contactEmail}\n${r.reason}',
                ),
                if (r.reviewNote.isNotEmpty) Text('검토 사유: ${r.reviewNote}'),
                if (canReview) ...[
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('신청자 신원을 별도로 확인했습니다'),
                    value: _identity,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _identity = v!),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('해당 학교 담당자 자격을 확인했습니다'),
                    value: _affiliation,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _affiliation = v!),
                  ),
                  TextField(
                    controller: _note,
                    enabled: !_busy,
                    maxLength: 500,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '검토 사유 (신청자에게 표시)',
                    ),
                  ),
                ],
                if (_error != null)
                  Semantics(liveRegion: true, child: Text(_error!)),
              ],
            ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => InputDialog.cancel<void>(context),
          child: const Text('닫기'),
        ),
        if (canReview) ...[
          OutlinedButton(
            onPressed: _busy ? null : () => _decide(false),
            child: const Text('반려'),
          ),
          FilledButton(
            onPressed: _busy || !_identity || !_affiliation
                ? null
                : () => _decide(true),
            child: const Text('승인·학교 범위 부여'),
          ),
        ],
      ],
    );
  }
}
