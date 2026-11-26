import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:university_path_frontend/features/admin/school_admin_applications_dialog.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/shared/widgets/surface_card.dart';

import 'school_admin_applications_ui_test.dart' as fixture;
import 'support/auth_fixture.dart';

void main() {
  testWidgets('empty application list shows placeholder SurfaceCards', (
    tester,
  ) async {
    final auth = AuthApi(
      cookieMode: false,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return fixture.reply({...identityJson(), 'access_token': token});
        }
        return fixture.reply({'items': [], 'next_cursor': null});
      }),
    );
    addTearDown(auth.close);
    final identity = await auth.authenticate(
      email: 'synthetic@example.test',
      password: 'synthetic long password',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchoolAdminApplicationsDialog(
            auth: auth,
            identity: identity,
            inline: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('application-empty-cards')), findsOneWidget);
    expect(find.text('예시 · 대기'), findsOneWidget);
    expect(find.textContaining('신청 내역이 없습니다'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('application-empty-cards')),
        matching: find.byType(SurfaceCard),
      ),
      findsNWidgets(2),
    );
  });
}
