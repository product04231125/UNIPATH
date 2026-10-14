import 'package:flutter/foundation.dart';

import '../../shared/external_links.dart';
import '../auth/app_role.dart';
import 'admin_fixture.dart';
import 'admin_models.dart';
import 'admin_fields.dart';

abstract class AdminRepository extends ChangeNotifier {
  List<AdminRecord> get records;
  List<AdminAuditEntry> get history;
  Future<void> load();
  AppRole role(String actorId);
  bool active(String actorId);
  String school(AdminRecord record);
  bool canRead(String actorId, AdminRecord record);
  bool canWrite(String actorId, AdminRecord record);
  Future<void> save(String actorId, AdminRecord record);
  Future<void> remove(String actorId, String id);
  Future<void> apply(String actorId, String id);
  Future<AdminRecord> newVersion(String actorId, String id);
  Future<void> revoke(String actorId, String id, String reason);
}

/// In-memory fake only. Every operation checks the latest role/scope.
class FakeAdminRepository extends AdminRepository {
  FakeAdminRepository({List<AdminRecord>? seed, this.beforeOperation})
    : _records = [...seed ?? adminFixture()];
  final Future<void> Function(String operation)? beforeOperation;
  final List<AdminRecord> _records;
  final List<AdminAuditEntry> _history = [];
  int _sequence = 0;
  Future<void> _pending = Future.value();
  @override
  List<AdminRecord> get records => List.unmodifiable(_records);
  @override
  List<AdminAuditEntry> get history => List.unmodifiable(_history);
  AdminRecord? find(String id) => _records.where((r) => r.id == id).firstOrNull;
  @override
  AppRole role(String actorId) => roleFromRecord(find(actorId));
  @override
  bool active(String actorId) =>
      find(actorId)?.value('accountStatus') == 'active';
  @override
  Future<void> load() async {
    await beforeOperation?.call('load');
  }

  List<AdminRecord> scopes(String actorId) => _records
      .where(
        (r) =>
            r.kind == AdminKind.scope &&
            r.value('userId') == actorId &&
            r.status == 'active',
      )
      .toList();
  String school(AdminRecord r) {
    if (r.kind == AdminKind.institution) return r.id;
    if (r.value('institutionId').isNotEmpty) return r.value('institutionId');
    if (r.value('departmentId').isNotEmpty)
      return find(r.value('departmentId'))?.value('institutionId') ?? '';
    if (r.value('curriculumId').isNotEmpty) {
      final c = find(r.value('curriculumId'));
      return c == null ? '' : school(c);
    }
    return '';
  }

  String department(AdminRecord r) => r.kind == AdminKind.department
      ? r.id
      : r.value('departmentId').isNotEmpty
      ? r.value('departmentId')
      : find(r.value('curriculumId'))?.value('departmentId') ?? '';
  String curriculum(AdminRecord r) =>
      r.kind == AdminKind.curriculum ? r.id : r.value('curriculumId');
  bool _within(AdminRecord scope, AdminRecord r) {
    if (scope.value('institutionId') != school(r)) return false;
    return switch (scope.value('scopeType')) {
      'institution' => true,
      'department' => scope.value('departmentId') == department(r),
      'curriculum' => scope.value('curriculumId') == curriculum(r),
      _ => false,
    };
  }

  @override
  bool canRead(String actorId, AdminRecord r) {
    if (!active(actorId) || role(actorId) == AppRole.user) return false;
    if (role(actorId) == AppRole.superAdmin) return true;
    if (r.kind == AdminKind.account) return r.id == actorId;
    if (r.kind == AdminKind.scope) return r.value('userId') == actorId;
    return scopes(actorId).any(
      (s) =>
          _within(s, r) ||
          r.kind == AdminKind.institution && r.id == s.value('institutionId') ||
          r.kind == AdminKind.department && r.id == s.value('departmentId') ||
          r.kind == AdminKind.course && s.value('institutionId') == school(r),
    );
  }

  @override
  bool canWrite(String actorId, AdminRecord r) {
    if (!active(actorId) || role(actorId) == AppRole.user) return false;
    if (role(actorId) == AppRole.superAdmin) return true;
    if ([
      AdminKind.account,
      AdminKind.scope,
      AdminKind.institution,
    ].contains(r.kind))
      return false;
    return scopes(actorId).any((s) => _within(s, r));
  }

  void _require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  void _validate(AdminRecord r) {
    for (final f in adminFields(r.kind)) {
      _require(
        !f.required || r.value(f.key).trim().isNotEmpty,
        '${f.label}을 입력하세요.',
      );
      _require(
        f.options.isEmpty ||
            r.value(f.key).isEmpty ||
            f.options.containsKey(r.value(f.key)),
        '${f.label}의 값을 확인하세요.',
      );
    }
    for (final key in ['sourceUrl', 'officialUrl']) {
      _require(
        r.value(key).isEmpty || browserLink(r.value(key)) != null,
        'HTTP(S) 주소를 입력하세요.',
      );
    }
    for (final key in ['effectiveFrom', 'effectiveTo']) {
      final value = r.value(key);
      final date = DateTime.tryParse(value);
      _require(
        value.isEmpty ||
            RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
                date != null &&
                date.toIso8601String().startsWith(value),
        '실제 날짜를 YYYY-MM-DD로 입력하세요.',
      );
    }
    _require(
      r.value('effectiveFrom').isEmpty ||
          r.value('effectiveTo').isEmpty ||
          r.value('effectiveFrom').compareTo(r.value('effectiveTo')) <= 0,
      '적용 종료일은 시작일 이후여야 합니다.',
    );
    _require(
      !_records.any(
        (other) =>
            other.id != r.id &&
            other.kind == r.kind &&
            !r.kind.versioned &&
            r.kind != AdminKind.scope &&
            r.kind != AdminKind.account &&
            (r.kind == AdminKind.institution || school(other) == school(r)) &&
            (r.value('code').isNotEmpty
                ? other.value('code') == r.value('code')
                : r.kind == AdminKind.curriculumCourse
                ? other.value('curriculumId') == r.value('curriculumId') &&
                      other.value('courseId') == r.value('courseId')
                : other.name == r.name &&
                      other.value('departmentId') == r.value('departmentId') &&
                      other.value('year') == r.value('year')),
      ),
      '동일 범위에 중복 이름·코드·관계가 있습니다.',
    );
    _require(r.name.trim().isNotEmpty, '이름을 입력하세요.');
    for (final (key, kind) in [
      ('institutionId', AdminKind.institution),
      ('departmentId', AdminKind.department),
      ('curriculumId', AdminKind.curriculum),
      ('courseId', AdminKind.course),
      ('ruleId', AdminKind.rule),
      ('userId', AdminKind.account),
    ]) {
      if (r.value(key).isNotEmpty)
        _require(find(r.value(key))?.kind == kind, '연결 대상이 없거나 종류가 다릅니다.');
    }
    if (r.value('institutionId').isNotEmpty &&
        r.value('departmentId').isNotEmpty) {
      _require(
        find(r.value('departmentId'))?.value('institutionId') ==
            r.value('institutionId'),
        '학교와 학과 소속이 다릅니다.',
      );
    }
    if (r.value('departmentId').isNotEmpty &&
        r.value('curriculumId').isNotEmpty) {
      _require(
        find(r.value('curriculumId'))?.value('departmentId') ==
            r.value('departmentId'),
        '학과와 교육과정 소속이 다릅니다.',
      );
    }
    if (r.kind == AdminKind.curriculumCourse) {
      _require(
        r.value('curriculumId').isNotEmpty && r.value('courseId').isNotEmpty,
        '교육과정과 과목을 선택하세요.',
      );
      _require(
        school(find(r.value('courseId'))!) == school(r),
        '교육과정과 과목의 학교가 다릅니다.',
      );
    }
    if (r.kind == AdminKind.department || r.kind == AdminKind.course)
      _require(r.value('institutionId').isNotEmpty, '학교를 선택하세요.');
    if (r.kind == AdminKind.curriculum)
      _require(r.value('departmentId').isNotEmpty, '학과를 선택하세요.');
    if (r.kind.versioned) {
      _require(r.value('institutionId').isNotEmpty, '학교를 선택하세요.');
      if (r.value('curriculumId').isNotEmpty)
        _require(
          school(find(r.value('curriculumId'))!) == school(r),
          '교육과정의 학교가 다릅니다.',
        );
      if (r.value('ruleId').isNotEmpty)
        _require(
          school(find(r.value('ruleId'))!) == school(r),
          '근거 규칙의 학교가 다릅니다.',
        );
    }
    if (r.kind == AdminKind.curriculum)
      _require(
        RegExp(r'^\d{4}$').hasMatch(r.value('year')),
        '적용 연도는 네 자리로 입력하세요.',
      );
    if (r.kind == AdminKind.course) {
      final credits = double.tryParse(r.value('credits'));
      _require(
        credits != null && credits.isFinite && credits > 0,
        '학점은 0보다 큰 유한 숫자여야 합니다.',
      );
    }
    if (r.kind == AdminKind.document) {
      _require(
        r.value('sourceUrl').isNotEmpty &&
            browserLink(r.value('sourceUrl')) != null,
        '공식 문서의 HTTP(S) 출처를 입력하세요.',
      );
    }
    if (r.kind == AdminKind.scope) {
      final type = r.value('scopeType');
      _require(
        ['institution', 'department', 'curriculum'].contains(type),
        '관리 범위 종류를 선택하세요.',
      );
      _require(
        r.value('institutionId').isNotEmpty && r.value('userId').isNotEmpty,
        '학교와 사용자를 선택하세요.',
      );
      _require(
        find(r.value('userId'))?.value('role') != 'super_admin',
        '슈퍼관리자에게 학교 범위를 부여하지 않습니다.',
      );
      _require(
        find(r.value('userId'))?.value('accountStatus') == 'active',
        '정지 계정에는 범위를 부여하지 않습니다.',
      );
      _require(
        type != 'institution' ||
            r.value('departmentId').isEmpty && r.value('curriculumId').isEmpty,
        '학교 전체 범위에는 하위 범위를 지정하지 않습니다.',
      );
      _require(
        type == 'institution' || r.value('departmentId').isNotEmpty,
        '학과를 선택하세요.',
      );
      _require(
        type != 'department' || r.value('curriculumId').isEmpty,
        '학과 범위에는 교육과정을 지정하지 않습니다.',
      );
      _require(
        type != 'curriculum' || r.value('curriculumId').isNotEmpty,
        '교육과정을 선택하세요.',
      );
      _require(r.value('reason').trim().isNotEmpty, '권한 변경 사유를 입력하세요.');
      _require(
        !_records.any(
          (s) =>
              s.id != r.id &&
              s.kind == AdminKind.scope &&
              s.status == 'active' &&
              [
                'userId',
                'institutionId',
                'scopeType',
                'departmentId',
                'curriculumId',
              ].every((key) => s.value(key) == r.value(key)),
        ),
        '동일한 활성 관리 범위가 이미 있습니다.',
      );
    }
  }

  void _audit(String actor, String action, AdminRecord r, String result) {
    _history.add(
      AdminAuditEntry(
        actorId: actor,
        action: action,
        targetId: r.id,
        kind: r.kind,
        institutionId: school(r),
        result: result,
        requestId: 'mock-${++_sequence}',
        at: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> _operation(
    String actor,
    String action,
    AdminRecord r,
    void Function() change,
  ) {
    final task = _pending.then((_) async {
      try {
        await beforeOperation?.call(action);
        _require(
          action == 'save' || identical(find(r.id), r),
          '대상이 변경되었습니다. 다시 확인하세요.',
        );
        _require(canWrite(actor, r), '현재 역할·계정 상태·관리 범위로 작업할 수 없습니다.');
        change();
        _audit(actor, action, r, 'success');
      } catch (_) {
        _audit(actor, action, r, 'failed');
        notifyListeners();
        rethrow;
      }
      notifyListeners();
    });
    _pending = task.then<void>((_) {}, onError: (Object _) {});
    return task;
  }

  @override
  Future<void> save(String actorId, AdminRecord r) =>
      _operation(actorId, 'save', r, () {
        final old = find(r.id);
        _require(
          old == null || old.kind == r.kind && canWrite(actorId, old),
          '원본을 수정할 수 없습니다.',
        );
        _require(
          old?.status != 'applied' && old?.status != 'revoked',
          '적용·회수 이력은 직접 수정할 수 없습니다.',
        );
        _require(
          r.kind != AdminKind.account ||
              old != null &&
                  r.value('role') == old.value('role') &&
                  ['active', 'suspended'].contains(r.value('accountStatus')) &&
                  r.id != actorId,
          '본인·역할 변경 또는 계정 생성은 지원하지 않습니다.',
        );
        _validate(r);
        for (final f in adminFields(
          r.kind,
        ).where((f) => f.relation != null && r.value(f.key).isNotEmpty)) {
          _require(
            canRead(actorId, find(r.value(f.key))!),
            '연결 대상이 현재 관리 범위 밖입니다.',
          );
        }
        final now = DateTime.now().toUtc();
        final values = {...r.values};
        if (r.kind == AdminKind.scope) {
          values['grantedBy'] = actorId;
          values['grantedAt'] = now.toIso8601String();
        }
        final saved = AdminRecord(
          id: r.id,
          kind: r.kind,
          values: values,
          version: old?.version ?? r.version,
          lineage: old?.lineage ?? r.lineage,
          status: r.kind == AdminKind.scope ? 'active' : old?.status ?? 'draft',
          createdBy: old?.createdBy ?? actorId,
          updatedBy: actorId,
          updatedAt: now,
        );
        if (old != null) _records.remove(old);
        _records.add(saved);
        if (r.kind == AdminKind.scope) {
          final user = find(r.value('userId'))!;
          _records[_records.indexOf(user)] = user.copy(
            values: {...user.values, 'role': 'school_admin'},
            updatedBy: actorId,
            updatedAt: now,
          );
        }
      });
  @override
  Future<void> remove(String actorId, String id) {
    final r = find(id);
    _require(r != null, '대상이 없습니다.');
    return _operation(actorId, 'delete', r!, () {
      _require(
        ![AdminKind.account, AdminKind.scope].contains(r.kind) &&
            r.status != 'applied',
        '계정·권한·적용 이력은 삭제하지 않습니다.',
      );
      _require(
        !_records.any(
          (other) =>
              other.id != id &&
              [
                'institutionId',
                'departmentId',
                'curriculumId',
                'courseId',
                'ruleId',
              ].any((key) => other.value(key) == id),
        ),
        '연결된 데이터가 있습니다. 참조를 먼저 정리하세요.',
      );
      _records.remove(r);
    });
  }

  @override
  Future<void> apply(String actorId, String id) {
    final r = find(id);
    _require(r != null, '대상이 없습니다.');
    return _operation(actorId, 'apply', r!, () {
      _require(r.kind.versioned && r.status == 'draft', '초안만 적용할 수 있습니다.');
      _validate(r);
      _require(
        r.kind != AdminKind.rule ||
            r.value('ruleType').isNotEmpty &&
                r.value('definition').trim().isNotEmpty,
        '규칙 종류와 조건 설명을 입력하세요.',
      );
      final now = DateTime.now().toUtc();
      _records[_records.indexOf(r)] = r.copy(
        status: 'applied',
        appliedBy: actorId,
        appliedAt: now,
      );
    });
  }

  @override
  Future<AdminRecord> newVersion(String actorId, String id) async {
    final r = find(id);
    _require(r != null, '대상이 없습니다.');
    late AdminRecord draft;
    await _operation(actorId, 'new_version', r!, () {
      _require(
        r.kind.versioned && r.status == 'applied',
        '적용 버전에서 새 초안을 만드세요.',
      );
      _require(
        !_records.any(
          (other) => other.lineage == r.lineage && other.status == 'draft',
        ),
        '이미 새 버전 초안이 있습니다.',
      );
      final latest = _records
          .where((other) => other.lineage == r.lineage)
          .map((other) => other.version)
          .reduce((a, b) => a > b ? a : b);
      draft = AdminRecord(
        id: 'mock-version-${++_sequence}',
        kind: r.kind,
        values: r.values,
        lineage: r.lineage,
        version: latest + 1,
        createdBy: actorId,
        updatedBy: actorId,
        updatedAt: DateTime.now().toUtc(),
      );
      _records.add(draft);
    });
    return draft;
  }

  @override
  Future<void> revoke(String actorId, String id, String reason) {
    final r = find(id);
    _require(r != null, '대상이 없습니다.');
    return _operation(actorId, 'revoke', r!, () {
      _require(
        r.kind == AdminKind.scope &&
            r.status == 'active' &&
            reason.trim().isNotEmpty,
        '활성 범위와 회수 사유를 확인하세요.',
      );
      _records[_records.indexOf(r)] = r.copy(
        status: 'revoked',
        updatedBy: actorId,
        updatedAt: DateTime.now().toUtc(),
        values: {
          ...r.values,
          'revokedBy': actorId,
          'revokedAt': DateTime.now().toUtc().toIso8601String(),
          'reason': reason.trim(),
        },
      );
    });
  }
}
