import 'dart:async';
import 'package:university_path_frontend/features/api/job_analysis_api.dart';
import 'package:university_path_frontend/features/api/job_analysis_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/features/records/personal_repository_scope.dart';
import 'package:university_path_frontend/features/records/portfolio/portfolio_workspace_repository.dart';
import 'package:university_path_frontend/features/records/portfolio/job_analysis_page.dart';

const id = '10000000-0000-4000-8000-000000000001';
class Records extends PersonalRecordRepository {
  Records(super.kind);
  @override Future<void> load() async {}
  @override List<PersonalRecord> get records => kind == PersonalRecordKind.activity
    ? [PersonalRecord(id: id, version: 3, values: {'title': '선택 봉사'})] : [];
}
class Gateway implements ApiGateway {
  final bodies = <Map<String,Object?>>[];
  final pending = <Completer<Map<String,dynamic>?>>[];
  @override Future<Map<String,dynamic>?> request(String method, String path, [Map<String,Object?>? body]) {
    expect(method, 'POST'); expect(path, 'me/job-analyses');
    bodies.add(body!);
    final c = Completer<Map<String,dynamic>?>(); pending.add(c); return c.future;
  }
}
Widget host(StudentApi api) => MaterialApp(home: PersonalRepositoryScope(
  records: (kind) => Records(kind), portfolio: () => PortfolioWorkspaceRepository(),
  child: Scaffold(body: JobAnalysisPage(studentApi: api)),
));
Future<void> prepare(WidgetTester tester) async {
  await tester.enterText(find.byKey(const ValueKey('job-posting-text')), '공고 본문');
  final selected = find.byKey(const ValueKey('job-record-activity/$id'));
  await tester.ensureVisible(selected); await tester.tap(selected); await tester.pump();
}
Future<void> run(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('job-analysis-run'));
  await tester.ensureVisible(button); await tester.tap(button); await tester.pump();
}
void main() {
  test('response cannot cite an unselected record version', () async {
    final gateway = Gateway();
    final pending = JobAnalysisApi(gateway).analyze(JobAnalysisRequest(postingText: '공고 본문', records: [PersonalEvidenceSelection(kind:'activity', recordId:id, expectedVersion:3)]));
    final check = expectLater(pending, throwsFormatException);
    gateway.pending.single.complete({'analysis_id':id,'status':'completed','reason':'compared_with_personal_evidence','official':false,'missing_fields':[],'comparisons':[{
      'requirement_id':id,'priority':'required','requirement':'요건','status':'supported',
      'posting_evidence':{'start':0,'end':2,'excerpt':'공고'},
      'personal_evidence':[{'kind':'activity','record_id':id,'version':4,'excerpt':'선택 봉사'}], 'explanation':'잘못된 버전',
    }]});
    await check;
  });
  testWidgets('a late analysis never appears in a replaced owner session', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final old = Gateway();
    await tester.pumpWidget(host(StudentApi(old, ownerId:id)));
    await tester.pumpAndSettle(); await prepare(tester); await run(tester);
    await tester.pumpWidget(host(StudentApi(Gateway(), ownerId:id)));
    await tester.pumpAndSettle();
    old.pending.single.complete({'analysis_id':id,'status':'not_configured','reason':'analyzer_not_configured','official':false,'comparisons':[],'missing_fields':[]});
    await tester.pumpAndSettle();
    expect(find.text('상태: 분석기 연결 전'), findsNothing);
    expect(tester.widget<TextFormField>(find.byKey(const ValueKey('job-posting-text'))).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('text analysis pins selected versions, blocks duplicates, and preserves retry input', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = Gateway();
    await tester.pumpWidget(host(StudentApi(gateway, ownerId: id)));
    await tester.pumpAndSettle(); await prepare(tester); await run(tester);
    final body = Map<String, Object?>.of(gateway.bodies.single);
    // The current merge contract may serialize the default; no consent is inferred.
    expect(body.remove('external_processing_consent'), anyOf(isNull, isFalse));
    expect(body, {'posting_text': '공고 본문', 'records': [{'kind':'activity','record_id':id,'expected_version':3}]});
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('job-analysis-run'))).onPressed, isNull);
    gateway.pending.single.completeError(const AuthFailure('공고를 확인하세요.', status:422, fields:['posting_text']));
    await tester.pumpAndSettle();
    expect(find.text('공고 텍스트를 확인하세요.'), findsOneWidget);
    expect(tester.widget<TextFormField>(find.byKey(const ValueKey('job-posting-text'))).controller!.text, '공고 본문');
    await run(tester);
    expect(gateway.bodies, hasLength(2));
    gateway.pending.last.complete({'analysis_id':id,'status':'not_configured','reason':'analyzer_not_configured','official':false,'comparisons':[],'missing_fields':[]});
    await tester.pumpAndSettle();
    expect(find.text('상태: 분석기 연결 전'), findsOneWidget);
    expect(find.textContaining('서버 분석기가 아직 연결되지 않았습니다'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('completed analysis renders only received comparisons and selected evidence', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = Gateway();
    await tester.pumpWidget(host(StudentApi(gateway, ownerId:id)));
    await tester.pumpAndSettle(); await prepare(tester); await run(tester);
    gateway.pending.single.complete({'analysis_id':id,'status':'completed','reason':'compared_with_personal_evidence','official':false,'missing_fields':[], 'comparisons':[{
      'requirement_id':id, 'priority':'required','requirement':'공고 조건',
      'posting_evidence':{'start':0,'end':2,'excerpt':'공고'},'status':'supported',
      'personal_evidence':[{'kind':'activity','record_id':id,'version':3,'excerpt':'선택 봉사'}],
      'explanation':'서버가 반환한 비교 설명',
    }]});
    await tester.pumpAndSettle();
    expect(find.text('상태: 분석 완료'), findsOneWidget);
    expect(find.text('서버가 반환한 비교 설명'), findsOneWidget);
    expect(find.text('선택 기록 근거: 선택 봉사'), findsOneWidget);
    expect(find.text('근거: 받은 근거 없음'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
