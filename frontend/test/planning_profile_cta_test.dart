import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/app_navigation.dart';
import 'package:university_path_frontend/features/planning/planning_profile_cta.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';

const _configured = PlanningProfile(
  school: '경동대학교',
  department: '컴퓨터공학과',
  admissionYear: 2026,
);

const _catalog = PlanningProfile(
  school: '경동대학교',
  department: '컴퓨터공학과',
  admissionYear: 2026,
  institutionId: 'synthetic-institution',
);

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  test('empty and missing profiles are not ready for either need', () {
    expect(
      isPlanningProfileReady(null, PlanningProfileNeed.configured),
      isFalse,
    );
    expect(
      isPlanningProfileReady(null, PlanningProfileNeed.catalogSchool),
      isFalse,
    );
    expect(
      isPlanningProfileReady(
        const PlanningProfile(),
        PlanningProfileNeed.configured,
      ),
      isFalse,
    );
    expect(
      isPlanningProfileReady(
        const PlanningProfile(),
        PlanningProfileNeed.catalogSchool,
      ),
      isFalse,
    );
  });

  test('isConfigured does not imply a catalog school UUID', () {
    expect(
      isPlanningProfileReady(_configured, PlanningProfileNeed.configured),
      isTrue,
    );
    expect(
      isPlanningProfileReady(_configured, PlanningProfileNeed.catalogSchool),
      isFalse,
    );
    expect(_configured.isConfigured, isTrue);
    expect(_configured.hasCatalogSchool, isFalse);
  });

  test('catalog UUID without names is catalog-ready but not configured', () {
    const catalogOnly = PlanningProfile(institutionId: 'synthetic-institution');
    expect(
      isPlanningProfileReady(catalogOnly, PlanningProfileNeed.catalogSchool),
      isTrue,
    );
    expect(
      isPlanningProfileReady(catalogOnly, PlanningProfileNeed.configured),
      isFalse,
    );
    expect(catalogOnly.hasCatalogSchool, isTrue);
    expect(catalogOnly.isConfigured, isFalse);
  });

  test('full catalog profile is ready for both needs', () {
    expect(
      isPlanningProfileReady(_catalog, PlanningProfileNeed.configured),
      isTrue,
    );
    expect(
      isPlanningProfileReady(_catalog, PlanningProfileNeed.catalogSchool),
      isTrue,
    );
  });

  test('settings CTA copy matches register versus edit', () {
    expect(planningProfileSettingsCtaLabel(ready: false), '설정에서 학업 프로필 등록');
    expect(planningProfileSettingsCtaLabel(ready: true), '설정에서 학업 프로필 수정');
    expect(
      planningProfileSettingsMessage(ready: false),
      '설정에서 학업 프로필을 등록하면 이 화면에 자동으로 사용합니다.',
    );
    expect(
      planningProfileSettingsMessage(ready: true),
      '학업 프로필 변경은 설정에서만 할 수 있습니다.',
    );
  });

  test('openSettings selects the existing /settings menu tab', () {
    expect(AppLocation.settingsPath, '/settings');
    expect(
      AppLocation.settingsMenu,
      AppLocation.menuPaths.indexOf('/settings'),
    );
    expect(AppLocation.settingsMenu, greaterThanOrEqualTo(0));
    var opened = -1;
    AppLocation.openSettings((index) => opened = index);
    expect(opened, AppLocation.settingsMenu);
    opened = -1;
    AppLocation.bindOpenSettings((index) => opened = index)();
    expect(opened, AppLocation.settingsMenu);
  });

  testWidgets('unready CTA is primary and opens settings', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      _host(
        PlanningProfileSettingsCta(
          need: PlanningProfileNeed.catalogSchool,
          profile: _configured,
          onOpenSettings: AppLocation.bindOpenSettings((_) => opened += 1),
        ),
      ),
    );
    expect(find.byKey(planningProfileSettingsCtaKey), findsOneWidget);
    expect(find.text('설정에서 학업 프로필을 등록하면 이 화면에 자동으로 사용합니다.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '설정에서 학업 프로필 등록'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '설정에서 학업 프로필 수정'), findsNothing);
    await tester.tap(find.text('설정에서 학업 프로필 등록'));
    expect(opened, 1);
  });

  testWidgets('ready CTA is secondary edit and opens settings', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      _host(
        PlanningProfileSettingsCta(
          need: PlanningProfileNeed.catalogSchool,
          profile: _catalog,
          onOpenSettings: AppLocation.bindOpenSettings((_) => opened += 1),
        ),
      ),
    );
    expect(find.text('학업 프로필 변경은 설정에서만 할 수 있습니다.'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, '설정에서 학업 프로필 수정'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, '설정에서 학업 프로필 등록'), findsNothing);
    await tester.tap(find.text('설정에서 학업 프로필 수정'));
    expect(opened, 1);
  });
}
