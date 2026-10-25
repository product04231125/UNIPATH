import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:university_path_frontend/features/admin/school_admin_applications_dialog.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';

import 'school_admin_applications_ui_test.dart' as fixture;
import 'support/auth_fixture.dart';

void main() {
  testWidgets(
    'school and status filters keep owner transport reset cursors and hide stale rows on failure',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const secondSchool = '00000000-0000-4000-8000-000000000099';
      const cursor = '00000000-0000-4000-8000-000000000088';
      var fail = false;
      final calls = <http.Request>[];
      final auth = AuthApi(
        cookieMode: false,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login')) {
            return fixture.reply({
              ...identityJson(role: 'super_admin'),
              'access_token': token,
            });
          }
          calls.add(request);
          if (fail) {
            return http.Response(
              '{}',
              503,
              headers: {'content-type': 'application/json'},
            );
          }
          final school =
              request.url.queryParameters['institution_id'] ?? fixture.school;
          return fixture.reply({
            'items': [
              {
                ...fixture.record(),
                'id': request.url.queryParameters['cursor'] == null
                    ? fixture.application
                    : '00000000-0000-4000-8000-000000000004',
                'institution_id': school,
                'institution_name': school == secondSchool
                    ? '두 번째 대학'
                    : '검증 대학',
                'applicant_id': otherId,
                'applicant': {
                  'id': otherId,
                  'email': 'staff@example.test',
                  'display_name': '신청 담당자',
                  'role': 'user',
                  'account_status': 'active',
                  'version': 1,
                },
              },
            ],
            'next_cursor': request.url.queryParameters['cursor'] == null
                ? cursor
                : null,
          });
        }),
      );
      addTearDown(auth.close);
      final identity = await auth.authenticate(
        email: 'admin@example.test',
        password: 'synthetic long password',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SchoolAdminApplicationsDialog(
                auth: auth,
                identity: identity,
                inline: true,
                reviewSchools: const [
                  SelectOption(fixture.school, '검증 대학'),
                  SelectOption(secondSchool, '두 번째 대학'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final schoolFilter = find.byKey(
        const ValueKey('application-school-filter'),
      );
      tester
          .widget<AnchoredSelectField<String>>(schoolFilter)
          .onChanged(secondSchool);
      await tester.pumpAndSettle();
      expect(calls.last.url.queryParameters['institution_id'], secondSchool);
      expect(calls.last.url.queryParameters['cursor'], isNull);
      expect(find.text('검증 대학 · 승인 대기'), findsNothing);
      expect(find.text('두 번째 대학 · 승인 대기'), findsOneWidget);
      await tester.tap(find.text('더 보기'));
      await tester.pumpAndSettle();
      expect(calls.last.url.queryParameters['cursor'], cursor);
      expect(calls.last.url.queryParameters['institution_id'], secondSchool);
      final statusFilter = find.byWidgetPredicate(
        (w) => w is AnchoredSelectField<String> && w.label == '신청 상태',
      );
      tester
          .widget<AnchoredSelectField<String>>(statusFilter)
          .onChanged('pending');
      await tester.pumpAndSettle();
      expect(calls.last.url.queryParameters['cursor'], isNull);
      expect(calls.last.url.queryParameters['status'], 'pending');
      expect(calls.last.url.queryParameters['institution_id'], secondSchool);
      fail = true;
      tester
          .widget<AnchoredSelectField<String>>(schoolFilter)
          .onChanged(fixture.school);
      await tester.pumpAndSettle();
      expect(find.text('두 번째 대학 · 승인 대기'), findsNothing);
      expect(
        tester.widget<AnchoredSelectField<String>>(schoolFilter).value,
        fixture.school,
      );
      fail = false;
      await tester.tap(find.text('신청 이력 다시 읽기'));
      await tester.pumpAndSettle();
      expect(calls.last.url.queryParameters['institution_id'], fixture.school);
      expect(calls.last.url.queryParameters['status'], 'pending');
      expect(find.text('검증 대학 · 승인 대기'), findsOneWidget);
      expect(
        calls.every(
          (r) => r.headers['X-Unipath-Owner'] == userId && r.method == 'GET',
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
