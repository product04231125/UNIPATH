import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/auth/login_page.dart';

void main() {
  test('debug sample login flag defaults to off', () {
    expect(kShowDebugSampleLogin, isFalse);
  });

  testWidgets('default flag hides sample entry keys on login', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(onSignedIn: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sample-student-entry')), findsNothing);
    expect(find.byKey(const Key('sample-school-admin-entry')), findsNothing);
    expect(find.byKey(const Key('sample-super-admin-entry')), findsNothing);
    expect(find.textContaining('개발용 샘플 진입'), findsNothing);
  });
}
