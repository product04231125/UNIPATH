import 'admin_models.dart';

List<AdminRecord> adminFixture() => [
  for (final (id, name, role) in [
    ('super-admin', '합성 운영 담당', 'super_admin'),
    ('school-admin', '합성 학교 담당', 'school_admin'),
    ('sample-user', '합성 사용자', 'user'),
  ])
    AdminRecord(
      id: id,
      kind: AdminKind.account,
      values: {'name': name, 'role': role, 'accountStatus': 'active'},
    ),
  for (final id in ['school-a', 'school-b']) ...[
    AdminRecord(
      id: id,
      kind: AdminKind.institution,
      values: {'name': '합성 대학 ${id.endsWith('a') ? 'A' : 'B'}'},
    ),
    AdminRecord(
      id: '$id-dept',
      kind: AdminKind.department,
      values: {'name': '합성 학과', 'institutionId': id, 'code': 'DEPT'},
    ),
    AdminRecord(
      id: '$id-curr',
      kind: AdminKind.curriculum,
      values: {'name': '합성 교육과정', 'departmentId': '$id-dept', 'year': '2026'},
    ),
  ],
  AdminRecord(
    id: 'scope-a',
    kind: AdminKind.scope,
    status: 'active',
    createdBy: 'super-admin',
    values: {
      'name': '합성 대학 A 전체',
      'userId': 'school-admin',
      'institutionId': 'school-a',
      'scopeType': 'institution',
      'reason': '개발용 초기 범위',
      'grantedBy': 'super-admin',
      'grantedAt': '2026-10-14T00:00:00.000Z',
    },
  ),
];
