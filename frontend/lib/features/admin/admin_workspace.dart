import '../../shared/widgets/responsive_columns.dart';
import '../../shared/app_style.dart';
import '../../shared/credits_format.dart';
import '../settings/account_settings_section.dart';
import '../settings/appearance_settings_section.dart';

import 'package:flutter/material.dart';

import '../auth/app_role.dart';
import '../../shared/widgets/feature_actions.dart';
import '../../shared/widgets/feature_line.dart';
import '../../shared/widgets/feature_page.dart';
import '../../shared/widgets/surface_card.dart';
import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/field_label.dart';
import 'admin_models.dart';
import 'admin_repository.dart';
import 'admin_editor.dart';
import 'admin_school_chrome.dart';
import 'admin_shell.dart';
import 'graduation_certification_page.dart';
import 'graduation_credit_grid_page.dart';
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
    this.schoolChrome,
    this.phoneChrome = false,
    this.initialSchoolId,
    this.onEnterStudentPreview,
  });
  final AppRole role;
  final String path;
  final ValueChanged<String> onNavigate;
  final VoidCallback onSignedOut;
  final AdminRepository? repository;
  final bool sidebarVisible;
  final String? actorId;
  final Future<void> Function()? beforeSignedOut;
  final AdminSchoolChrome? schoolChrome;
  final bool phoneChrome;
  /// Preferred school after leaving student guest preview.
  final String? initialSchoolId;
  final VoidCallback? onEnterStudentPreview;
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
  static const menuDescriptions = <String, String>{
    '/admin/overview': '학교 자료와 최근 작업을 확인합니다.',
    '/admin/schools': '학교와 학과를 등록하고 관리합니다.',
    '/admin/curricula': '교육과정과 과목을 등록하고 관리합니다.',
    '/admin/rules': '졸업 요건과 실행 조건을 관리합니다.',
    '/admin/documents': '학교 문서를 등록하고 적용합니다.',
    '/admin/history': '관리 작업 이력을 확인합니다.',
    '/admin/accounts': '관리자 계정과 권한을 관리합니다.',
    '/admin/applications': '학교관리자 가입 신청을 검토합니다.',
    '/admin/settings': '화면과 계정 보안을 관리합니다.',
  };
  @override
  State<AdminWorkspace> createState() => _AdminWorkspaceState();
}

class _AdminWorkspaceState extends State<AdminWorkspace> {
  late final AdminRepository _repo;
  bool _loading = true;
  bool _refreshing = false;
  bool _hasLoaded = false;
  String? _loadError, _error;
  String _schoolId = '';
  bool _busy = false;
  final _editorKeys = <AdminKind, GlobalKey<AdminEditorState>>{};
  final _catalogScroll = <AdminKind, ScrollController>{};
  String? _scheduledDetailId;
  var _ruleView = 'line';
  final _creditGrid = GlobalKey<GraduationCreditGridPageState>();
  final _certification = GlobalKey<GraduationCertificationPageState>();
  Future<bool> _allowLeave() async {
    for (final key in _editorKeys.values) {
      if (key.currentState != null && !await key.currentState!.allowLeave()) {
        return false;
      }
    }
    if (_creditGrid.currentState != null &&
        !await _creditGrid.currentState!.allowLeave()) {
      return false;
    }
    if (_certification.currentState != null &&
        !await _certification.currentState!.allowLeave()) {
      return false;
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

  String _accountRole = '';
  String? _accountEditId;
  final _queries = <AdminKind, String>{};
  final _statuses = <AdminKind, String>{};
  final _historyQuery = TextEditingController();
  String _historyKind = '';
  String _historyAction = '';
  String get _actor =>
      widget.actorId ??
      (widget.role == AppRole.superAdmin ? 'super-admin' : 'school-admin');
  AppRole get _role =>
      widget.role == AppRole.user ? AppRole.user : _repo.role(_actor);
  bool get _isSuperAdmin =>
      widget.role == AppRole.superAdmin && _role == AppRole.superAdmin;
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
    for (final controller in _catalogScroll.values) {
      controller.dispose();
    }
    _historyQuery.dispose();
    widget.schoolChrome?.clear();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _signOut() async {
    if (_busy) return;
    if (!await _allowLeave() || !mounted || _busy) return;
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
    final refresh = _hasLoaded;
    setState(() {
      if (refresh) {
        _refreshing = true;
      } else {
        _loading = true;
      }
      _loadError = null;
    });
    try {
      await _repo.load();
      _hasLoaded = true;
    } catch (error) {
      _loadError = error is StateError
          ? error.message.toString()
          : '관리 데이터를 읽지 못했습니다.';
    }
    if (mounted) {
      setState(() {
        _loading = false;
        _refreshing = false;
      });
      _scheduleDetailConsume();
    }
  }

  @override
  void didUpdateWidget(covariant AdminWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _scheduleDetailConsume();
  }

  void _scheduleDetailConsume() {
    if (_loading || _loadError != null) return;
    final id = _detailId;
    if (id == null) {
      _scheduledDetailId = null;
      return;
    }
    if (id == _scheduledDetailId) return;
    final record = _find(id);
    if (record == null || !_repo.canRead(_actor, record)) return;
    _scheduledDetailId = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _detailId != id) return;
      _edit(record.kind, record);
    });
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
            kind == AdminKind.institution ||
            _repo.school(r) == _schoolId),
  );
  Future<void> _edit(
    AdminKind kind, [
    AdminRecord? record,
    bool revoke = false,
  ]) async {
    if (revoke) {
      final result = await showInputDialog<String>(
        context: context,
        builder: (_) => AdminEditor(
          repository: _repo,
          actorId: _actor,
          kind: kind,
          schoolId: _schoolId,
          record: record,
          revoke: true,
        ),
      );
      if (result == 'revoke' && record != null) {
        await _edit(kind, record, true);
        return;
      }
      if (record != null && _find(record.id)?.status == 'revoked') {
        _editorKeys[kind]?.currentState?.abandonToCreate();
      }
      return;
    }
    if (kind == AdminKind.account && record != null) {
      final editor = _editorKeys[AdminKind.account]?.currentState;
      if (editor != null && editor.activeRecord?.id != record.id) {
        if (!await editor.allowLeave()) return;
        if (!mounted) return;
        editor.showRecord(record);
      }
      if (!mounted) return;
      setState(() => _accountEditId = record.id);
      return;
    }
    final path = _pathFor(kind);
    if (_section != path || _detailId != null) await _navigate(path);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final editor = _editorKeys[kind]?.currentState;
      if (record != null) {
        await editor?.loadRecord(record);
      }
      if (!mounted) return;
      final target = _editorKeys[kind]?.currentContext;
      if (target != null && target.mounted) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 200),
        );
      }
    });
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

  String _accountScopeText(AdminRecord account) {
    if (account.value('role') == 'super_admin') return '전체 학교';
    final scopes = _repo.records.where(
      (r) =>
          r.kind == AdminKind.scope &&
          r.status == 'active' &&
          r.value('userId') == account.id &&
          _repo.canRead(_actor, r),
    );
    final labels = scopes
        .map(
          (r) => [
            _relationName(r.value('institutionId')),
            _scopeSummary(r),
          ].where((s) => s.isNotEmpty).join(' · '),
        )
        .toSet();
    return labels.isEmpty ? '부여된 관리 범위 없음' : labels.join(' / ');
  }

  String _recordContext(AdminRecord r) {
    final parts = [
      if (r.kind == AdminKind.account) '관리 범위: ${_accountScopeText(r)}',
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
      if (r.value('credits').isNotEmpty) formatCreditsLabel(r.value('credits')),
      if (r.value('code').isNotEmpty) '코드 ${r.value('code')}',
      if (r.kind == AdminKind.scope)
        switch (r.value('scopeType')) {
          'institution' => '학교 전체',
          'department' => '학과 범위',
          'curriculum' => '교육과정 범위',
          _ => '범위 유형 확인 필요',
        },
    ].where((s) => s.isNotEmpty);
    final seen = <String>{};
    return parts.where(seen.add).join(' · ');
  }
  Iterable<AdminRecord> _filteredRows(AdminKind kind) => _rows(kind).where((r) {
    if (kind == AdminKind.institution) return true;
    final query = (_queries[kind] ?? '').trim().toLowerCase();
    return '${r.name} ${r.kind == AdminKind.account ? '${r.value('email')} ${roleFromRecord(r).label}' : ''} ${_recordContext(r)}'
            .toLowerCase()
            .contains(query) &&
        (kind != AdminKind.account ||
            _accountRole.isEmpty ||
            r.value('role') == _accountRole) &&
        ((_statuses[kind] ?? '').isEmpty || _status(r) == _statuses[kind]);
  });

  Widget _records(AdminKind kind) {
    if (kind == AdminKind.account) {
      final editing = _accountEditId == null ? null : _find(_accountEditId!);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _recordList(kind),
          if (editing != null) ...[
            SizedBox(height: FeatureLine.slotGap(context)),
            AdminEditor(
              key: _editorKeys.putIfAbsent(
                AdminKind.account,
                GlobalKey<AdminEditorState>.new,
              ),
              repository: _repo,
              actorId: _actor,
              kind: kind,
              schoolId: _schoolId,
              record: editing,
              inline: true,
              onClosed: () => setState(() => _accountEditId = null),
            ),
          ],
        ],
      );
    }
    if (!_canCreate(kind)) return _recordList(kind);
    return SurfaceCard(
      key: ValueKey('admin-frame-${kind.name}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FeatureLine.section(text: kind.label),
          KeyedSubtree(
            key: ValueKey('admin-registration-${kind.name}-$_schoolId'),
            child: AdminEditor(
              key: _editorKeys.putIfAbsent(
                kind,
                () => GlobalKey<AdminEditorState>(),
              ),
              repository: _repo,
              actorId: _actor,
              kind: kind,
              schoolId: _schoolId,
              inline: true,
              list: _recordList(kind, framed: false),
              onRevokeRequested: () {
                final current = _editorKeys[kind]?.currentState?.activeRecord;
                if (current != null) _edit(kind, current, true);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordList(AdminKind kind, {bool framed = true}) {
    final content = Padding(
      key: ValueKey('admin-section-${kind.name}'),
      padding: EdgeInsets.all(framed ? 20 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FeatureLine.section(
            text: framed ? '${kind.label} 목록' : '목록',
            padTop: !framed,
            padBottom: false,
            trailing: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${_rows(kind).length}개'),
                if (_repo.live)
                  FeatureLine.reload(
                    onPressed: _busy || _loading || _refreshing ? null : _load,
                  ),
              ],
            ),
          ),
          if (_refreshing) const LinearProgressIndicator(),
          SizedBox(height: FeatureLine.slotGap(context)),
          if (kind == AdminKind.account) ...[
            AnchoredSelectField<String>(
              key: const ValueKey('admin-account-role'),
              externalLabel: true,
              value: _accountRole,
              label: '사용자 역할',
              options: const [
                SelectOption('', '전체 역할'),
                SelectOption('super_admin', '슈퍼관리자'),
                SelectOption('school_admin', '학교관리자'),
                SelectOption('user', '학생'),
              ],
              onChanged: (value) => setState(() => _accountRole = value),
            ),
            const SizedBox(height: 8),
          ],
          if (kind != AdminKind.institution && _rows(kind).isNotEmpty) ...[
            FieldLabel(
              label: kind == AdminKind.account
                  ? '사용자 이름·이메일·학교 검색'
                  : '${kind.label} 이름·소속·코드 검색',
              child: TextFormField(
                key: ValueKey('admin-search-$_schoolId-${kind.name}'),
                initialValue: _queries[kind] ?? '',
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _queries[kind] = value),
              ),
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
              const FeatureLine.one(
                text: '검색·필터에 맞는 항목이 없습니다. 검색어와 상태를 바꿔보세요.',
              ),
          ],
          if (_rows(kind).isEmpty)
            ConstrainedBox(
              key: ValueKey('admin-empty-${kind.name}'),
              constraints: const BoxConstraints(minHeight: 180),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        Icons.list_alt_outlined,
                        size: 32,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '등록된 ${kind.label} 항목이 없습니다',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _canCreate(kind)
                          ? '등록 폼에서 추가하면 이 목록에 표시됩니다.'
                          : '조회할 수 있는 항목이 없습니다. 권한과 관리 범위를 확인하세요.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_filteredRows(kind).isNotEmpty)
            _cappedCatalogList(kind),
        ],
      ),
    );
    if (!framed) return content;
    return SurfaceCard(
      key: ValueKey('admin-frame-${kind.name}'),
      child: content,
    );
  }

  static const _catalogRowHeight = 64.0;
  static const _catalogVisibleRows = 3;
  static const _catalogActionHeight = 36.0;

  double get _catalogExtent {
    final scaled = MediaQuery.textScalerOf(context).scale(_catalogRowHeight);
    return scaled < _catalogRowHeight ? _catalogRowHeight : scaled;
  }

  ButtonStyle _catalogActionStyle({bool danger = false}) {
    final base = danger
        ? _dangerStyle()
        : OutlinedButton.styleFrom();
    return base.copyWith(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const WidgetStatePropertyAll(Size(0, _catalogActionHeight)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      ),
    );
  }

  bool _canEdit(AdminRecord r) =>
      _repo.canWrite(_actor, r) && r.id != _actor && r.status != 'revoked';

  bool _canDelete(AdminRecord r) =>
      _repo.canWrite(_actor, r) &&
      ![AdminKind.scope, AdminKind.account].contains(r.kind) &&
      r.status != 'applied';

  String _catalogSubtitle(AdminRecord r) {
    final parts = [
      _recordContext(r),
      if (r.kind.versioned) 'v${r.revision} · ${_statusLabel(r.status)}',
      if (r.kind == AdminKind.account)
        '${roleFromRecord(r).label} · ${_statusLabel(r.value('accountStatus'))}',
      if (r.kind == AdminKind.scope) _statusLabel(r.status),
    ].where((s) => s.isNotEmpty);
    return parts.join(' · ');
  }

  Widget _cappedCatalogList(AdminKind kind) {
    final rows = _filteredRows(kind).toList();
    final visible = rows.length < _catalogVisibleRows
        ? rows.length
        : _catalogVisibleRows;
    final overflowing = rows.length > _catalogVisibleRows;
    final controller = _catalogScroll.putIfAbsent(kind, ScrollController.new);
    final extent = _catalogExtent;
    return SizedBox(
      key: ValueKey('admin-catalog-${kind.name}'),
      height: extent * visible,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: Scrollbar(
          controller: controller,
          thumbVisibility: overflowing,
          interactive: true,
          child: ListView.builder(
            controller: controller,
            padding: overflowing
                ? const EdgeInsetsDirectional.only(end: 16)
                : EdgeInsets.zero,
            primary: false,
            itemCount: rows.length,
            itemExtent: extent,
            itemBuilder: (context, index) => _catalogRow(rows[index]),
          ),
        ),
      ),
    );
  }

  Widget _catalogRow(AdminRecord r) {
    final subtitle = _catalogSubtitle(r);
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: ValueKey('admin-row-${r.id}'),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    r.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_canEdit(r))
                  OutlinedButton(
                    style: _catalogActionStyle(),
                    onPressed: _busy ? null : () => _edit(r.kind, r),
                    child: const Text('수정'),
                  ),
                if (_canDelete(r))
                  FilledButton(
                    style: _catalogActionStyle(danger: true),
                    onPressed: _busy
                        ? null
                        : () => _confirmAction(r, '삭제', () async {
                            await _repo.remove(_actor, r.id);
                          }),
                    child: const Text('삭제'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  ButtonStyle _dangerStyle() => destructiveButtonStyle(context);

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

  static const _overviewActionMin = Size(148, 40);

  ButtonStyle get _overviewOutlinedStyle => OutlinedButton.styleFrom(
    minimumSize: _overviewActionMin,
  );

  ButtonStyle get _overviewFilledStyle => FilledButton.styleFrom(
    minimumSize: _overviewActionMin,
  );

  Widget _overview() {
    final recent = _schoolHistory.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_schoolId.isEmpty) ...[
          const FeatureLine.one(
            text: '관리 가능한 학교가 없습니다. 학교 등록 또는 범위 부여가 필요합니다.',
          ),
          if (_isSuperAdmin)
            FeatureActions(
              children: [
                FilledButton(
                  onPressed: _busy ? null : () => _edit(AdminKind.institution),
                  child: const Text('학교 등록'),
                ),
              ],
            ),
          if (_repo.live)
            FeatureLine.reload(
              onPressed: _busy || _loading || _refreshing ? null : _load,
            ),
        ] else ...[
          SurfaceCard(
            child: ResponsiveColumns(
              enabled: true,
              first: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FeatureLine.section(
                    text: '바로가기',
                    padTop: false,
                    padBottom: false,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        style: _overviewOutlinedStyle,
                        onPressed:
                            _busy ? null : () => _navigate('/admin/rules'),
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        label: const Text('졸업요건 확인'),
                      ),
                      OutlinedButton.icon(
                        style: _overviewOutlinedStyle,
                        onPressed: _busy
                            ? null
                            : () => _navigate('/admin/documents'),
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        label: const Text('공식 문서 확인'),
                      ),
                      if (_isSuperAdmin)
                        OutlinedButton.icon(
                          style: _overviewOutlinedStyle,
                          onPressed: _busy
                              ? null
                              : () => _navigate('/admin/accounts'),
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          label: const Text('관리자 범위 관리'),
                        ),
                      OutlinedButton.icon(
                        style: _overviewOutlinedStyle,
                        onPressed: _busy
                            ? null
                            : () => _navigate('/admin/history'),
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        label: const Text('관리 이력 보기'),
                      ),
                      if (widget.onEnterStudentPreview != null)
                        OutlinedButton.icon(
                          key: const ValueKey('admin-student-preview'),
                          style: _overviewOutlinedStyle,
                          onPressed: _busy
                              ? null
                              : widget.onEnterStudentPreview,
                          icon: const Icon(Icons.visibility_outlined, size: 18),
                          label: const Text('학생 화면 미리보기'),
                        ),
                    ],
                  ),
                ],
              ),
              second: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FeatureLine.section(
                    text: '자료 등록',
                    padTop: false,
                    padBottom: false,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final kind in [
                        AdminKind.department,
                        AdminKind.curriculum,
                        AdminKind.course,
                        AdminKind.document,
                      ])
                        if (_canCreate(kind))
                          FilledButton.icon(
                            style: _overviewFilledStyle,
                            onPressed: _busy ? null : () => _edit(kind),
                            icon: const Icon(Icons.add, size: 18),
                            label: Text('${kind.label} 등록'),
                          ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: FeatureLine.slotGap(context)),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FeatureLine.section(
                  text: '최근 변경',
                  padTop: false,
                  padBottom: false,
                  trailing: _repo.live
                      ? FeatureLine.reload(
                          onPressed:
                              _busy || _loading || _refreshing ? null : _load,
                        )
                      : null,
                ),
                const SizedBox(height: 8),
                if (recent.isEmpty)
                  const FeatureLine.one(text: '현재 학교의 변경 이력이 없습니다.'),
                for (final entry in recent)
                  InkWell(
                    onTap: () => _navigate('/admin/history'),
                    child: FeatureLine.two(
                      primary:
                          '${entry.kind.label} · ${_actionLabel(entry.action)} · ${entry.result == 'success' ? '완료' : '실패'}',
                      secondary:
                          _find(entry.targetId) != null &&
                              _repo.canRead(_actor, _find(entry.targetId)!)
                          ? _find(entry.targetId)!.name
                          : '삭제되었거나 볼 수 없는 항목',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  bool _historyInScope(AdminAuditEntry entry) {
    if (_role == AppRole.superAdmin) {
      return _schoolId.isEmpty || entry.institutionId == _schoolId;
    }
    return entry.institutionId == _schoolId &&
        (entry.actorId == _actor ||
            _find(entry.targetId) != null &&
                _repo.canRead(_actor, _find(entry.targetId)!));
  }

  Iterable<AdminAuditEntry> _filteredHistory(Iterable<AdminAuditEntry> scoped) {
    final query = _historyQuery.text.trim().toLowerCase();
    return scoped.where((entry) {
      if (_historyKind.isNotEmpty && entry.kind.name != _historyKind) {
        return false;
      }
      if (_historyAction.isNotEmpty && entry.action != _historyAction) {
        return false;
      }
      if (query.isEmpty) return true;
      final target = _relationName(entry.targetId);
      final actor = _actorName(entry.actorId);
      final action = _actionLabel(entry.action);
      final haystack =
          '${entry.kind.label} $target $actor $action ${entry.action}'
              .toLowerCase();
      return haystack.contains(query);
    });
  }

  Widget _history() {
    final allScoped =
        _repo.history.reversed.where(_historyInScope).toList();
    final entries = _filteredHistory(allScoped).toList();
    final kindOptions = {
      for (final entry in allScoped) entry.kind.name: entry.kind.label,
    };
    final actionOptions = {
      for (final entry in allScoped) entry.action: _actionLabel(entry.action),
    };
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FeatureLine.section(
            text: '관리 이력',
            padTop: false,
            padBottom: false,
            trailing: _repo.live
                ? FeatureLine.reload(
                    onPressed: _busy || _loading || _refreshing ? null : _load,
                  )
                : null,
          ),
          SizedBox(height: FeatureLine.slotGap(context)),
          TextFormField(
            key: const ValueKey('admin-history-search'),
            controller: _historyQuery,
            decoration: const InputDecoration(
              labelText: '대상·수행자·행동 검색',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          AnchoredSelectField<String>(
            key: const ValueKey('admin-history-kind'),
            externalLabel: true,
            value: _historyKind,
            label: '종류',
            options: [
              const SelectOption('', '전체 종류'),
              for (final entry in kindOptions.entries)
                SelectOption(entry.key, entry.value),
            ],
            onChanged: (value) => setState(() => _historyKind = value),
          ),
          const SizedBox(height: 8),
          AnchoredSelectField<String>(
            key: const ValueKey('admin-history-action'),
            externalLabel: true,
            value: _historyAction,
            label: '행동',
            options: [
              const SelectOption('', '전체 행동'),
              for (final entry in actionOptions.entries)
                SelectOption(entry.key, entry.value),
            ],
            onChanged: (value) => setState(() => _historyAction = value),
          ),
          if (allScoped.isEmpty)
            const FeatureLine.one(text: '관리 이력이 없습니다. 등록·수정 후 확인하세요.')
          else if (entries.isEmpty)
            const FeatureLine.one(text: '검색·필터에 맞는 이력이 없습니다.')
          else
            for (final entry in entries) ...[
              FeatureLine.two(
                primary:
                    '${entry.kind.label} · ${_actionLabel(entry.action)} · ${entry.result == 'success' ? '완료' : '실패'}',
                secondary:
                    '${_timeLabel(entry.at)} · ${_actorName(entry.actorId)} · ${_relationName(entry.targetId).isEmpty ? '삭제되었거나 볼 수 없는 항목' : _relationName(entry.targetId)}',
              ),
              Material(
                key: ObjectKey(entry),
                type: MaterialType.transparency,
                child: ExpansionTile(
                  title: const Text('기술 식별자'),
                  children: [
                    SelectableText(
                      '요청 ID: ${entry.requestId}\n대상 ID: ${entry.targetId}',
                    ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }

  Widget _ruleViewSwitcher() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final entry in [
        ('line', '한 줄 요건'),
        ('grid', '학점표'),
        ('cert', '인증 요건'),
      ])
        _ruleViewButton(entry.$1, entry.$2),
    ],
  );

  Widget _ruleViewButton(String id, String label) {
    final selected = _ruleView == id;
    final onPressed = () async {
      if (_ruleView == id) return;
      if (!await _allowLeave()) return;
      if (!mounted) return;
      setState(() => _ruleView = id);
    };
    final child = Text(label);
    final key = ValueKey('rule-view-$id');
    return selected
        ? FilledButton(key: key, onPressed: onPressed, child: child)
        : OutlinedButton(key: key, onPressed: onPressed, child: child);
  }

  Future<void> _changeSchool(String v) async {
    if (v == _schoolId || !await _allowLeave()) return;
    setState(() {
      _schoolId = v;
      _editorKeys.clear();
      _error = null;
      _accountRole = '';
      _queries.clear();
      _statuses.clear();
      _historyQuery.clear();
      _historyKind = '';
      _historyAction = '';
    });
    // The old detail cannot remain under the new school.
    if (_detailId != null) widget.onNavigate(_section);
  }

  Widget _schoolSelector({required bool compactHeader}) => Align(
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
          for (final school in _schools) SelectOption(school.id, school.name),
        ],
        onChanged: _changeSchool,
      ),
    ),
  );

  void _publishSchoolChrome({required bool allowed}) {
    final chrome = widget.schoolChrome;
    if (chrome == null) return;
    final keepSelection =
        allowed &&
        _schools.isNotEmpty &&
        _section != '/admin/applications' &&
        _schoolId.isNotEmpty;
    final showInTitle = keepSelection && !widget.phoneChrome;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.schoolChrome != chrome) return;
      if (!keepSelection) {
        chrome.clear();
        return;
      }
      // Phone keeps schoolId for guest-preview seeding; title bar stays hidden.
      chrome.publish(
        schoolId: _schoolId,
        schools: [
          for (final school in _schools) (id: school.id, name: school.name),
        ],
        visible: showInTitle,
        onChanged: _changeSchool,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_schools.any((r) => r.id == _schoolId)) {
      final preferred = widget.initialSchoolId?.trim() ?? '';
      _schoolId =
          preferred.isNotEmpty && _schools.any((r) => r.id == preferred)
          ? preferred
          : (_schools.firstOrNull?.id ?? '');
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
            _isSuperAdmin) &&
        (_detailId == null ||
            detail != null &&
                sectionKinds[_section]?.contains(detail.kind) == true &&
                _repo.canRead(_actor, detail));
    _publishSchoolChrome(allowed: allowed);
    final showBodySchool =
        _schools.isNotEmpty &&
        allowed &&
        _section != '/admin/applications' &&
        (widget.schoolChrome == null || widget.phoneChrome);
    return AdminShell(
      sidebarVisible: widget.sidebarVisible,
      menus: {
        for (final entry in AdminWorkspace.menus.entries)
          if (!{'/admin/accounts', '/admin/applications'}.contains(entry.key) ||
              _isSuperAdmin)
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
          return FeaturePage(
            title: title,
            description: allowed
                ? AdminWorkspace.menuDescriptions[_section]
                : null,
            body: [
              if (showBodySchool)
                _schoolSelector(compactHeader: compactHeader),
              if (_repo.live && _repo.warning != null) Text(_repo.warning!),
              if (_loading)
                const LinearProgressIndicator()
              else if (_loadError != null && !_hasLoaded) ...[
                FeatureLine.one(text: _loadError!),
                FeatureLine.reload(onPressed: _load),
              ] else if (!allowed) ...[
                const FeatureLine.one(
                  text: '현재 계정 상태·역할·관리 범위로 이 화면에 접근할 수 없습니다.',
                ),
                TextButton(
                  onPressed: () => _navigate('/admin/overview'),
                  child: const Text('관리 현황으로'),
                ),
              ] else ...[
                if (_refreshing && _section == '/admin/overview')
                  const LinearProgressIndicator(),
                if (_loadError != null) ...[
                  FeatureLine.one(text: _loadError!),
                  FeatureLine.reload(
                    onPressed: _busy || _refreshing ? null : _load,
                  ),
                ],
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_section == '/admin/overview') _overview(),
                if (_section == '/admin/rules') ...[
                  _ruleViewSwitcher(),
                  const SizedBox(height: 16),
                ],
                if (_section != '/admin/rules' || _ruleView == 'line')
                  for (final kind
                      in sectionKinds[_section] ?? <AdminKind>[]) ...[
                    _records(kind),
                    SizedBox(height: FeatureLine.slotGap(context)),
                  ]
                else if (_ruleView == 'grid')
                  GraduationCreditGridPage(
                    key: _creditGrid,
                    schoolName: _relationName(_schoolId).isEmpty
                        ? '현재 학교'
                        : _relationName(_schoolId),
                    departments: [
                      for (final department in _repo.records.where(
                        (r) =>
                            r.kind == AdminKind.department &&
                            r.value('institutionId') == _schoolId &&
                            _repo.canRead(_actor, r),
                      ))
                        department,
                    ],
                  )
                else
                  GraduationCertificationPage(
                    key: _certification,
                    schoolName: _relationName(_schoolId).isEmpty
                        ? '현재 학교'
                        : _relationName(_schoolId),
                    departments: [
                      for (final department in _repo.records.where(
                        (r) =>
                            r.kind == AdminKind.department &&
                            r.value('institutionId') == _schoolId &&
                            _repo.canRead(_actor, r),
                      ))
                        department,
                    ],
                  ),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppearanceSettingsSection(),
                          AccountSettingsSection(),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
