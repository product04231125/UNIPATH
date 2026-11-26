import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/planning/planning_repository.dart';
import 'package:university_path_frontend/features/planning/remote_planning_repository.dart';
import 'package:university_path_frontend/features/settings/settings_page.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';

import 'support/auth_fixture.dart';

class SettingsCatalogServer implements ApiGateway {
  final writes = <Map<String, Object?>>[];
  AuthFailure? profileFailure;
  final profile = <String, dynamic>{
    'owner_id': userId,
    'version': 0,
    'official': false,
  };

  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    if (path.startsWith('catalog/academic/options')) {
      return {
        'institution_id': otherId,
        'departments': [
          {'id': otherId, 'name': '검증 학과'},
        ],
        'tracks': [
          {'id': 'registered-track', 'name': '학교 등록 경로'},
        ],
        'curricula': [
          for (final year in [2018, 2019, 2020, 2021, 2025, 2026])
            {
              'id': 'published-$year',
              'name': '$year학년도 게시 교육과정',
              'revision': 1,
              'scope': {
                'clauses': [{}],
              },
            },
        ],
      };
    }
    if (path.startsWith('me/academic-')) {
      return {
        'owner_id': userId,
        'version': 1,
        'workspace_version': 1,
        'institution_id': otherId,
        'contexts': [],
        'issues': [],
        'documents': [],
        'digest': 'a' * 64,
        'changes': [],
      };
    }
    if (path.startsWith('catalog/')) {
      return {
        'items': [_catalogItem(path)],
        'next_cursor': null,
      };
    }
    if (path == 'me/planning-profile') {
      if (method == 'PATCH') {
        writes.add(Map.of(body!));
        if (profileFailure != null) throw profileFailure!;
        if (body['expected_version'] != profile['version']) {
          throw const AuthFailure('다른 변경이 있습니다.', status: 409);
        }
        profile.addAll(body);
        profile['version'] = (profile['version'] as int) + 1;
      }
      return {...profile};
    }
    if (path.startsWith('me/events')) {
      return {'items': <Map<String, dynamic>>[], 'next_cursor': null};
    }
    throw StateError('Unexpected route $method $path');
  }

  Map<String, Object?> _catalogItem(String path) {
    final institutions = path.startsWith('catalog/institutions');
    final departments = path.startsWith('catalog/departments');
    return {
      'id': otherId,
      'version': 1,
      'name': institutions
          ? '검증 대학'
          : departments
          ? '검증 학과'
          : '검증 과정',
      'created_at': '2026-10-21T00:00:00Z',
      'updated_at': '2026-10-21T00:00:00Z',
      'institution_id': otherId,
      'department_id': otherId,
      'code': 'synthetic',
      'year': 2026,
    };
  }
}

Future<void> choose(WidgetTester tester, String from, String to) async {
  await tester.ensureVisible(find.text(from));
  await tester.tap(find.text(from));
  await tester.pumpAndSettle();
  await tester.tap(find.text(to).last);
  await tester.pumpAndSettle();
}

Future<void> saveSettings(WidgetTester tester) async {
  final save = find.text('저장');
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<RemotePlanningRepository> pumpSettings(
    WidgetTester tester,
    SettingsCatalogServer server, {
    StudentApi? api,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final studentApi = api ?? StudentApi(server, ownerId: userId);
    final repository = RemotePlanningRepository(studentApi);
    await repository.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(repository: repository, studentApi: studentApi),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets(
    'registered school track opens academic context selection in place',
    (tester) async {
      final server = SettingsCatalogServer();
      server.profile.addAll({
        'institution_id': otherId,
        'department_id': otherId,
        'school': '검증 대학',
        'department': '검증 학과',
        'admission_year': 2026,
        'track': '기존 개인 경로',
        'curriculum_id': otherId,
      });
      final repository = await pumpSettings(tester, server);
      addTearDown(repository.dispose);
      final field = find.byKey(const Key('settings-school-track'));
      expect(tester.widget<InputDecorator>(field).decoration.enabled, isTrue);
      expect(
        find.byWidgetPredicate(
          (w) => w is AnchoredSelectField<String?> && w.label == '교육과정',
        ),
        findsNothing,
      );
      expect(find.textContaining('연결 전입니다'), findsNothing);
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(find.text('주전공·추가 전공 학업 기준'), findsOneWidget);
      final trackSelect = tester.widget<AnchoredSelectField<String>>(
        find.byWidgetPredicate(
          (w) => w is AnchoredSelectField<String> && w.label == '이수 경로',
        ),
      );
      expect(trackSelect.value, '');
      expect(
        trackSelect.options.any((option) => option.label == '학교 등록 경로'),
        isTrue,
      );
      expect(repository.profile.track, '기존 개인 경로');
      expect(server.writes, isEmpty);
      final curriculumSelect = tester.widget<AnchoredSelectField<String>>(
        find.byWidgetPredicate(
          (w) => w is AnchoredSelectField<String> && w.label == '교육과정',
        ),
      );
      expect(
        curriculumSelect.options.where((option) => option.value.isNotEmpty),
        hasLength(6),
      );
      expect(
        curriculumSelect.options.map((option) => option.value),
        containsAll(['published-2018', 'published-2026']),
      );
      await tester.tap(find.text('닫기').last);
      await tester.pumpAndSettle();
      await saveSettings(tester);
      expect(repository.profile.curriculumId, otherId);
      expect(server.writes.single['curriculum_id'], otherId);
      expect(tester.takeException(), isNull);
    },
  );

  for (final track in <String?>[null, 'school-specific-track']) {
    testWidgets(
      'school track stays read-only and survives settings retry: $track',
      (tester) async {
        final server = SettingsCatalogServer()..profile['track'] = track;
        final repository = await pumpSettings(tester, server);
        addTearDown(repository.dispose);
        final field = find.byKey(const Key('settings-school-track'));
        expect(field, findsOneWidget);
        expect(
          find.descendant(
            of: field,
            matching: find.text(track ?? '저장된 이수 경로 없음'),
          ),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (w) => w is AnchoredSelectField<String?> && w.label == '이수경로',
          ),
          findsNothing,
        );
        expect(find.text('단일전공'), findsNothing);
        expect(find.text('복수전공'), findsNothing);
        expect(
          tester.getTopLeft(field).dy,
          lessThan(tester.getTopLeft(find.text('개인 계획')).dy),
        );
        final year = find.byWidgetPredicate(
          (w) => w is AnchoredSelectField<int?> && w.label == '개인 계획 학년',
        );
        tester.widget<AnchoredSelectField<int?>>(year).onChanged(4);
        await tester.pumpAndSettle();
        server.profileFailure = const AuthFailure('합성 저장 실패', status: 422);
        await saveSettings(tester);
        expect(find.textContaining('합성 저장 실패'), findsOneWidget);
        expect(tester.widget<AnchoredSelectField<int?>>(year).value, 4);
        expect(server.writes.single['track'], track);
        server.profileFailure = null;
        await saveSettings(tester);
        expect(repository.profile.track, track);
        expect(repository.profile.academicYearOverride, 4);
        expect(server.writes.last['track'], track);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('empty server settings start from registered school catalog', (
    tester,
  ) async {
    final repository = await pumpSettings(tester, SettingsCatalogServer());
    expect(find.textContaining('목록에 없으면 만들지 않습니다'), findsOneWidget);
    expect(
      find.textContaining('등록 학교 목록에 없으면 여기서 교육과정·규칙을 직접 만듭니다.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, '개인 교육과정 작업'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '개인 교육과정 작업'), findsNothing);
    expect(find.text('학교 선택'), findsOneWidget);
    expect(find.text('목록에 없는 학교 직접 입력'), findsNothing);
    repository.dispose();
  });

  testWidgets('catalog school selection stores ids and clearing removes them', (
    tester,
  ) async {
    final server = SettingsCatalogServer();
    final repository = await pumpSettings(tester, server);
    await choose(tester, '학교 선택', '검증 대학');
    await choose(tester, '학과 선택', '검증 학과');
    await saveSettings(tester);
    expect(repository.profile.institutionId, otherId);
    expect(repository.profile.departmentId, otherId);
    expect(repository.profile.curriculumId, isNull);
    expect(repository.profile.school, '검증 대학');
    expect(repository.profile.department, '검증 학과');
    expect(find.text('등록된 학교 · 검증 대학 · 검증 학과'), findsOneWidget);
    await choose(tester, '검증 대학', '학교 선택');
    await saveSettings(tester);
    expect(repository.profile.school, isEmpty);
    expect(repository.profile.institutionId, isNull);
    expect(repository.profile.departmentId, isNull);
    expect(repository.profile.curriculumId, isNull);
    expect(server.profile['institution_id'], isNull);
    repository.dispose();
  });

  testWidgets('admission year is a searchable select up to the current year', (
    tester,
  ) async {
    final repository = await pumpSettings(tester, SettingsCatalogServer());
    final current = DateTime.now().year;
    final field = find.byKey(const Key('settings-admission-year-select'));
    expect(field, findsOneWidget);
    final select = tester.widget<AnchoredSelectField<int?>>(field);
    expect(select.searchable, isTrue);
    expect(select.options.map((option) => option.value), contains(null));
    expect(select.options.map((option) => option.value), contains(1900));
    expect(select.options.map((option) => option.value), contains(current));
    expect(
      select.options.map((option) => option.value),
      isNot(contains(current + 1)),
    );
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('select-search-input')),
      '$current',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, '$current년'));
    await tester.pumpAndSettle();
    await saveSettings(tester);
    expect(repository.profile.admissionYear, current);
    repository.dispose();
  });

  testWidgets('personal school names stay without becoming a catalog school', (
    tester,
  ) async {
    final server = SettingsCatalogServer();
    final studentApi = StudentApi(server, ownerId: userId);
    final repository = RemotePlanningRepository(studentApi);
    await repository.load();
    await repository.saveProfile(
      PlanningProfile(
        school: '미등록 대학',
        department: '미등록 학과',
        version: repository.profile.version,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(repository: repository, studentApi: studentApi),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('개인 설정 · 미등록 대학 · 미등록 학과'), findsOneWidget);
    expect(find.text('학교 선택'), findsOneWidget);
    await saveSettings(tester);
    expect(repository.profile.school, '미등록 대학');
    expect(repository.profile.institutionId, isNull);
    repository.dispose();
  });

  testWidgets('saving settings releases keyboard focus from profile inputs', (
    tester,
  ) async {
    final write = Completer<bool>();
    final repository = PlanningRepository(writer: (_, _) => write.future);
    addTearDown(repository.dispose);
    await repository.load();
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsPage(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '검증 대학');
    final input = tester.widget<EditableText>(find.byType(EditableText).first);
    expect(input.focusNode.hasFocus, isTrue);

    // Invoke the same save action without moving focus through a pointer tap.
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '저장'))
        .onPressed!();
    await tester.pump();
    final focusedDuringSave = input.focusNode.hasFocus;
    write.complete(true);
    await tester.pumpAndSettle();
    expect(focusedDuringSave, isFalse);
    expect(repository.profile.school, '검증 대학');
    expect(find.text('저장되었습니다.'), findsOneWidget);
  });
}
