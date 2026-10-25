import '../../shared/widgets/responsive_columns.dart';
import '../../shared/widgets/responsive_panels.dart';
import '../../shared/app_style.dart';
import '../settings/appearance_settings_section.dart';

import 'package:flutter/material.dart';

import '../auth/app_role.dart';
import '../../shared/widgets/content_scroll_view.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/external_link_button.dart';
import 'admin_models.dart';
import 'admin_repository.dart';
import 'admin_editor.dart';
import 'admin_shell.dart';
import 'school_admin_application_inbox.dart';

class AdminWorkspace extends StatefulWidget {
  const AdminWorkspace({
    super.key,
    required this.role,
    required this.path,
    required this.onNavigate,
    required this.onSignedOut,
    this.repository,
    this.sidebarVisible = true,
    this.actorId,
    this.beforeSignedOut,
  });
  final AppRole role;
  final String path;
  final ValueChanged<String> onNavigate;
  final VoidCallback onSignedOut;
  final AdminRepository? repository;
  final bool sidebarVisible;
  final String? actorId;
  final Future<void> Function()? beforeSignedOut;
  static const menus = <String, String>{
    '/admin/overview': '관리 현황',
    '/admin/schools': '학교·학과',
    '/admin/curricula': '교육과정·과목',
    '/admin/rules': '졸업요건',
    '/admin/documents': '공식 문서',
    '/admin/history': '관리 이력',
    '/admin/accounts': '관리자 관리',
    '/admin/applications': '학교관리자 신청 접수',
    '/admin/settings': '설정',
  };
  @override
  State<AdminWorkspace> createState() => _AdminWorkspaceState();
}

class _AdminWorkspaceState extends State<AdminWorkspace> {
  late final AdminRepository _repo;
  bool _loading = true;
  String? _loadError, _error;
  String _schoolId = '';
  bool _busy = false;
  final _editorKeys = <AdminKind, GlobalKey<AdminEditorState>>{};
  Future<bool> _allowLeave() async {
    for (final key in _editorKeys.values) {
      if (key.currentState != null && !await key.currentState!.allowLeave()) {
        return false;
      }
    }
    return mounted;
  }

  Future<void> _navigate(String path) async {
    if (path == widget.path) return;
    if (await _allowLeave()) widget.onNavigate(path);
  }

  String _pathFor(AdminKind kind) => switch (kind) {
    AdminKind.institution || AdminKind.department => '/admin/schools',
    AdminKind.curriculum ||
    AdminKind.course ||
    AdminKind.curriculumCourse => '/admin/curricula',
    AdminKind.ruleSet || AdminKind.rule => '/admin/rules',
    AdminKind.document => '/admin/documents',
    _ => '/admin/accounts',
  };

  final _queries = <AdminKind, String>{};
  final _statuses = <AdminKind, String>{};
  String get _actor =>
      widget.actorId ??
      (widget.role == AppRole.superAdmin ? 'super-admin' : 'school-admin');
  AppRole get _role =>
      widget.role == AppRole.user ? AppRole.user : _repo.role(_actor);
  String get _section {
    final parts = widget.path.split('/');
    return parts.length > 2 ? parts.take(3).join('/') : '/admin/overview';
  }

  String? get _detailId {
    final parts = widget.path.split('/');
    return parts.length == 4 && parts[3].isNotEmpty ? parts[3] : null;
  }

  AdminRecord? _find(String id) =>
      _repo.records.where((r) => r.id == id).firstOrNull;
  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? FakeAdminRepository();
    _repo.addListener(_refresh);
    _load();
  }

  @override
  void dispose() {
    _repo.removeListener(_refresh);
    if (widget.repository == null) _repo.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _signOut() async {
    if (_busy) return;
    if (!await _allowLeave() || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.beforeSignedOut?.call();
      if (mounted) widget.onSignedOut();
    } catch (_) {
      if (mounted) setState(() => _error = '로그아웃하지 못했습니다. 연결을 확인하고 다시 시도하세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await _repo.load();
    } catch (error) {
      _loadError = error is StateError
          ? error.message.toString()
          : '관리 데이터를 읽지 못했습니다.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Iterable<AdminRecord> get _schools => _repo.records.where(
    (r) =>
        widget.role != AppRole.user &&
        r.kind == AdminKind.institution &&
        _repo.canRead(_actor, r),
  );
  Iterable<AdminRecord> _rows(AdminKind kind) => _repo.records.where(
    (r) =>
        r.kind == kind &&
        _repo.canRead(_actor, r) &&
        (kind == AdminKind.account ||
            kind == AdminKind.scope ||
            _repo.school(r) == _schoolId),
  );
  Future<void> _edit(
    AdminKind kind, [
    AdminRecord? record,
    bool revoke = false,
  ]) async {
    if (record == null && !revoke) {
      final path = _pathFor(kind);
      if (_section != path || _detailId != null) await _navigate(path);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _editorKeys[kind]?.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            duration: const Duration(milliseconds: 200),
          );
        }
      });
      return;
    }
    await showInputDialog<void>(
      context: context,
      builder: (_) => AdminEditor(
        repository: _repo,
        actorId: _actor,
        kind: kind,
        schoolId: _schoolId,
        record: record,
        revoke: revoke,
      ),
    );
  }

  Future<void> _confirmAction(
    AdminRecord r,
    String action,
    Future<void> Function() operation,
  ) async {
    if (_busy) return;
    int referenceCount = 0;
    if (action == '삭제') {
      setState(() => _busy = true);
      try {
        referenceCount = await _repo.referenceCount(r);
      } catch (error) {
        if (mounted) {
          setState(
            () => _error = error is StateError
                ? error.message.toString()
                : '연결 참조를 확인하지 못했습니다. 다시 시도하세요.',
          );
        }
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      if (!mounted) return;
    }
    final references = _repo.records.where(
      (other) =>
          other.id != r.id &&
          [
            'institutionId',
            'departmentId',
            'curriculumId',
            'courseId',
            'ruleId',
            'ruleSetId',
          ].any((key) => other.value(key) == r.id),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${r.name} · $action'),
        content: Text(
          action == '초안 적용'
              ? 'v${r.revision}의 내용·관리 범위·근거를 검토했습니까?'
              : '대상과 연결 영향을 확인하세요. 참조가 남은 삭제는 차단하고 적용 이력은 보존합니다.\n연결된 항목 $referenceCount개: ${references.where((other) => _repo.canRead(_actor, other)).map((other) => other.name).join(', ')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: action == '삭제' ? destructiveButtonStyle(context) : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
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
      await operation();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is StateError ? e.message : '처리하지 못했습니다. 다시 시도하세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _canCreate(AdminKind kind) {
    if (_role == AppRole.superAdmin) return kind != AdminKind.account;
    if ([
      AdminKind.institution,
      AdminKind.account,
      AdminKind.scope,
    ].contains(kind)) {
      return false;
    }
    return _repo.records.any(
      (r) =>
          r.kind == AdminKind.scope &&
          r.status == 'active' &&
          r.value('userId') == _actor &&
          r.value('institutionId') == _schoolId &&
          (r.value('scopeType') == 'institution' ||
              r.value('scopeType') == 'department' &&
                  kind != AdminKind.course &&
                  kind != AdminKind.department ||
              r.value('scopeType') == 'curriculum' &&
                  [
                    AdminKind.ruleSet,
                    AdminKind.rule,
                    AdminKind.document,
                    AdminKind.curriculumCourse,
                  ].contains(kind)),
    );
  }

  String _status(AdminRecord r) =>
      r.kind == AdminKind.account ? r.value('accountStatus') : r.status;
  String _statusLabel(String status) => switch (status) {
    'draft' => '초안',
    'applied' => '적용됨',
    'active' => '활성',
    'revoked' => '회수됨',
    'suspended' => '정지',
    _ => '알 수 없는 상태',
  };
  String _relationName(String id) {
    final r = _find(id);
    return r != null && _repo.canRead(_actor, r) ? r.name : '';
  }

  String _scopeSummary(AdminRecord scope) => switch (scope.value('scopeType')) {
    'institution' => '학교 전체',
    'department' =>
      '${_relationName(scope.value('departmentId')).isEmpty ? '학과' : _relationName(scope.value('departmentId'))} 범위',
    'curriculum' =>
      '${_relationName(scope.value('curriculumId')).isEmpty ? '교육과정' : _relationName(scope.value('curriculumId'))} 범위',
    _ => '범위 유형 확인 필요',
  };

  String _recordContext(AdminRecord r) => [
    if (_repo.school(r) != r.id) _relationName(_repo.school(r)),
    for (final key in [
      'departmentId',
      'curriculumId',
      'courseId',
      'ruleSetId',
      'userId',
    ])
      _relationName(r.value(key)),
    if (r.value('year').isNotEmpty) '${r.value('year')}년 적용',
    if (r.value('code').isNotEmpty) '코드 ${r.value('code')}',
    if (r.value('credits').isNotEmpty) '${r.value('credits')}학점',
    if (r.kind == AdminKind.scope)
      switch (r.value('scopeType')) {
        'institution' => '학교 전체',
        'department' => '학과 범위',
        'curriculum' => '교육과정 범위',
        _ => '범위 유형 확인 필요',
      },
  ].where((s) => s.isNotEmpty).toSet().join(' · ');
  Iterable<AdminRecord> _filteredRows(AdminKind kind) => _rows(kind).where((r) {
    if (kind == AdminKind.institution) return true;
    final query = (_queries[kind] ?? '').trim().toLowerCase();
    return '${r.name} ${_recordContext(r)}'.toLowerCase().contains(query) &&
        ((_statuses[kind] ?? '').isEmpty || _status(r) == _statuses[kind]);
  });

  Widget _records(AdminKind kind) => ResponsiveColumns(
    key: ValueKey('admin-registration-${kind.name}-$_schoolId'),
    enabled: true,
    first: _recordList(kind),
    second: _canCreate(kind)
        ? AdminEditor(
            key: _editorKeys.putIfAbsent(
              kind,
              () => GlobalKey<AdminEditorState>(),
            ),
            repository: _repo,
            actorId: _actor,
            kind: kind,
            schoolId: _schoolId,
            inline: true,
          )
        : const SizedBox.shrink(),
  );
  Widget _recordList(AdminKind kind) => Column(
    key: ValueKey('admin-section-${kind.name}'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 16),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(
            AdminWorkspace.menus[_section] == kind.label ? '목록' : kind.label,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_canCreate(kind))
            FilledButton(
              onPressed: _busy ? null : () => _edit(kind),
              child: Text('${kind.label} 등록'),
            ),
        ],
      ),
      if (kind != AdminKind.institution && _rows(kind).isNotEmpty) ...[
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey('admin-search-$_schoolId-${kind.name}'),
          initialValue: _queries[kind] ?? '',
          decoration: InputDecoration(
            labelText: '${kind.label} 이름·소속·코드 검색',
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => _queries[kind] = value),
        ),
        if (kind.versioned ||
            kind == AdminKind.scope ||
            kind == AdminKind.account) ...[
          const SizedBox(height: 8),
          AnchoredSelectField<String>(
            externalLabel: true,
            key: ValueKey('admin-status-${kind.name}'),
            value: _statuses[kind] ?? '',
            label: '${kind.label} 상태',
            options: [
              const SelectOption('', '전체 상태'),
              for (final status in _rows(kind).map(_status).toSet())
                SelectOption(status, _statusLabel(status)),
            ],
            onChanged: (value) => setState(() => _statuses[kind] = value),
          ),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '${_filteredRows(kind).length}개 표시 / ${_rows(kind).length}개',
          ),
        ),
        if (_filteredRows(kind).isEmpty)
          const Text('검색·필터에 맞는 항목이 없습니다. 검색어와 상태를 바꿔보세요.'),
      ],
      if (_rows(kind).isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            '${kind.label} 데이터가 없습니다.${_canCreate(kind) ? ' 옆의 등록 영역에서 시작하세요.' : '권한과 관리 범위를 확인하세요.'}',
          ),
        ),
      ResponsivePanels(
        enabled: kind == AdminKind.document,
        children: [
          for (final r in _filteredRows(kind))
            Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      r.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_recordContext(r).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _recordContext(r),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    if (kind.versioned)
                      Text('v${r.revision} · ${_statusLabel(r.status)}'),
                    if (kind == AdminKind.scope) Text(_statusLabel(r.status)),
                    if (kind == AdminKind.account)
                      Text(
                        '${roleFromRecord(r).label} · ${_statusLabel(r.value('accountStatus'))}',
                      ),
                    if (kind == AdminKind.account && _repo.live)
                      Text(r.value('email')),
                    const SizedBox(height: 16),
                    _recordActions(r),
                  ],
                ),
              ),
            ),
        ],
      ),
    ],
  );
  Widget _recordActions(AdminRecord r, {bool detail = false}) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      if (!detail)
        OutlinedButton.icon(
          onPressed: () => _navigate('$_section/${r.id}'),
          icon: const Icon(Icons.arrow_forward, size: 18),
          label: const Text('상세'),
        ),
      if (_repo.canWrite(_actor, r) &&
          !(_repo.live && r.kind == AdminKind.scope) &&
          r.status != 'applied' &&
          r.status != 'revoked' &&
          r.id != _actor)
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          onPressed: _busy ? null : () => _edit(r.kind, r),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('수정'),
        ),
      if (_repo.canWrite(_actor, r) &&
          r.kind.versioned &&
          r.value('ruleSetId').isEmpty &&
          r.status == 'draft')
        FilledButton.tonal(
          onPressed: _busy
              ? null
              : () =>
                    _confirmAction(r, '초안 적용', () => _repo.apply(_actor, r.id)),
          child: const Text('검토·적용'),
        ),
      if (_repo.canWrite(_actor, r) &&
          r.kind.versioned &&
          r.value('ruleSetId').isEmpty &&
          r.status == 'applied')
        FilledButton.tonal(
          onPressed: _busy
              ? null
              : () => _confirmAction(r, '새 버전 초안', () async {
                  await _repo.newVersion(_actor, r.id);
                }),
          child: const Text('새 버전 초안'),
        ),
      if (_repo.canWrite(_actor, r) &&
          r.kind == AdminKind.scope &&
          r.status == 'active')
        OutlinedButton.icon(
          style: _dangerStyle(),
          icon: const Icon(Icons.remove_circle_outline, size: 18),
          onPressed: _busy ? null : () => _edit(r.kind, r, true),
          label: const Text('범위 회수'),
        ),
      if (_repo.canWrite(_actor, r) &&
          ![AdminKind.scope, AdminKind.account].contains(r.kind) &&
          r.status != 'applied')
        OutlinedButton.icon(
          style: _dangerStyle(),
          icon: const Icon(Icons.delete_outline, size: 18),
          onPressed: _busy
              ? null
              : () => _confirmAction(r, '삭제', () async {
                  await _repo.remove(_actor, r.id);
                  if (mounted && detail) widget.onNavigate(_section);
                }),
          label: const Text('삭제'),
        ),
    ],
  );

  ButtonStyle _dangerStyle() => destructiveButtonStyle(context);

  Widget _detail(AdminRecord r) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextButton(
        onPressed: () => _navigate(_section),
        child: const Text('목록으로'),
      ),
      Text(r.name, style: Theme.of(context).textTheme.titleLarge),
      Text(_recordContext(r), style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 12),
      _recordActions(r, detail: true),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      const Divider(height: 24),
      ResponsiveColumns(
        enabled: true,
        first: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final f in _repo.fields(r.kind))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${f.label}: ${f.relation != null ? (_relationName(r.value(f.key)).isEmpty ? '미연결 또는 접근 불가' : _relationName(r.value(f.key))) : f.options[r.value(f.key)] ?? (r.value(f.key).isEmpty ? '미입력' : r.value(f.key))}',
                ),
              ),
            const Divider(height: 24),
          ],
        ),
        second: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('변경 정보', style: Theme.of(context).textTheme.titleMedium),
            Text(
              '생성: ${_actorName(r.createdBy)} · 수정: ${_actorName(r.updatedBy)}',
            ),
            Text('마지막 변경: ${_timeLabel(r.updatedAt)}'),
            if (r.kind.versioned) ...[
              Text('버전 ${r.revision} · ${_statusLabel(r.status)}'),
              Text(
                '적용: ${_actorName(r.appliedBy)} · ${_timeLabel(r.appliedAt, empty: '미적용')}',
              ),
            ],
            if (r.kind == AdminKind.scope) ...[
              if (_repo.live && r.value('revocationReason').isNotEmpty)
                Text('회수 사유: ${r.value('revocationReason')}'),
              Text(
                '부여: ${_actorName(r.value('grantedBy'))} · ${_timeLabel(DateTime.tryParse(r.value('grantedAt')))}',
              ),
              Text(
                '회수: ${_actorName(r.value('revokedBy'))} · ${_timeLabel(DateTime.tryParse(r.value('revokedAt')), empty: '회수되지 않음')}',
              ),
            ],
            ExpansionTile(
              title: const Text('기술 식별자'),
              children: [
                SelectableText('대상 ID: ${r.id}\n버전 묶음 ID: ${r.lineage}'),
              ],
            ),
            if (r.value('sourceUrl').isNotEmpty)
              ExternalLinkButton(url: r.value('sourceUrl'), label: '원문 열기'),
          ],
        ),
      ),
    ],
  );
  String _actorName(String id) {
    if (id.isEmpty) return '기록 없음';
    if (id == _actor) return '나';
    final name = _relationName(id);
    return name.isEmpty ? '관리자' : name;
  }

  String _timeLabel(DateTime? value, {String empty = '기록 없음'}) {
    if (value == null) return empty;
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}.${two(local.month)}.${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  String _routeFor(AdminKind kind) => switch (kind) {
    AdminKind.institution || AdminKind.department => '/admin/schools',
    AdminKind.curriculum ||
    AdminKind.course ||
    AdminKind.curriculumCourse => '/admin/curricula',
    AdminKind.ruleSet || AdminKind.rule => '/admin/rules',
    AdminKind.document => '/admin/documents',
    AdminKind.account || AdminKind.scope => '/admin/accounts',
  };

  String _actionLabel(String action) => switch (action) {
    'role_changed' => '역할 변경',
    'account_status_changed' => '계정 상태 변경',
    'access_changed' => '역할·계정 상태 변경',
    'scope_granted' => '관리 범위 부여',
    'scope_revoked' => '관리 범위 회수',
    'institution_created' => '학교 등록',
    'super_admin_bootstrapped' => '최초 슈퍼관리자 생성',
    'operator_credentials_rotated' => '운영자 계정 정보 갱신',
    'create' => '등록',
    'update' => '수정',
    'save' => '저장',
    'delete' => '삭제',
    'apply' => '초안 적용',
    'new_version' => '새 버전 작성',
    'revoke' => '범위 회수',
    _ => '관리 작업',
  };

  Iterable<AdminAuditEntry> get _schoolHistory => _repo.history.reversed.where(
    (entry) =>
        entry.institutionId == _schoolId &&
        (_role == AppRole.superAdmin ||
            entry.actorId == _actor ||
            _find(entry.targetId) != null &&
                _repo.canRead(_actor, _find(entry.targetId)!)),
  );

  Widget _overview() {
    final drafts = _repo.records
        .where(
          (r) =>
              r.kind.versioned &&
              r.status == 'draft' &&
              r.value('ruleSetId').isEmpty &&
              _repo.school(r) == _schoolId &&
              _repo.canRead(_actor, r),
        )
        .toList();
    final recent = _schoolHistory.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('관리 가능한 학교 ${_schools.length}개'),
        if (_schoolId.isEmpty) ...[
          const SizedBox(height: 12),
          const Text('관리 가능한 학교가 없습니다. 학교 등록 또는 범위 부여가 필요합니다.'),
          if (_role == AppRole.superAdmin)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _busy ? null : () => _edit(AdminKind.institution),
                child: const Text('학교 등록'),
              ),
            ),
        ] else ...[
          const SizedBox(height: 24),
          ResponsiveColumns(
            enabled: true,
            first: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '확인할 초안 ${drafts.length}개',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (drafts.isEmpty) const Text('확인할 초안이 없습니다. 필요한 자료부터 등록하세요.'),
                for (final r in drafts.take(5))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(r.name),
                    subtitle: Text('${r.kind.label} · v${r.revision} · 초안'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy
                        ? null
                        : () =>
                              widget.onNavigate('${_routeFor(r.kind)}/${r.id}'),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _navigate('/admin/rules'),
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('졸업요건 확인'),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _navigate('/admin/documents'),
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('공식 문서 확인'),
                  ),
                ),
                const Divider(height: 32),
              ],
            ),
            second: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('자료 등록', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    for (final kind in [
                      AdminKind.department,
                      AdminKind.curriculum,
                      AdminKind.course,
                      AdminKind.document,
                    ])
                      if (_canCreate(kind))
                        FilledButton.tonalIcon(
                          onPressed: _busy ? null : () => _edit(kind),
                          icon: const Icon(Icons.add, size: 18),
                          label: Text('${kind.label} 등록'),
                        ),
                    if (_role == AppRole.superAdmin)
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _navigate('/admin/accounts'),
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        label: const Text('관리자 범위 관리'),
                      ),
                  ],
                ),
                const Divider(height: 32),
                Text('최근 변경', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (recent.isEmpty) const Text('현재 학교의 변경 이력이 없습니다.'),
                for (final entry in recent)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${entry.kind.label} · ${_actionLabel(entry.action)} · ${entry.result == 'success' ? '완료' : '실패'}',
                    ),
                    subtitle: Text(
                      _find(entry.targetId) != null &&
                              _repo.canRead(_actor, _find(entry.targetId)!)
                          ? _find(entry.targetId)!.name
                          : '삭제되었거나 볼 수 없는 항목',
                    ),
                    onTap: () => _navigate('/admin/history'),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _navigate('/admin/history'),
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('관리 이력 보기'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _history() {
    final entries = _repo.history.reversed
        .where(
          (entry) =>
              _role == AppRole.superAdmin ||
              entry.institutionId == _schoolId &&
                  (entry.actorId == _actor ||
                      _find(entry.targetId) != null &&
                          _repo.canRead(_actor, _find(entry.targetId)!)),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('관리자 변경 메타데이터 · 학생 개인 기록 원문 없음'),
        if (entries.isEmpty) const Text('관리 이력이 없습니다. 등록·수정 후 확인하세요.'),
        ResponsivePanels(
          children: [
            for (final entry in entries)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${entry.kind.label} · ${_actionLabel(entry.action)} · ${entry.result == 'success' ? '완료' : '실패'}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${_timeLabel(entry.at)} · ${_actorName(entry.actorId)}',
                      ),
                      Text(
                        '학교: ${_relationName(entry.institutionId).isEmpty ? '학교 공통 또는 접근 불가' : _relationName(entry.institutionId)}',
                      ),
                      Text(
                        '대상: ${_relationName(entry.targetId).isEmpty ? '삭제되었거나 볼 수 없는 항목' : _relationName(entry.targetId)}',
                      ),
                      ExpansionTile(
                        title: const Text('기술 식별자'),
                        children: [
                          SelectableText(
                            '요청 ID: ${entry.requestId}\n대상 ID: ${entry.targetId}',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_schools.any((r) => r.id == _schoolId)) {
      _schoolId = _schools.firstOrNull?.id ?? '';
    }
    final known =
        AdminWorkspace.menus.containsKey(_section) &&
        widget.path.split('/').length <= 4;
    final detail = _detailId == null ? null : _find(_detailId!);
    // A directly opened detail owns the school context. Never label a record
    // with the first accessible school merely because the route was restored.
    if (detail != null && _repo.canRead(_actor, detail)) {
      final school = _repo.school(detail);
      if (_schools.any((r) => r.id == school)) _schoolId = school;
    }
    final sectionKinds = <String, List<AdminKind>>{
      '/admin/schools': [AdminKind.institution, AdminKind.department],
      '/admin/curricula': [
        AdminKind.curriculum,
        AdminKind.course,
        AdminKind.curriculumCourse,
      ],
      '/admin/rules': [AdminKind.ruleSet, AdminKind.rule],
      '/admin/documents': [AdminKind.document],
      '/admin/accounts': [AdminKind.account, AdminKind.scope],
    };
    final allowed =
        known &&
        widget.role != AppRole.user &&
        _repo.active(_actor) &&
        _role != AppRole.user &&
        (!{'/admin/accounts', '/admin/applications'}.contains(_section) ||
            _role == AppRole.superAdmin) &&
        (_detailId == null ||
            detail != null &&
                sectionKinds[_section]?.contains(detail.kind) == true &&
                _repo.canRead(_actor, detail));
    return AdminShell(
      sidebarVisible: widget.sidebarVisible,
      menus: {
        for (final entry in AdminWorkspace.menus.entries)
          if (!{'/admin/accounts', '/admin/applications'}.contains(entry.key) ||
              _role == AppRole.superAdmin)
            entry.key: entry.value,
      },
      section: _section,
      busy: _busy,
      onNavigate: _navigate,
      onSignedOut: _signOut,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactHeader =
              constraints.maxWidth < 760 ||
              MediaQuery.textScalerOf(context).scale(14) > 18;
          final title = allowed
              ? AdminWorkspace.menus[_section]!
              : '접근할 수 없습니다.';
          return ContentScrollView(
            child: Padding(
              padding: EdgeInsets.all(compactHeader ? 16 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (compactHeader)
                    PageHeader(title: title)
                  else ...[
                    Text('${_role.label} · 관리자 작업 공간'),
                    const SizedBox(height: 12),
                  ],
                  if (_schools.isNotEmpty &&
                      allowed &&
                      _section != '/admin/applications')
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: AnchoredSelectField<String>(
                          externalLabel: !compactHeader,
                          key: const ValueKey('admin-school-selector'),
                          searchable: true,
                          searchLabel: '학교 이름 검색',
                          value: _schoolId,
                          label: '현재 학교',
                          options: [
                            for (final school in _schools)
                              SelectOption(school.id, school.name),
                          ],
                          onChanged: (v) async {
                            if (v == _schoolId || !await _allowLeave()) return;
                            setState(() {
                              _schoolId = v;
                              _editorKeys.clear();
                              _error = null;
                              _queries.clear();
                              _statuses.clear();
                            });
                            // The old detail cannot remain under the new school.
                            if (_detailId != null) widget.onNavigate(_section);
                          },
                        ),
                      ),
                    ),
                  if (widget.role != AppRole.user)
                    Text(
                      _role == AppRole.superAdmin
                          ? '관리 범위: 전체 학교'
                          : '관리 범위: ${_repo.records.where((r) => r.kind == AdminKind.scope && r.status == 'active' && r.value('userId') == _actor && r.value('institutionId') == _schoolId).map(_scopeSummary).toSet().join(', ')}',
                    ),
                  const SizedBox(height: 12),
                  if (_repo.live) ...[
                    const Text(
                      '서버에 저장되는 관리 데이터 · 문서 적용은 RAG 승인이나 졸업 판정이 아닙니다.',
                    ),
                    if (_repo.warning != null) Text(_repo.warning!),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _busy || _loading ? null : _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('다시 읽기'),
                      ),
                    ),
                  ],
                  if (!compactHeader) PageHeader(title: title),
                  if (_loading)
                    const LinearProgressIndicator()
                  else if (_loadError != null) ...[
                    Text(_loadError!),
                    TextButton(onPressed: _load, child: const Text('다시 읽기')),
                  ] else if (!allowed) ...[
                    const Text('현재 계정 상태·역할·관리 범위로 이 화면에 접근할 수 없습니다.'),
                    TextButton(
                      onPressed: () => _navigate('/admin/overview'),
                      child: const Text('관리 현황으로'),
                    ),
                  ] else if (_detailId != null)
                    _detail(detail!)
                  else ...[
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (_section == '/admin/overview') _overview(),
                    for (final kind
                        in sectionKinds[_section] ?? <AdminKind>[]) ...[
                      _records(kind),
                      const SizedBox(height: 24),
                    ],
                    if (_section == '/admin/history') _history(),
                    if (_section == '/admin/applications')
                      SchoolAdminApplicationInbox(
                        schools: [
                          for (final school in _schools)
                            SelectOption(school.id, school.name),
                        ],
                      ),
                    if (_section == '/admin/settings')
                      const Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: 548,
                          child: AppearanceSettingsSection(),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
