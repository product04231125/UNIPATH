import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/graduation/personal_requirement_panel.dart';
import 'package:university_path_frontend/features/graduation/personal_calculation_controller.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/personal_repository_scope.dart';
import 'package:university_path_frontend/features/records/remote_personal_record_repository.dart';
import 'package:university_path_frontend/features/records/portfolio/remote_portfolio_workspace_repository.dart';

import 'support/calculation_gateway.dart';
import 'support/personal_workspace_fixture.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'rule form sends explicit minimum and retries same evaluation then restores saved criterion',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gateway = CalculationGateway()..loseResponse = true;
      final controller = PersonalCalculationController(
        gateway.api,
        ensureOpen: () {},
      );
      addTearDown(controller.dispose);
      Widget page() => MaterialApp(
        home: PersonalRepositoryScope(
          records: (kind) => RemotePersonalRecordRepository(
            gateway.api,
            kind,
            ensureOpen: () {},
          ),
          portfolio: () => RemotePortfolioWorkspaceRepository(
            gateway.api,
            ensureOpen: () {},
          ),
          calculations: controller,
          child: Scaffold(
            body: SingleChildScrollView(
              child: PersonalRequirementPanel(
                curriculumId: fixtureId(PersonalRecordKind.personalCurriculum),
                rule: PersonalRecord(
                  id: calculationRuleId(0),
                  version: 1,
                  values: const {'title': '합성 규칙'},
                ),
                metadataDirty: false,
                onChanged: (_) {},
                onBusy: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(gateway.posted, isEmpty);
      await tester.tap(find.text('조건 미지정 · 확인 필요'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, '최소 학점'));
      await tester.pumpAndSettle();
      final minimum = find.widgetWithText(TextFormField, '최소 학점');
      await tester.enterText(minimum, '120');
      await tester.tap(find.text('계산 조건 저장·계산'));
      await tester.pumpAndSettle();
      expect(gateway.posted, hasLength(1));
      expect(
        (gateway.posted.single['calculations'] as List)
            .single['condition']['minimum'],
        '120',
      );
      expect(find.textContaining('입력과 기존 결과를 보존'), findsOneWidget);
      await tester.tap(find.text('같은 계산 요청으로 다시 확인'));
      await tester.pumpAndSettle();
      expect(gateway.posted, hasLength(2));
      expect(gateway.posted[0], gateway.posted[1]);
      expect(find.textContaining('현재 확인 필요 / 필요 확인 필요'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(minimum).initialValue, '120');
      expect(gateway.posted, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );
}
