import '../auth/app_role.dart';

enum AdminKind {
  institution,
  department,
  curriculum,
  course,
  curriculumCourse,
  rule,
  document,
  account,
  scope,
}

extension AdminKindLabel on AdminKind {
  String get label => switch (this) {
    AdminKind.institution => '학교',
    AdminKind.department => '학과',
    AdminKind.curriculum => '교육과정',
    AdminKind.course => '과목',
    AdminKind.curriculumCourse => '교육과정 과목 연결',
    AdminKind.rule => '졸업요건',
    AdminKind.document => '공식 문서',
    AdminKind.account => '사용자',
    AdminKind.scope => '관리 범위',
  };
  bool get versioned => this == AdminKind.rule || this == AdminKind.document;
}

/// Temporary mock input model, never a server DTO or official approval.
class AdminRecord {
  AdminRecord({
    required this.id,
    required this.kind,
    required Map<String, String> values,
    this.version = 1,
    String? lineage,
    this.status = 'draft',
    this.createdBy = '',
    this.updatedBy = '',
    this.appliedBy = '',
    this.updatedAt,
    this.appliedAt,
  }) : values = Map.unmodifiable(values),
       lineage = lineage ?? id;
  final String id, lineage, status, createdBy, updatedBy, appliedBy;
  final AdminKind kind;
  final Map<String, String> values;
  final int version;
  final DateTime? updatedAt, appliedAt;
  String value(String key) => values[key] ?? '';
  String get name => value('name');
  AdminRecord copy({
    Map<String, String>? values,
    String? status,
    String? updatedBy,
    String? appliedBy,
    DateTime? updatedAt,
    DateTime? appliedAt,
  }) => AdminRecord(
    id: id,
    kind: kind,
    values: values ?? this.values,
    lineage: lineage,
    version: version,
    status: status ?? this.status,
    createdBy: createdBy,
    updatedBy: updatedBy ?? this.updatedBy,
    appliedBy: appliedBy ?? this.appliedBy,
    updatedAt: updatedAt ?? this.updatedAt,
    appliedAt: appliedAt ?? this.appliedAt,
  );
}

class AdminAuditEntry {
  const AdminAuditEntry({
    required this.actorId,
    required this.action,
    required this.targetId,
    required this.kind,
    required this.institutionId,
    required this.result,
    required this.requestId,
    required this.at,
  });
  final String actorId, action, targetId, institutionId, result, requestId;
  final AdminKind kind;
  final DateTime at;
}

AppRole roleFromRecord(AdminRecord? account) =>
    switch (account?.value('role')) {
      'school_admin' => AppRole.schoolAdmin,
      'super_admin' => AppRole.superAdmin,
      _ => AppRole.user,
    };
