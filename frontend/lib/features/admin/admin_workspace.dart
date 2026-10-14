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
import 'admin_fields.dart';

class AdminWorkspace extends StatefulWidget {
  const AdminWorkspace({
    super.key,
    required this.role,
    required this.path,
    required this.onNavigate,
    required this.onSignedOut,
    this.repository,
  });
  final AppRole role;
  final String path;
  final ValueChanged<String> onNavigate;
  final VoidCallback onSignedOut;
  final AdminRepository? repository;
  static const menus = <String, String>{
    '/admin/overview': '관리 현황',
    '/admin/schools': '학교·학과',
    '/admin/curricula': '교육과정·과목',
    '/admin/rules': '졸업요건',
    '/admin/documents': '공식 문서',
    '/admin/history': '관리 이력',
    '/admin/accounts': '관리자 관리',
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
  String get _actor =>
      widget.role == AppRole.superAdmin ? 'super-admin' : 'school-admin';
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await _repo.load();
    } catch (_) {
      _loadError = '관리 데이터를 읽지 못했습니다.';
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
    final references = _repo.records.where(
      (other) =>
          other.id != r.id &&
          [
            'institutionId',
            'departmentId',
            'curriculumId',
            'courseId',
            'ruleId',
          ].any((key) => other.value(key) == r.id),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${r.name} · $action'),
        content: Text(
          action == '초안 적용'
              ? 'v${r.version}의 내용·관리 범위·근거를 검토했습니까? 목업 상태만 적용하며 실제 학교 승인이나 졸업 판정은 아닙니다.'
              : '대상과 연결 영향을 확인하세요. 참조가 남은 삭제는 차단하고 적용 이력은 보존합니다.\n연결된 항목 ${references.length}개: ${references.where((other) => _repo.canRead(_actor, other)).map((other) => other.name).join(', ')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
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
      if (mounted)
        setState(
          () => _error = e is StateError
              ? '${e.message}'
              : '처리하지 못했습니다. 다시 시도하세요.',
        );
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
    ].contains(kind))
      return false;
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
                    AdminKind.rule,
                    AdminKind.document,
                    AdminKind.curriculumCourse,
                  ].contains(kind)),
    );
  }

  Widget _records(AdminKind kind) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 16),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(kind.label, style: Theme.of(context).textTheme.titleMedium),
          if (_canCreate(kind))
            FilledButton(
              onPressed: _busy ? null : () => _edit(kind),
              child: Text('${kind.label} 등록'),
            ),
        ],
      ),
      if (_rows(kind).isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            '${kind.label} 데이터가 없습니다.${_canCreate(kind) ? ' 등록 버튼으로 시작하세요.' : '권한과 관리 범위를 확인하세요.'}',
          ),
        ),
      for (final r in _rows(kind))
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(r.name, style: Theme.of(context).textTheme.titleMedium),
                if (kind.versioned)
                  Text(
                    'v${r.version} · ${r.status == 'applied' ? '목업 적용' : '초안'}',
                  ),
                if (kind == AdminKind.scope)
                  Text(
                    '${r.value('scopeType')} · ${r.status == 'active' ? '활성' : '회수됨'}',
                  ),
                if (kind == AdminKind.account)
                  Text(
                    '${roleFromRecord(r).label} · ${r.value('accountStatus') == 'active' ? '활성' : '정지'}',
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => widget.onNavigate('$_section/${r.id}'),
                      child: const Text('상세'),
                    ),
                    if (_repo.canWrite(_actor, r) &&
                        r.status != 'applied' &&
                        r.status != 'revoked' &&
                        r.id != _actor)
                      TextButton(
                        onPressed: _busy ? null : () => _edit(kind, r),
                        child: const Text('수정'),
                      ),
                    if (_repo.canWrite(_actor, r) &&
                        kind.versioned &&
                        r.status == 'draft')
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _confirmAction(
                                r,
                                '초안 적용',
                                () => _repo.apply(_actor, r.id),
                              ),
                        child: const Text('검토·적용'),
                      ),
                    if (_repo.canWrite(_actor, r) &&
                        kind.versioned &&
                        r.status == 'applied')
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _confirmAction(r, '새 버전 초안', () async {
                                await _repo.newVersion(_actor, r.id);
                              }),
                        child: const Text('새 버전 초안'),
                      ),
                    if (_repo.canWrite(_actor, r) &&
                        kind == AdminKind.scope &&
                        r.status == 'active')
                      TextButton(
                        onPressed: _busy ? null : () => _edit(kind, r, true),
                        child: const Text('범위 회수'),
                      ),
                    if (_repo.canWrite(_actor, r) &&
                        ![AdminKind.scope, AdminKind.account].contains(kind) &&
                        r.status != 'applied')
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _confirmAction(
                                r,
                                '삭제',
                                () => _repo.remove(_actor, r.id),
                              ),
                        child: const Text('삭제'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );
  Widget _detail(AdminRecord r) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextButton(
        onPressed: () => widget.onNavigate(_section),
        child: const Text('목록으로'),
      ),
      Text(r.name, style: Theme.of(context).textTheme.titleLarge),
      for (final f in adminFields(r.kind))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${f.label}: ${f.relation != null ? _find(r.value(f.key))?.name ?? '미연결' : f.options[r.value(f.key)] ?? r.value(f.key)}',
          ),
        ),
      Text(
        '생성: ${r.createdBy} · 수정: ${r.updatedBy} · ${r.updatedAt?.toIso8601String() ?? '초기 합성 자료'}',
      ),
      if (r.kind.versioned)
        Text(
          '버전 ${r.version} · ${r.status} · 적용: ${r.appliedBy} · ${r.appliedAt?.toIso8601String() ?? '미적용'}',
        ),
      if (r.kind == AdminKind.scope)
        Text(
          '부여: ${r.value('grantedBy')} ${r.value('grantedAt')}\n회수: ${r.value('revokedBy')} ${r.value('revokedAt')}',
        ),
      if (r.value('sourceUrl').isNotEmpty)
        ExternalLinkButton(url: r.value('sourceUrl'), label: '원문 열기'),
    ],
  );
  Widget _history() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('관리자 변경 메타데이터 · 학생 개인 기록 원문 없음'),
      if (_repo.history.isEmpty) const Text('관리 이력이 없습니다. 등록·수정 후 확인하세요.'),
      for (final entry in _repo.history.reversed)
        if (_role == AppRole.superAdmin ||
            entry.institutionId == _schoolId &&
                (entry.actorId == _actor ||
                    _find(entry.targetId) != null &&
                        _repo.canRead(_actor, _find(entry.targetId)!)))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '${entry.at.toIso8601String()}\n${entry.actorId} · ${entry.kind.label} · ${entry.action} · ${entry.result}\n${entry.requestId} · 대상 ${entry.targetId}',
              ),
            ),
          ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    if (!_schools.any((r) => r.id == _schoolId))
      _schoolId = _schools.firstOrNull?.id ?? '';
    final known =
        AdminWorkspace.menus.containsKey(_section) &&
        widget.path.split('/').length <= 4;
    final detail = _detailId == null ? null : _find(_detailId!);
    final sectionKinds = <String, List<AdminKind>>{
      '/admin/schools': [AdminKind.institution, AdminKind.department],
      '/admin/curricula': [
        AdminKind.curriculum,
        AdminKind.course,
        AdminKind.curriculumCourse,
      ],
      '/admin/rules': [AdminKind.rule],
      '/admin/documents': [AdminKind.document],
      '/admin/accounts': [AdminKind.account, AdminKind.scope],
    };
    final allowed =
        known &&
        widget.role != AppRole.user &&
        _repo.active(_actor) &&
        _role != AppRole.user &&
        (_section != '/admin/accounts' || _role == AppRole.superAdmin) &&
        (_detailId == null ||
            detail != null &&
                sectionKinds[_section]?.contains(detail.kind) == true &&
                _repo.canRead(_actor, detail));
    return Scaffold(
      body: SafeArea(
        child: ContentScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${_role.label} · 관리자 작업 공간'),
                const Text('개발용 목업 · 실제 권한 및 서버 저장 없음'),
                const SizedBox(height: 12),
                if (_schools.isNotEmpty && allowed)
                  AnchoredSelectField<String>(
                    value: _schoolId,
                    label: '현재 학교',
                    options: [
                      for (final school in _schools)
                        SelectOption(school.id, school.name),
                    ],
                    onChanged: (v) => setState(() => _schoolId = v),
                  ),
                if (widget.role != AppRole.user)
                  Text(
                    _role == AppRole.superAdmin
                        ? '관리 범위: 전체 학교'
                        : '관리 범위: ${_repo.records.where((r) => r.kind == AdminKind.scope && r.status == 'active' && r.value('userId') == _actor && r.value('institutionId') == _schoolId).map((r) => '${r.name} (${r.value('scopeType')})').join(', ')}',
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in AdminWorkspace.menus.entries)
                      if (entry.key != '/admin/accounts' ||
                          _role == AppRole.superAdmin)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => widget.onNavigate(entry.key),
                          child: Text(entry.value),
                        ),
                    TextButton(
                      onPressed: _busy ? null : widget.onSignedOut,
                      child: const Text('로그아웃'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                PageHeader(
                  title: allowed
                      ? AdminWorkspace.menus[_section]!
                      : '접근할 수 없습니다.',
                ),
                if (_loading)
                  const LinearProgressIndicator()
                else if (_loadError != null) ...[
                  Text(_loadError!),
                  TextButton(onPressed: _load, child: const Text('다시 읽기')),
                ] else if (!allowed) ...[
                  const Text('현재 계정 상태·역할·관리 범위로 이 화면에 접근할 수 없습니다.'),
                  TextButton(
                    onPressed: () => widget.onNavigate('/admin/overview'),
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
                  if (_section == '/admin/overview') ...[
                    Text('관리 가능한 학교 ${_schools.length}개'),
                    if (_schoolId.isEmpty)
                      const Text('관리 가능한 학교가 없습니다. 슈퍼관리자의 범위 부여가 필요합니다.'),
                    for (final r in _repo.records.where(
                      (r) =>
                          r.kind == AdminKind.scope &&
                          r.value('userId') == _actor,
                    ))
                      Text('${r.name} · ${r.status}'),
                  ],
                  if (_section == '/admin/schools') ...[
                    _records(AdminKind.institution),
                    _records(AdminKind.department),
                  ],
                  if (_section == '/admin/curricula') ...[
                    _records(AdminKind.curriculum),
                    _records(AdminKind.course),
                    _records(AdminKind.curriculumCourse),
                  ],
                  if (_section == '/admin/rules') _records(AdminKind.rule),
                  if (_section == '/admin/documents')
                    _records(AdminKind.document),
                  if (_section == '/admin/accounts') ...[
                    _records(AdminKind.account),
                    _records(AdminKind.scope),
                  ],
                  if (_section == '/admin/history') _history(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
