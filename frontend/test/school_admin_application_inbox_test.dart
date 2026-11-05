import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:university_path_frontend/features/admin/admin_workspace.dart';
import 'package:university_path_frontend/features/admin/school_admin_application_inbox.dart';
import 'package:university_path_frontend/features/auth/app_role.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/auth/school_workflow_session.dart';

import 'school_admin_applications_ui_test.dart' as fixture;
import 'support/auth_fixture.dart';

void main() {
  testWidgets(
    'superadmin opens the received application list from its own menu and reviews it',
    (tester) async {
      final paths = <String>[];
      final applicant = {
        ...fixture.record(),
        'applicant_id': otherId,
        'applicant': {
          'id': otherId,
          'email': 'staff@example.test',
          'display_name': '합성 담당자',
          'role': 'user',
          'account_status': 'active',
          'version': 3,
        },
      };
      final auth = AuthApi(
        cookieMode: false,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login')) {
            return fixture.reply({
              ...identityJson(role: 'super_admin'),
              'access_token': token,
            });
          }
          paths.add(request.url.path);
          expect(request.headers['X-Unipath-Owner'], userId);
          expect(request.method, 'GET');
          if (request.url.path.endsWith('/${fixture.application}')) {
            return fixture.reply(applicant);
          }
          return fixture.reply({
            'items': [applicant],
            'next_cursor': null,
          });
        }),
      );
      addTearDown(auth.close);
      final identity = await auth.authenticate(
        email: 'admin@example.test',
        password: 'synthetic password',
      );
      var path = '/admin/overview';
      await tester.pumpWidget(
        MaterialApp(
          home: SchoolWorkflowSession(
            auth: auth,
            identity: identity,
            child: StatefulBuilder(
              builder: (context, setState) => AdminWorkspace(
                role: AppRole.superAdmin,
                path: path,
                onNavigate: (value) => setState(() => path = value),
                onSignedOut: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final menu = find.byKey(const ValueKey('admin-menu-/admin/applications'));
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(path, '/admin/applications');
      expect(paths.single, '/api/v1/admin/school-admin-applications');
      expect(find.text('검증 대학 · 승인 대기'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      final refresh = find.text('접수 목록 새로고침');
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(paths.length, 2);
      await tester.ensureVisible(find.text('검증 대학 · 승인 대기'));
      await tester.tap(find.text('검증 대학 · 승인 대기'));
      await tester.pumpAndSettle();
      expect(
        paths.last,
        '/api/v1/admin/school-admin-applications/${fixture.application}',
      );
      expect(find.text('신청자 신원을 별도로 확인했습니다'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final role in [AppRole.user, AppRole.schoolAdmin]) {
    testWidgets(
      '${role.name} has no inbox destination and direct access is denied',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: AdminWorkspace(
              role: role,
              path: '/admin/applications',
              onNavigate: (_) {},
              onSignedOut: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('admin-menu-/admin/applications')),
          findsNothing,
        );
        expect(find.text('접근할 수 없습니다.'), findsOneWidget);
        expect(find.byType(SchoolAdminApplicationInbox), findsNothing);
      },
    );
  }

  testWidgets('sample inbox never pretends to receive signup drafts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminWorkspace(
          role: AppRole.superAdmin,
          path: '/admin/applications',
          onNavigate: (_) {},
          onSignedOut: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('실제 슈퍼관리자 계정으로 로그인하면'), findsOneWidget);
    expect(find.text('승인 대기'), findsNothing);
  });
}
