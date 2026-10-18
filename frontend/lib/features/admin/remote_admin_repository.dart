import '../auth/app_role.dart';
import '../auth/auth_api.dart';
import 'admin_fields.dart';
import 'admin_models.dart';
import 'admin_repository.dart';

/// Shared authenticated transport: Web cookies and native in-memory tokens.
class RemoteAdminRepository extends AdminRepository {
  RemoteAdminRepository(
    this._identity, {
    required this.auth,
    required this.api,
  });
  final AuthGateway auth;
  final ApiGateway api;
  AuthIdentity _identity;
  String get userId => _identity.id;
  int get permissionVersion => _identity.version;
  bool _disposed = false;
  int _loadEpoch = 0;
  List<AdminRecord> _records = [];
  List<AdminAuditEntry> _history = [];
  String? _warning;
  @override
  bool get live => true;
  @override
  String? get warning => _warning;
  @override
  List<AdminRecord> get records => List.unmodifiable(_records);
  @override
  List<AdminAuditEntry> get history => List.unmodifiable(_history);
  static const paths = {
    AdminKind.institution: 'institutions',
    AdminKind.department: 'departments',
    AdminKind.curriculum: 'curricula',
    AdminKind.course: 'courses',
    AdminKind.curriculumCourse: 'curriculum-courses',
    AdminKind.ruleSet: 'rule-sets',
    AdminKind.rule: 'rules',
    AdminKind.document: 'documents',
    AdminKind.account: 'users',
    AdminKind.scope: 'scopes',
  };
  static const keys = {
    'institutionId': 'institution_id',
    'departmentId': 'department_id',
    'curriculumId': 'curriculum_id',
    'courseId': 'course_id',
    'ruleSetId': 'rule_set_id',
    'ruleId': 'rule_id',
    'countryCode': 'country_code',
    'officialUrl': 'official_url',
    'sourceUrl': 'source_url',
    'ruleType': 'rule_type',
    'documentType': 'document_type',
    'effectiveFrom': 'effective_from',
    'effectiveTo': 'effective_to',
    'userId': 'user_id',
    'accountStatus': 'account_status',
    'scopeType': 'scope_type',
    'grantedBy': 'granted_by',
    'grantedAt': 'granted_at',
    'revokedBy': 'revoked_by',
    'revokedAt': 'revoked_at',
    'revocationReason': 'revocation_reason',
  };
  void updateIdentity(AuthIdentity value) {
    _loadEpoch++;
    _identity = value;
    _records = [];
    _history = [];
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _loadEpoch++;
    _records = [];
    _history = [];
    super.dispose();
  }

  Future<Map<String, dynamic>?> _request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    try {
      return await api.request(method, 'admin/$path', body);
    } on AuthFailure catch (error) {
      if (error.status == 401 || error.status == 403) {
        _records = [];
        _history = [];
        _notify();
      }
      throw StateError(
        error.status == 422
            ? '입력 형식·소속·길이를 확인하세요. 숫자·날짜·HTTP(S) 주소를 확인한 뒤 다시 저장하세요.'
            : error.message,
      );
    }
  }

  Future<List<Map<String, dynamic>>> _pages(String path) async {
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};
    String? cursor;
    do {
      final query = Uri(queryParameters: {'limit': '100', 'cursor': ?cursor})
          .query;
      final response = (await _request('GET', '$path?$query'))!;
      result.addAll(List<Map<String, dynamic>>.from(response['items'] as List));
      cursor = response['next_cursor'] as String?;
      if (cursor != null && !seen.add(cursor)) {
        throw StateError('목록을 끝까지 읽지 못했습니다. 다시 읽어주세요.');
      }
    } while (cursor != null);
    return result;
  }

  AdminRecord _record(AdminKind kind, Map<String, dynamic> data) {
    final id = data['id'] as String;
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) {
      throw const FormatException('Invalid ID');
    }
    final values = <String, String>{
      'institutionId': data['institution_id']?.toString() ?? '',
    };
    for (final field in adminFields(kind)) {
      final value = data[keys[field.key] ?? field.key];
      if (value != null) values[field.key] = value.toString();
    }
    if (kind == AdminKind.account) {
      values.addAll({
        'name': data['display_name'] as String,
        'email': data['email'] as String,
        'role': data['role'] as String,
        'accountStatus': data['account_status'] as String,
      });
    }
    if (kind == AdminKind.scope) {
      values.addAll({
        'name': '학교 전체 관리 범위',
        'scopeType': 'institution',
        for (final key in [
          'grantedBy',
          'grantedAt',
          'revokedBy',
          'revokedAt',
          'revocationReason',
        ])
          key: data[keys[key]]?.toString() ?? '',
      });
    }
    return AdminRecord(
      id: id,
      kind: kind,
      values: values,
      version: data['version'] as int,
      revision: data['revision'] as int? ?? 1,
      status: data['status'] as String? ?? 'active',
      lineage: data['lineage_id'] as String?,
      createdBy: data['created_by'] as String? ?? '',
      updatedBy: data['updated_by'] as String? ?? '',
      appliedBy: data['applied_by'] as String? ?? '',
      updatedAt: DateTime.tryParse(data['updated_at'] as String? ?? ''),
      appliedAt: DateTime.tryParse(data['applied_at'] as String? ?? ''),
    );
  }

  @override
  Future<void> load() async {
    final epoch = ++_loadEpoch;
    try {
      final identity = await auth.me();
      if (_disposed || epoch != _loadEpoch) return;
      if (identity == null ||
          identity.id != userId ||
          identity.role == AppRole.user) {
        _records = [];
        _history = [];
        _notify();
        throw StateError('관리 권한이 변경되었습니다. 다시 로그인해 주세요.');
      }
      _identity = identity;
      final rows = <AdminRecord>[];
      final kinds = paths.keys
          .where(
            (kind) =>
                kind != AdminKind.account ||
                identity.role == AppRole.superAdmin,
          )
          .toList();
      final pages = await Future.wait(
        kinds.map((kind) => _pages(paths[kind]!)),
      );
      for (var i = 0; i < kinds.length; i++) {
        rows.addAll(pages[i].map((r) => _record(kinds[i], r)));
      }
      if (identity.role != AppRole.superAdmin) {
        rows.add(
          AdminRecord(
            id: identity.id,
            kind: AdminKind.account,
            status: 'active',
            values: {
              'name': identity.displayName,
              'email': identity.email,
              'role': 'school_admin',
              'accountStatus': 'active',
            },
          ),
        );
      }
      final events = await _pages('audit-logs');
      final history = <AdminAuditEntry>[];
      for (final e in events) {
        final action = e['action'] as String;
        history.add(
          AdminAuditEntry(
            actorId: e['actor_id'] as String? ?? '',
            targetId: e['target_id'] as String,
            institutionId: e['institution_id'] as String? ?? '',
            action: action.startsWith('academic:')
                ? action.split(':').last
                : action,
            kind: AdminKind.values.firstWhere((k) => k.name == e['kind']),
            result: 'success',
            requestId: e['request_id'] as String? ?? '',
            at: DateTime.parse(e['occurred_at'] as String),
          ),
        );
      }
      history.sort((a, b) => a.at.compareTo(b.at));
      final confirmed = await auth.me();
      if (confirmed == null ||
          confirmed.id != identity.id ||
          confirmed.version != identity.version) {
        _records = [];
        _history = [];
        _notify();
        throw StateError('계정이나 관리 권한이 변경되었습니다. 다시 읽거나 로그인해 주세요.');
      }
      if (_disposed || epoch != _loadEpoch) return;
      _records = rows;
      _history = history;
      _warning = null;
      _notify();
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError('관리 데이터를 읽지 못했습니다. 연결을 확인하고 다시 읽어주세요.');
    }
  }

  @override
  AppRole role(String actorId) =>
      actorId == userId ? _identity.role : AppRole.user;
  @override
  bool active(String actorId) => !_disposed && actorId == userId;
  @override
  String school(AdminRecord record) => record.kind == AdminKind.institution
      ? record.id
      : record.value('institutionId');
  @override
  bool canRead(String actorId, AdminRecord record) {
    if (!active(actorId)) return false;
    if (role(actorId) == AppRole.superAdmin) return true;
    if (record.kind == AdminKind.account) return record.id == actorId;
    if (record.kind == AdminKind.scope) {
      return record.value('userId') == actorId;
    }
    return _identity.scopes.any(
      (s) => s['institution_id'] == school(record) && s['status'] == 'active',
    );
  }

  @override
  bool canWrite(String actorId, AdminRecord record) =>
      canRead(actorId, record) &&
      ([
            AdminKind.institution,
            AdminKind.account,
            AdminKind.scope,
          ].contains(record.kind)
          ? role(actorId) == AppRole.superAdmin && record.id != actorId
          : true);
  @override
  List<AdminField> fields(AdminKind kind) {
    if (kind == AdminKind.scope) {
      return adminFields(kind)
          .where((f) => ['institutionId', 'userId', 'reason'].contains(f.key))
          .toList();
    }
    if (kind == AdminKind.account) {
      return const [
        AdminField(
          'role',
          '역할',
          options: {
            'user': '일반 사용자',
            'school_admin': '학교관리자',
            'super_admin': '슈퍼관리자',
          },
        ),
        AdminField(
          'accountStatus',
          '계정 상태',
          options: {'active': '활성', 'suspended': '정지'},
        ),
      ];
    }
    return adminFields(kind);
  }

  Map<String, Object?> _body(AdminRecord record) {
    final result = <String, Object?>{};
    for (final f in fields(record.kind)) {
      final value = record.value(f.key);
      final key = keys[f.key] ?? f.key;
      if (['year', 'credits'].contains(f.key)) {
        final number = num.tryParse(value);
        if (number == null ||
            !number.isFinite ||
            f.key == 'year' && number != number.truncate()) {
          throw StateError('${f.label}을 올바른 숫자로 입력하세요.');
        }
        result[key] = f.key == 'year' ? number.toInt() : value;
      } else if (f.key == 'required') {
        if (!['true', 'false'].contains(value)) {
          throw StateError('필수 여부를 선택하세요.');
        }
        result[key] = value == 'true';
      } else if (value.isEmpty &&
          (key.endsWith('_id') || key.startsWith('effective_'))) {
        result[key] = null;
      } else {
        result[key] = value;
      }
    }
    if (![
      AdminKind.institution,
      AdminKind.account,
      AdminKind.scope,
    ].contains(record.kind)) {
      result['institution_id'] = record.value('institutionId');
    }
    return result;
  }

  Future<void> _refreshAfterWrite(AdminRecord? saved, {String? removed}) async {
    if (_disposed) return;
    if (removed != null) _records.removeWhere((r) => r.id == removed);
    if (saved != null) {
      _records.removeWhere((r) => r.id == saved.id);
      _records.add(saved);
    }
    _notify();
    try {
      await load();
    } catch (_) {
      if (!_disposed) {
        _warning = '저장은 완료했지만 목록을 새로 읽지 못했습니다. 다시 읽어주세요.';
        _notify();
      }
    }
  }

  @override
  Future<void> save(String actorId, AdminRecord record) async {
    final existing = _records.any((r) => r.id == record.id);
    if (record.kind == AdminKind.account && !existing) {
      throw StateError('사용자는 회원가입으로 생성합니다.');
    }
    final body = _body(record);
    if (existing) body['expected_version'] = record.version;
    final path =
        '${paths[record.kind]}${existing ? '/${record.id}' : ''}${record.kind == AdminKind.account ? '/access' : ''}';
    final response = (await _request(existing ? 'PATCH' : 'POST', path, body))!;
    await _refreshAfterWrite(_record(record.kind, response));
  }

  AdminRecord _find(String id) => _records.firstWhere((r) => r.id == id);
  @override
  Future<int> referenceCount(AdminRecord record) async =>
      (await _request(
            'GET',
            '${paths[record.kind]}/${record.id}/references',
          ))!['total']
          as int;
  @override
  Future<void> remove(String actorId, String id) async {
    final r = _find(id);
    await _request(
      'DELETE',
      '${paths[r.kind]}/$id?expected_version=${r.version}',
    );
    await _refreshAfterWrite(null, removed: id);
  }

  @override
  Future<void> apply(String actorId, String id) async {
    final r = _find(id);
    final result = (await _request('POST', '${paths[r.kind]}/$id/apply', {
      'expected_version': r.version,
    }))!;
    await _refreshAfterWrite(_record(r.kind, result));
  }

  @override
  Future<AdminRecord> newVersion(String actorId, String id) async {
    final r = _find(id);
    final result = (await _request('POST', '${paths[r.kind]}/$id/drafts', {
      'expected_version': r.version,
    }))!;
    final draft = _record(r.kind, result);
    await _refreshAfterWrite(draft);
    return draft;
  }

  @override
  Future<void> revoke(String actorId, String id, String reason) async {
    final r = _find(id);
    final result = (await _request('POST', 'scopes/$id/revoke', {
      'expected_version': r.version,
      'reason': reason,
    }))!;
    await _refreshAfterWrite(_record(AdminKind.scope, result));
  }
}
