import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/app_shell/phone_shell.dart';
import 'package:university_path_frontend/features/records/activity/activity_page.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/personal_repository_scope.dart';
import 'package:university_path_frontend/features/records/portfolio/portfolio_workspace_repository.dart';

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
    testWidgets('activity description survives loading error and recovery with phone chrome=$phone', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repos = {for (final kind in [PersonalRecordKind.activity, PersonalRecordKind.experience]) kind: HeaderRepository(kind)};
      const description = '봉사·교내외 활동과 프로젝트·인턴·동아리 경험을 한곳에서 기록합니다.';
      await tester.pumpWidget(MaterialApp(home: PhoneChromeScope(
        active: phone,
        child: PersonalRepositoryScope(
          records: (kind) => repos[kind]!, portfolio: PortfolioWorkspaceRepository.new,
          child: const Scaffold(body: ActivityPage()),
        ),
      )));
      expect(find.text(description), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      for (final repo in repos.values) { repo.pending.complete(); }
      await tester.pumpAndSettle();
      expect(find.text(description), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
      for (final repo in repos.values) { repo.fail = false; }
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.text(description), findsOneWidget);
      expect(find.text('등록한 활동'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
