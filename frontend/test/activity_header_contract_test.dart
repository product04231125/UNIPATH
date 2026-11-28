import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app_shell/phone_shell.dart';
import 'package:university_path_frontend/features/records/portfolio/materials_page.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/personal_repository_scope.dart';

import 'support/memory_materials.dart';

class HeaderRepository extends PersonalRecordRepository {
  HeaderRepository(super.kind);
  final pending = Completer<void>();
  bool fail = true;
  @override Future<void> load() async {
    await pending.future;
    if (fail) throw StateError('synthetic read failure');
  }
}

void main() {
  for (final phone in [false, true]) {
    testWidgets('내 자료 header stays put through loading error and recovery with phone chrome=$phone', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repos = {for (final kind in [PersonalRecordKind.activity, PersonalRecordKind.experience, PersonalRecordKind.credential]) kind: HeaderRepository(kind)};
      const description = '봉사·교내외 활동과 프로젝트·인턴·동아리 경험을 한곳에서 기록합니다.';
      await tester.pumpWidget(MaterialApp(home: PhoneChromeScope(
        active: phone,
        child: PersonalRepositoryScope(
          records: (kind) => repos[kind]!,
          child: Scaffold(body: MaterialsPage(repository: MemoryMaterials())),
        ),
      )));
      // Title and actions render from the first frame; no description line.
      expect(find.text(description), findsNothing);
      final title = tester.getTopLeft(find.text('내 자료'));
      expect(find.byTooltip('자료 추가'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      for (final repo in repos.values) { repo.pending.complete(); }
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('내 자료')), title);
      // A record read failure keeps the page (and the files) and offers a retry.
      expect(find.textContaining('활동·자격증 기록을 읽지 못했습니다'), findsOneWidget);
      expect(find.text('다시 읽기'), findsOneWidget);
      for (final repo in repos.values) { repo.fail = false; }
      await tester.tap(find.text('다시 읽기'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('내 자료')), title);
      expect(find.textContaining('활동·자격증 기록을 읽지 못했습니다'), findsNothing);
      expect(find.text('아직 기록한 자료가 없습니다'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
