import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/auth/local_data_owner.dart';
import 'package:university_path_frontend/features/records/personal_repository_scope.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/remote_personal_record_repository.dart';
import 'package:university_path_frontend/features/records/portfolio/remote_portfolio_workspace_repository.dart';
import 'package:university_path_frontend/features/records/course/course_page.dart';
import 'package:university_path_frontend/features/graduation/personal_graduation_workspace.dart';

import 'support/auth_fixture.dart';
import 'support/personal_gateway.dart';
import 'support/personal_workspace_fixture.dart';

Widget scope(PersonalGateway gateway, Widget child, {double scale = 1}) =>
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: PersonalRepositoryScope(
        records: (kind) => RemotePersonalRecordRepository(
          gateway.api,
          kind,
          ensureOpen: () {},
        ),
        portfolio: () =>
            RemotePortfolioWorkspaceRepository(gateway.api, ensureOpen: () {}),
        child: Scaffold(body: child),
      ),
    );
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalDataOwner.currentUserId = otherId;
  });
  tearDown(() => LocalDataOwner.currentUserId = null);
  for (final size in [const Size(1440, 900), const Size(480, 520)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'server course editor preserves input/version on conflict at $size scale=$scale',
        (tester) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final gateway = PersonalGateway()..failWrites = true;
          await tester.pumpWidget(
            scope(gateway, const CoursePage(showMockData: false), scale: scale),
          );
          await tester.pumpAndSettle();
          expect(find.text('합성 course'), findsOneWidget);
          expect(find.textContaining('계정 서버 개인 기록'), findsWidgets);
          final edit = find.widgetWithText(TextButton, '수정');
          await tester.ensureVisible(edit);
          await tester.tap(edit);
          await tester.pumpAndSettle();
          final title = find.byType(TextFormField).first;
          await tester.ensureVisible(title);
          await tester.enterText(title, '충돌 후 유지할 이름');
          final save = find.widgetWithText(FilledButton, '내 기록에 저장');
          await tester.ensureVisible(save);
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(find.textContaining('입력은 유지됩니다'), findsOneWidget);
          expect(
            tester.widget<TextFormField>(title).controller!.text,
            '충돌 후 유지할 이름',
          );
          final request = gateway.calls.singleWhere(
            (call) => call.$1 == 'PATCH',
          );
          expect(
            request.$2,
            'me/course-records/${fixtureId(PersonalRecordKind.course)}',
          );
          expect(request.$3!['expected_version'], 1);
          expect(request.$3!.containsKey('owner_id'), isFalse);
          expect(request.$3!.containsKey('client_id'), isFalse);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  testWidgets(
    'graduation selectors use same server repositories and never evaluate free text',
    (tester) async {
      final gateway = PersonalGateway();
      await tester.pumpWidget(
        scope(gateway, PersonalGraduationWorkspace(onBack: () {})),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '개인 규칙'));
      await tester.pumpAndSettle();
      expect(find.text('합성 personalGraduationRule'), findsOneWidget);
      expect(
        gateway.calls.any(
          (call) => call.$2.startsWith('me/personal-curricula?'),
        ),
        isTrue,
      );
      expect(
        gateway.calls.any(
          (call) => call.$2.startsWith('me/personal-curriculum-courses?'),
        ),
        isTrue,
      );
      expect(
        gateway.calls.any(
          (call) => call.$2.startsWith('me/achievement-records?'),
        ),
        isTrue,
      );
      expect(
        gateway.calls.any(
          (call) => call.$2.startsWith('me/personal-evaluations'),
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
