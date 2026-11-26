import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/admin/rule_program_review_dialog.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'rule_program_api_test.dart' as fixture;

class ReviewGateway implements ApiGateway {
  Map<String,dynamic> value = {...fixture.program(), 'status':'draft', 'approved_by':null, 'review_note':'', 'revoked_by':null, 'revocation_reason':'', 'missing_rule_ids':[], 'usable':false};
  final writes = <(String,Map<String,Object?>)>[];
  int? fail;
  @override Future<Map<String,dynamic>?> request(String method, String path, [Map<String,Object?>? body]) async {
    if (method == 'GET') return path.contains('?') ? {'items':[value], 'next_cursor':null} : {...value};
    writes.add((path, body!));
    if (fail != null) throw AuthFailure('검토 자료를 다시 확인하세요.', status:fail);
    value = {...value, 'version': (value['version'] as int)+1,
      'status':path.endsWith('/approve') ? 'approved':'revoked',
      'review_note':body['review_note'] ?? value['review_note'], 'revocation_reason':body['reason'] ?? '',
    };
    return value;
  }
}
Future<void> launch(WidgetTester tester, ReviewGateway gateway, {VoidCallback? allowed}) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: RuleProgramReviewDialog(
    gateway:gateway,institutionId:fixture.identifier,ruleSetId:fixture.identifier,ensureAllowed:allowed ?? () {},
  )));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('review-program-${fixture.identifier}')));
  await tester.pumpAndSettle();
}
Future<void> review(WidgetTester tester) async {
  for (var i=0;i<4;i++) {
    final check = find.byKey(ValueKey('program-review-check-$i'));
    await tester.ensureVisible(check); await tester.tap(check); await tester.pump();
  }
  final note = find.byKey(const ValueKey('program-review-note'));
  await tester.ensureVisible(note); await tester.enterText(note,'전체 규정 검토 완료');
  FocusManager.instance.primaryFocus?.unfocus(); await tester.pumpAndSettle();
}
void main() {
  testWidgets('review requires every attestation and note then uses captured version for approval and revocation', (tester) async {
    final gateway = ReviewGateway(); await launch(tester,gateway);
    final approve=find.byKey(const ValueKey('program-review-approve'));
    expect(tester.widget<FilledButton>(approve).onPressed,isNull);
    await review(tester); await tester.tap(approve); await tester.pumpAndSettle();
    expect(gateway.writes.single.$2, {'expected_version':2,'conditions_verified':true,'sources_verified':true,'applicability_verified':true,'complete_source_context_verified':true,'review_note':'전체 규정 검토 완료'});
    expect(find.text('실행본을 승인했습니다.'),findsOneWidget);
    final note=find.byKey(const ValueKey('program-review-note'));
    await tester.ensureVisible(note); await tester.enterText(note,'새 기준으로 대체');
    FocusManager.instance.primaryFocus?.unfocus(); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('program-review-revoke'))); await tester.pumpAndSettle();
    expect(gateway.writes.last.$2,{'expected_version':3,'reason':'새 기준으로 대체'});
    expect(find.text('실행본을 회수했습니다.'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
  testWidgets('conflicting approval preserves note and locks repeat writes until explicit reread', (tester) async {
    final gateway = ReviewGateway()..fail=409; await launch(tester,gateway); await review(tester);
    await tester.tap(find.byKey(const ValueKey('program-review-approve'))); await tester.pumpAndSettle();
    expect(gateway.writes,hasLength(1));
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('program-review-approve'))).onPressed,isNull);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('program-review-note'))).controller!.text,'전체 규정 검토 완료');
    expect(find.text('선택 실행본 다시 읽기'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
  testWidgets('permission loss hides reviewed contents and does not submit', (tester) async {
    var active=true; final gateway=ReviewGateway();
    await launch(tester,gateway,allowed:(){if(!active) throw const AuthFailure('권한이 변경되었습니다.',status:403);});
    await review(tester); active=false;
    await tester.tap(find.byKey(const ValueKey('program-review-approve'))); await tester.pumpAndSettle();
    expect(gateway.writes,isEmpty);
    expect(find.byKey(const ValueKey('program-review-approve')),findsNothing);
    expect(find.text('권한이 변경되었습니다.'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
