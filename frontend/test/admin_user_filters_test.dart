import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/admin/admin_fixture.dart';
import 'package:university_path_frontend/features/admin/admin_models.dart';
import 'package:university_path_frontend/features/admin/admin_repository.dart';
import 'package:university_path_frontend/features/auth/app_role.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';

import 'admin_list_panel_test.dart' as harness;

void main() {
  testWidgets(
    'roles status email and school scope filter the global user list together',
    (tester) async {
      final repo = FakeAdminRepository(
        seed: [
          ...adminFixture(),
          AdminRecord(
            id: 'other-student',
            kind: AdminKind.account,
            values: {
              'name': '정지 학생',
              'role': 'user',
              'accountStatus': 'suspended',
              'email': 'MixedCase@example.test',
            },
          ),
        ],
      );
      await harness.showWorkspace(
        tester,
        repo,
        AppRole.superAdmin,
        '/admin/accounts',
      );
      final list = find.byKey(const ValueKey('admin-section-account'));
      Finder text(String value) =>
          find.descendant(of: list, matching: find.text(value));
      void role(String value) => tester
          .widget<AnchoredSelectField<String>>(
            find.byKey(const ValueKey('admin-account-role')),
          )
          .onChanged(value);
      final search = find.byKey(
        const ValueKey('admin-search-school-a-account'),
      );
      role('user');
      await tester.pumpAndSettle();
      expect(text('합성 사용자'), findsOneWidget);
      expect(text('정지 학생'), findsOneWidget);
      expect(text('합성 학교 담당'), findsNothing);
      await tester.enterText(search, 'mixedCASE@EXAMPLE.test');
      await tester.pumpAndSettle();
      expect(text('정지 학생'), findsOneWidget);
      expect(text('합성 사용자'), findsNothing);
      tester
          .widget<AnchoredSelectField<String>>(
            find.byKey(const ValueKey('admin-status-account')),
          )
          .onChanged('active');
      await tester.pumpAndSettle();
      expect(text('정지 학생'), findsNothing);
      tester
          .widget<AnchoredSelectField<String>>(
            find.byKey(const ValueKey('admin-status-account')),
          )
          .onChanged('');
      role('school_admin');
      await tester.enterText(search, '합성 대학 A');
      await tester.pumpAndSettle();
      expect(text('합성 학교 담당'), findsOneWidget);
      expect(
        find.descendant(
          of: list,
          matching: find.textContaining('관리 범위: 합성 대학 A'),
        ),
        findsOneWidget,
      );
      await repo.revoke('super-admin', 'scope-a', '범위 갱신 검증');
      await tester.pumpAndSettle();
      expect(text('합성 학교 담당'), findsNothing);
      expect(find.textContaining('검색·필터에 맞는 항목'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
