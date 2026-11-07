import 'dart:convert';
import 'package:flutter/material.dart';
import '../../shared/app_style.dart';
import '../../shared/widgets/input_dialog.dart';
import '../../shared/widgets/anchored_select_field.dart';
import '../../shared/widgets/field_label.dart';
import '../api/school_knowledge_api.dart';
import '../api/school_knowledge_models.dart';
import '../api/student_api_models.dart';
import '../auth/auth_api.dart';

class SchoolKnowledgeCreateDialog extends StatefulWidget {
  const SchoolKnowledgeCreateDialog({super.key, required this.api, required this.documents});
  final SchoolKnowledgeAdminApi api;
  final List<StudentDocumentPublicView> documents;
  @override State<SchoolKnowledgeCreateDialog> createState() => _CreateState();
}
class _CreateState extends State<SchoolKnowledgeCreateDialog> {
  final _form = GlobalKey<FormState>();
  final _hash = TextEditingController(), _count = TextEditingController(), _extractor = TextEditingController(), _day = TextEditingController();
  final _changes = ChangeNotifier();
  String _id = ''; String? _error;
  List<String> _fields = [];
  bool _busy = false, _uncertain = false, _denied = false;
  @override void dispose() { for (final c in [_hash,_count,_extractor,_day]) {c.dispose();} _changes.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => InputDialog(title: const Text('학교 추출본 등록'),
    hasContent: () => _id.isNotEmpty || [_hash,_count,_extractor,_day].any((c)=>c.text.isNotEmpty),
    changes: Listenable.merge([_changes,_hash,_count,_extractor,_day]), saving: _busy,
    content: Form(key:_form,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      if (!_denied) ...[
        const Text('적용된 공식 문서와 직접 대조한 추출본 정보를 등록합니다. 이 화면은 PDF를 추출하지 않습니다.'),
        AnchoredSelectField<String>(value:_id,label:'적용 문서',options:[const SelectOption('','문서 선택'),for(final d in widget.documents) SelectOption(d.id,'${d.name} · v${d.version}')],
          onChanged:(id){if(!_busy&&!_uncertain){setState(()=>_id=id);_changes.notifyListeners();}}),
        for (final entry in [(_hash,'document_hash','원본 SHA-256',64),(_count,'page_count','원본 페이지 수',3),(_extractor,'extractor_version','추출 도구·버전',128),(_day,'source_checked_on','원본 확인일 (YYYY-MM-DD)',10)])
          Padding(padding:const EdgeInsets.only(top:12),child:FieldLabel(label:entry.$3,child:TextFormField(
            key:ValueKey('knowledge-create-${entry.$2}'),controller:entry.$1,enabled:!_busy&&!_uncertain,maxLength:entry.$4,
            decoration:InputDecoration(errorText:_fields.any((f)=>f.endsWith(entry.$2))?'입력을 확인하세요.':null),
            validator:(raw){final text=(raw??'').trim();
              if(entry.$2=='document_hash') return RegExp(r'^[0-9a-f]{64}$').hasMatch(text)?null:'소문자 SHA-256 64자를 입력하세요.';
              if(entry.$2=='page_count'){final n=int.tryParse(text);return n!=null&&n>=1&&n<=200?null:'1~200쪽을 입력하세요.';}
              if(entry.$2=='source_checked_on'){final d=DateTime.tryParse(text);return d!=null&&d.toIso8601String().startsWith(text)&&RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)?null:'실제 날짜를 입력하세요.';}
              return text.isEmpty?'필수 입력입니다.':null;
            },
          ))),
      ],
      if(_error!=null) Text(_error!),
      if(_uncertain) const Text('생성 결과를 확인해야 합니다. 다시 등록하지 말고 닫은 뒤 추출본 목록을 확인하세요.'),
    ])),
    actions:[TextButton(onPressed:_busy?null:()=>InputDialog.cancel<bool>(context),child:const Text('취소')),
      FilledButton(key:const ValueKey('knowledge-create-save'),onPressed:_busy||_uncertain||_denied?null:_save,child:const Text('추출본 등록'))],
  );
  Future<void> _save() async {
    if (_busy||_uncertain||_denied||!_form.currentState!.validate()) return;
    final document=widget.documents.where((d)=>d.id==_id).firstOrNull;
    if(document==null){setState(()=>_error='적용 문서를 선택하세요.');return;}
    setState((){_busy=true;_error=null;_fields=[];});
    try {
      final result=await widget.api.create(SchoolKnowledgeCreate(sourceDocumentId:document.id,expectedSourceVersion:document.version,
        documentHash:_hash.text.trim(),pageCount:int.parse(_count.text),extractorVersion:_extractor.text.trim(),sourceCheckedOn:_day.text.trim()));
      if(result.sourceDocumentId!=document.id) throw const FormatException('Source mismatch');
      if(mounted) Navigator.pop(context,true);
    } catch(error){if(mounted)setState((){_error=error is AuthFailure?error.message:'생성 결과를 확인하지 못했습니다.';
      if(error is AuthFailure){_fields=error.fields;_denied={401,403}.contains(error.status);}
      _uncertain=!(error is AuthFailure&&error.status==422);
    });} finally{if(mounted)setState(()=>_busy=false);}
  }
}
class _Part {
  _Part([SchoolKnowledgeChunkView? source]) : content=TextEditingController(text:source?.content??''),
    years=TextEditingController(text:source?.admissionYears?.join(', ')??''),tracks=TextEditingController(text:source?.tracks?.join(', ')??''),
    warnings=TextEditingController(text:source?.warnings.join(', ')??'');
  final TextEditingController content,years,tracks,warnings;
  List<TextEditingController> get controllers=>[content,years,tracks,warnings];
  void dispose(){for(final c in controllers){c.dispose();}}
}
class SchoolKnowledgePageEditor extends StatefulWidget {
  const SchoolKnowledgePageEditor({super.key,required this.api,required this.document,required this.page, this.initial});
  final SchoolKnowledgeAdminApi api;
  final SchoolKnowledgeView document;
  final int page;
  final SchoolKnowledgePageView? initial;
  @override State<SchoolKnowledgePageEditor> createState()=>_PageState();
}
class _PageState extends State<SchoolKnowledgePageEditor> {
  final _form=GlobalKey<FormState>();
  final _changes=ChangeNotifier();
  late final List<_Part> _parts=[if(widget.initial==null||widget.initial!.parts.isEmpty) _Part() else for(final part in widget.initial!.parts) _Part(part)];
  late bool _blank=widget.initial?.isBlank??false;
  bool _busy=false,_stale=false,_denied=false;
  String? _error; List<String> _fields=[];
  late final String _initial;
  String get _fingerprint=>jsonEncode([_blank,for(final part in _parts) [for(final c in part.controllers)c.text]]);
  @override void initState(){super.initState();_initial=_fingerprint;}
  @override void dispose(){for(final p in _parts){p.dispose();}_changes.dispose();super.dispose();}
  List<String>? _scope(String value, int max, int width) {
    if(value.trim().isEmpty)return null;
    final values=value.split(',').map((s)=>s.trim()).toList();
    if(values.length>max||values.toSet().length!=values.length||values.any((s)=>s.isEmpty||s.length>width))throw const FormatException('범위·경고의 개수와 중복을 확인하세요.');
    return values;
  }
  Future<void> _save() async {
    if(_busy||_stale||_denied||!_form.currentState!.validate())return;
    try {
      final parts=<SchoolKnowledgeChunkPart>[];
      if(!_blank) for(final p in _parts){
        final years=_scope(p.years.text,200,4)?.map((v){final y=int.tryParse(v);if(y==null||y<1000||y>9999)throw const FormatException('입학연도는 네 자리 숫자로 입력하세요.');return y;}).toList();
        parts.add(SchoolKnowledgeChunkPart(content:p.content.text,admissionYears:years,tracks:_scope(p.tracks.text,32,64),warnings:_scope(p.warnings.text,32,128)??[]));
      }
      if(parts.fold<int>(0,(sum,p)=>sum+p.content.runes.length)>20000)throw const FormatException('한 페이지 본문은 합계 20,000자 이내입니다.');
      setState((){_busy=true;_error=null;_fields=[];});
      final saved=await widget.api.replacePage(widget.document.id,widget.page,SchoolKnowledgePageReplace(expectedVersion:widget.document.version,isBlank:_blank,parts:parts));
      if(saved.knowledgeDocumentId!=widget.document.id||saved.page!=widget.page)throw const FormatException('Page mismatch');
      if(mounted)Navigator.pop(context,true);
    } catch(error){if(mounted)setState((){_error=error is AuthFailure?error.message:error is FormatException?error.message:'저장 결과를 확인하지 못했습니다.';
      if(error is AuthFailure){_fields=error.fields;_denied={401,403,404}.contains(error.status);}
      _stale=_busy && !(error is AuthFailure&&error.status==422);
    });}finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _delete()async{
    final yes=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:const Text('이 초안 페이지를 삭제할까요?'),actions:[
      TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('취소')),
      FilledButton(style:destructiveButtonStyle(context),onPressed:()=>Navigator.pop(context,true),child:const Text('페이지 삭제'))]));
    if(yes!=true||!mounted||_busy||_stale)return;
    setState(()=>_busy=true);
    try{await widget.api.removePage(widget.document.id,widget.page,expectedVersion:widget.document.version);if(mounted)Navigator.pop(context,true);}
    catch(error){if(mounted)setState((){_error=error is AuthFailure?error.message:'삭제 결과를 확인하지 못했습니다. 다시 읽어 확인하세요.';_stale=true;_denied=error is AuthFailure&&{401,403,404}.contains(error.status);});}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  @override Widget build(BuildContext context)=>InputDialog(title:Text('${widget.page}쪽 본문·범위 편집'),hasContent:()=>_blank||_parts.any((p)=>p.controllers.any((c)=>c.text.isNotEmpty)),hasUnsavedChanges:()=>_fingerprint!=_initial,editing:widget.initial!=null,
    changes:Listenable.merge([_changes,for(final part in _parts)...part.controllers]),saving:_busy,
    content:Form(key:_form,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      if(!_denied)...[
        CheckboxListTile(key:const ValueKey('knowledge-page-blank'),value:_blank,onChanged:_busy||_stale?null:(v){setState(()=>_blank=v==true);_changes.notifyListeners();},title:const Text('원본에서 직접 확인한 빈 페이지')),
        if(!_blank)...[
          for(var i=0;i<_parts.length;i++) Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
            Text('본문 분할 ${i+1}'),
            for(final e in [(_parts[i].content,'content','원문 본문',true),(_parts[i].years,'years','입학연도 (쉼표 구분, 미확인 시 비움)',false),(_parts[i].tracks,'tracks','이수 경로 (쉼표 구분, 미확인 시 비움)',false),(_parts[i].warnings,'warnings','해결하지 못한 경고 (쉼표 구분)',false)])
              Padding(padding:const EdgeInsets.only(top:8),child:FieldLabel(label:e.$3,child:TextFormField(key:ValueKey('knowledge-part-$i-${e.$2}'),controller:e.$1,
                enabled:!_busy&&!_stale,minLines:e.$4?4:1,maxLines:e.$4?10:2,maxLength:e.$4?20000:null,
                decoration:InputDecoration(errorText:_fields.any((f)=>f.startsWith('parts.$i'))?'이 분할의 본문·범위를 확인하세요.':null),
                validator:(raw)=>e.$4&&((raw??'').trim().isEmpty||(raw??'').contains('\u0000'))?'읽을 수 있는 원문을 입력하세요.':null,
              ))),
            if(_parts.length>1) TextButton(onPressed:_busy||_stale?null:(){final p=_parts.removeAt(i);setState((){});WidgetsBinding.instance.addPostFrameCallback((_){p.dispose();});_changes.notifyListeners();},child:const Text('분할 제거')),
          ]))),
          OutlinedButton(onPressed:_busy||_stale||_parts.length>=20?null:(){setState(()=>_parts.add(_Part()));_changes.notifyListeners();},child:const Text('본문 분할 추가')),
        ],
      ],
      if(_error!=null)Text(_error!),
      if(_stale)const Text('최신 추출본을 다시 읽고 편집하세요. 자동 재전송하지 않습니다.'),
    ])),
    actions:[TextButton(onPressed:_busy?null:()=>InputDialog.cancel<bool>(context),child:const Text('취소')),
      if(widget.initial!=null&&!_denied)TextButton(onPressed:_busy||_stale?null:_delete,child:const Text('이 페이지 삭제')),
      FilledButton(key:const ValueKey('knowledge-page-save'),onPressed:_busy||_stale||_denied?null:_save,child:const Text('페이지 저장'))],
  );
}
