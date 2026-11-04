import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/auth/guest_preview_scope.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';

void main() {
  test('planning repository blocks writes in guest preview', () async {
    final repo = PlanningRepository(writer: (key, value) async => true);
    addTearDown(repo.dispose);
    repo.blockWrites(GuestPreviewScope.blockedMessage);
    await expectLater(
      repo.saveProfile(const PlanningProfile(school: 'x')),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          GuestPreviewScope.blockedMessage,
        ),
      ),
    );
  });

  testWidgets('guest preview scope reports active flag and snackbar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GuestPreviewScope(
          active: true,
          institutionId: 'school-a',
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => GuestPreviewScope.showBlockedMessage(context),
                child: const Text('막기'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(GuestPreviewScope.isActive(tester.element(find.text('막기'))), isTrue);
    expect(
      GuestPreviewScope.previewInstitutionId(tester.element(find.text('막기'))),
      'school-a',
    );
    await tester.tap(find.text('막기'));
    await tester.pump();
    expect(find.text(GuestPreviewScope.blockedMessage), findsOneWidget);
  });
}
