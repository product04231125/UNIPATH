import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/admin/school_knowledge_edit_dialogs.dart';
import 'package:university_path_frontend/features/api/school_knowledge_api.dart';
import 'package:university_path_frontend/features/api/school_knowledge_models.dart';
import 'package:university_path_frontend/features/api/student_api_models.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/shared/widgets/input_dialog.dart';
import 'package:university_path_frontend/shared/widgets/anchored_select_field.dart';
import 'school_knowledge_api_test.dart' as fixture;
class Gateway implements ApiGateway {
  final writes = <(String,String,Map<String,Object?>?)>[];
  int? fail;
  @override Future<Map<String,dynamic>?> request(String method,String path,[Map<String,Object?>? body]) async {
    writes.add((method,path,body));
    if(fail!=null)throw AuthFailure('최신 자료 확인 필요',status:fail);
    if(method=='DELETE')return null;
    if(method=='POST')return fixture.header();
    return {'knowledge_document_id':fixture.document,'version':4,'page':1,'page_hash':'b'*64,'is_blank':body!['is_blank'],
      'parts':[for(final part in body['parts'] as List) {...part as Map,'id':fixture.chunk,'part_index':0,'part_count':1,'character_start':0,'character_end':(part['content'] as String).runes.length,'content_hash':'c'*64}]};
  }
}
Future<void> launch(WidgetTester tester,Widget dialog)async{
  await tester.binding.setSurfaceSize(const Size(1440,1100));addTearDown(()=>tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(context)=>TextButton(onPressed:()=>showInputDialog<bool>(context:context,builder:(_)=>dialog),child:const Text('열기'))))));
  await tester.tap(find.text('열기'));await tester.pumpAndSettle();
}
Future<void> enter(WidgetTester tester,String key,String text)async{
  final field=find.byKey(ValueKey(key));await tester.ensureVisible(field);await tester.enterText(field,text);await tester.pump();
}
void main(){
  testWidgets('deleting a draft page requires confirmation and the captured parent version', (tester)async{
    final gateway=Gateway();
    await launch(tester,SchoolKnowledgePageEditor(api:SchoolKnowledgeAdminApi(gateway),document:SchoolKnowledgeView.fromJson(fixture.header()),page:1,
      initial:SchoolKnowledgePageView(knowledgeDocumentId:fixture.document,version:3,page:1,pageHash:'b'*64,isBlank:true,parts:[])));
    await tester.tap(find.text('이 페이지 삭제'));await tester.pumpAndSettle();
    expect(gateway.writes,isEmpty);
    await tester.tap(find.widgetWithText(FilledButton,'페이지 삭제'));await tester.pumpAndSettle();
    expect(gateway.writes.single.$1,'DELETE');
    expect(gateway.writes.single.$2,'admin/knowledge-revisions/${fixture.document}/pages/1?expected_version=3');
    expect(tester.takeException(),isNull);
  });

  testWidgets('registering an extraction pins the selected applied document and version', (tester)async{
    final gateway=Gateway();
    final source=StudentDocumentPublicView(id:fixture.document,version:2,status:'applied',lineageId:fixture.document,revision:1,appliedAt:DateTime(2026,1,1),name:'적용 규정',institutionId:fixture.institution,sourceUrl:'https://example.invalid/rules',documentType:'regulation');
    await launch(tester,SchoolKnowledgeCreateDialog(api:SchoolKnowledgeAdminApi(gateway),documents:[source]));
    await tester.tap(find.byType(AnchoredSelectField<String>));await tester.pumpAndSettle();await tester.tap(find.text('적용 규정 · v2').last);await tester.pumpAndSettle();
    await enter(tester,'knowledge-create-document_hash','a'*64);await enter(tester,'knowledge-create-page_count','2');
    await enter(tester,'knowledge-create-extractor_version','synthetic-v2');await enter(tester,'knowledge-create-source_checked_on','2026-11-07');
    FocusManager.instance.primaryFocus?.unfocus();await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('knowledge-create-save')));await tester.pumpAndSettle();
    expect(gateway.writes.single.$3,{'source_document_id':fixture.document,'expected_source_version':2,'document_hash':'a'*64,'page_count':2,'extractor_version':'synthetic-v2','source_checked_on':'2026-11-07'});
    expect(tester.takeException(),isNull);
  });
  testWidgets('page replacement preserves exact content and scope and never infers a blank page', (tester)async{
    final gateway=Gateway();await launch(tester,SchoolKnowledgePageEditor(api:SchoolKnowledgeAdminApi(gateway),document:SchoolKnowledgeView.fromJson(fixture.header()),page:1));
    await tester.tap(find.byKey(const ValueKey('knowledge-page-save')));await tester.pumpAndSettle();expect(gateway.writes,isEmpty);
    await enter(tester,'knowledge-part-0-content','  원문\n본문  ');await enter(tester,'knowledge-part-0-years','2025, 2026');await enter(tester,'knowledge-part-0-tracks','single_major');
    await enter(tester,'knowledge-part-0-warnings','table_structure_requires_review');
    FocusManager.instance.primaryFocus?.unfocus();await tester.pumpAndSettle();await tester.tap(find.byKey(const ValueKey('knowledge-page-save')));await tester.pumpAndSettle();
    expect(gateway.writes.single.$3,{'expected_version':3,'is_blank':false,'parts':[{'content':'  원문\n본문  ','admission_years':[2025,2026],'tracks':['single_major'],'warnings':['table_structure_requires_review']}]});
    expect(tester.takeException(),isNull);
  });
  testWidgets('an explicit blank page sends no parts and conflict preserves input without repeating writes', (tester)async{
    final gateway=Gateway()..fail=409;await launch(tester,SchoolKnowledgePageEditor(api:SchoolKnowledgeAdminApi(gateway),document:SchoolKnowledgeView.fromJson(fixture.header()),page:1));
    await enter(tester,'knowledge-part-0-content','보존할 본문');
    await tester.ensureVisible(find.byKey(const ValueKey('knowledge-page-blank')));await tester.tap(find.byKey(const ValueKey('knowledge-page-blank')));await tester.pump();
    await tester.tap(find.byKey(const ValueKey('knowledge-page-save')));await tester.pumpAndSettle();
    expect(gateway.writes.single.$3,{'expected_version':3,'is_blank':true,'parts':[]});
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('knowledge-page-save'))).onPressed,isNull);
    expect(gateway.writes,hasLength(1));expect(find.textContaining('자동 재전송하지 않습니다'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
