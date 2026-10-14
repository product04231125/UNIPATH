import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/admin/admin_models.dart';
import 'package:university_path_frontend/features/admin/admin_repository.dart';
import 'package:university_path_frontend/features/auth/app_role.dart';

AdminRecord scope(
  String id, {
  String user = 'sample-user',
  String school = 'school-a',
  String type = 'institution',
  String department = '',
  String curriculum = '',
}) => AdminRecord(
  id: id,
  kind: AdminKind.scope,
  values: {
    'name': '범위',
    'userId': user,
    'institutionId': school,
    'scopeType': type,
    'departmentId': department,
    'curriculumId': curriculum,
    'reason': '합성 부여',
  },
);
AdminRecord rule(
  String id, {
  String school = 'school-a',
  String department = '',
  String curriculum = '',
}) => AdminRecord(
  id: id,
  kind: AdminKind.rule,
  values: {
    'name': '합성 규칙',
    'institutionId': school,
    'departmentId': department,
    'curriculumId': curriculum,
    'ruleType': 'credits',
    'definition': '직접 검토할 합성 조건',
  },
);

void main() {
  test(
    'school scope blocks cross-school writes and super manages all',
    () async {
      final repo = FakeAdminRepository();
      await repo.save('school-admin', rule('r-a'));
      await expectLater(
        repo.save('school-admin', rule('r-b', school: 'school-b')),
        throwsStateError,
      );
      await repo.save('super-admin', rule('r-b', school: 'school-b'));
      expect(repo.canRead('school-admin', repo.find('school-b')!), isFalse);
      expect(repo.history.last.result, 'success');
    },
  );
  test('grant validates nested scope and duplicate, revoke preserves history and blocks next mutation', () async {
    final repo = FakeAdminRepository();
    await expectLater(
      repo.save(
        'super-admin',
        scope('bad', type: 'department', department: 'school-b-dept'),
      ),
      throwsStateError,
    );
    await repo.save(
      'super-admin',
      scope(
        's',
        type: 'curriculum',
        department: 'school-a-dept',
        curriculum: 'school-a-curr',
      ),
    );
    expect(repo.role('sample-user'), AppRole.schoolAdmin);
    await expectLater(
      repo.save(
        'super-admin',
        scope(
          'duplicate',
          type: 'curriculum',
          department: 'school-a-dept',
          curriculum: 'school-a-curr',
        ),
      ),
      throwsStateError,
    );
    await repo.save(
      'sample-user',
      rule('nested', department: 'school-a-dept', curriculum: 'school-a-curr'),
    );
    await expectLater(
      repo.save('sample-user', rule('broad')),
      throwsStateError,
    );
    await repo.revoke('super-admin', 's', '합성 회수');
    expect(repo.find('s')!.status, 'revoked');
    expect(repo.find('s')!.value('revokedBy'), 'super-admin');
    await expectLater(
      repo.save(
        'sample-user',
        rule('after', department: 'school-a-dept', curriculum: 'school-a-curr'),
      ),
      throwsStateError,
    );
  });
  test('suspended account is denied; no actor can change own account or arbitrary role', () async {
    final repo = FakeAdminRepository();
    final school = repo.find('school-admin')!;
    await repo.save(
      'super-admin',
      school.copy(values: {...school.values, 'accountStatus': 'suspended'}),
    );
    await expectLater(repo.save('school-admin', rule('r')), throwsStateError);
    final own = repo.find('super-admin')!;
    await expectLater(
      repo.save(
        'super-admin',
        own.copy(values: {...own.values, 'accountStatus': 'suspended'}),
      ),
      throwsStateError,
    );
    expect(repo.active('super-admin'), isTrue);
  });
  test(
    'applied versions cannot mutate and new draft preserves previous snapshot',
    () async {
      final repo = FakeAdminRepository();
      await repo.save('school-admin', rule('r'));
      await repo.apply('school-admin', 'r');
      final applied = repo.find('r')!;
      await expectLater(
        repo.save(
          'school-admin',
          applied.copy(values: {...applied.values, 'name': '변경'}),
        ),
        throwsStateError,
      );
      final draft = await repo.newVersion('school-admin', 'r');
      expect(draft.version, 2);
      expect(draft.status, 'draft');
      await expectLater(repo.newVersion('school-admin', 'r'), throwsStateError);
      await repo.save(
        'school-admin',
        draft.copy(values: {...draft.values, 'name': '새 초안'}),
      );
      await repo.apply('school-admin', draft.id);
      expect(repo.find('r')!.name, '합성 규칙');
      expect(repo.find('r')!.appliedBy, 'school-admin');
      expect(repo.find(draft.id)!.status, 'applied');
    },
  );
  test(
    'references prevent deletion and failed write preserves source and retries',
    () async {
      var fail = true;
      final repo = FakeAdminRepository(
        beforeOperation: (op) async {
          if (op == 'save' && fail) throw StateError('합성 실패');
        },
      );
      await expectLater(repo.save('super-admin', rule('r')), throwsStateError);
      expect(repo.find('r'), isNull);
      expect(repo.history.last.result, 'failed');
      fail = false;
      await repo.save('super-admin', rule('r'));
      await expectLater(
        repo.remove('super-admin', 'school-a'),
        throwsStateError,
      );
      await repo.remove('super-admin', 'r');
      expect(repo.find('r'), isNull);
    },
  );
  test(
    'document source and relation validation do not invent server approvals',
    () async {
      final repo = FakeAdminRepository();
      final doc = AdminRecord(
        id: 'd',
        kind: AdminKind.document,
        values: {
          'name': '합成 문서',
          'institutionId': 'school-a',
          'sourceUrl': 'javascript:bad',
        },
      );
      await expectLater(repo.save('super-admin', doc), throwsStateError);
      await repo.save(
        'super-admin',
        doc.copy(
          values: {...doc.values, 'sourceUrl': 'https://example.org/document'},
        ),
      );
      await repo.apply('super-admin', 'd');
      expect(repo.find('d')!.status, 'applied');
    },
  );
}
