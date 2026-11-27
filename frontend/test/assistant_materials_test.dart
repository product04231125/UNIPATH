import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/api/guidance_api.dart';
import 'package:university_path_frontend/features/assistant/assistant_api.dart';
import 'package:university_path_frontend/features/assistant/ai_record_catalog.dart';
import 'package:university_path_frontend/features/assistant/assistant_conversation.dart';
import 'package:university_path_frontend/features/assistant/assistant_panel.dart';
import 'package:university_path_frontend/features/assistant/conversation_bridge.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/records/portfolio/material_repository.dart';
import 'package:university_path_frontend/features/records/portfolio/materials_page.dart';

import 'materials_test.dart' show MemoryMaterials;
import 'guidance_api_test.dart' show CapturingGateway;

import 'package:university_path_frontend/features/settings/ai_consent_preferences.dart';

import 'support/record_actions.dart';

class RecordsGateway extends ApiGateway {
  final paths = <String>[];
  @override
  Future<Map<String, dynamic>?> request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    paths.add(path);
    return {'items': [], 'next_cursor': null};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'material selection loads only chosen content and rejects deleted material',
    () async {
      final repository = MemoryMaterials();
      await repository.save(
        PersonalMaterial(
          id: 'selected',
          title: '내 증빙',
          type: MaterialKinds.other,
          description: '봉사 12시간',
        ),
      );
      await repository.save(
        PersonalMaterial(
          id: 'other',
          title: '선택 안 함',
          type: MaterialKinds.other,
          description: '보내지 않을 내용',
        ),
      );
      final documents = await loadGuidanceDocuments(repository, ['selected']);
      expect(documents.single.filename, '내 증빙.txt');
      expect(
        utf8.decode(base64Decode(documents.single.contentBase64)),
        '봉사 12시간',
      );
      await repository.deleteId('selected');
      await expectLater(
        loadGuidanceDocuments(repository, ['selected']),
        throwsStateError,
      );
    },
  );

  test('material only question requires consent before reading bytes and preserves selection on failure', () async {
    var reads = 0;
    final consent = AiConsentPreferences(
      ownerId: 'owner',
      reader: (_) async => null,
      writer: (_, _) async => true,
    );
    await consent.load();
    addTearDown(consent.dispose);
    final c =
        AssistantConversation(
          registeredOnly: true,
          guidanceApi: GuidanceApi(RecordsGateway()),
          consent: consent,
          loadMaterials: () async => [
            const AssistantMaterial(id: 'local', title: '증빙', type: '기타'),
          ],
          loadDocuments: (ids) async {
            reads++;
            throw StateError('OCR 처리 실패');
          },
        )..setContext(
          const SchoolQueryContext(
            institutionId: 'school',
            departmentId: 'department',
          ),
        );
    c.setMode(AssistantMode.personalized);
    await c.refreshMaterials();
    c.selectMaterial('local', true);
    c.input.text = '이 자료로 봉사 신청 안내';
    await c.send();
    expect(reads, 0);
    expect(c.submissionError, contains('동의'));
    await c.permit(AssistantMode.personalized, remember: false);
    await c.send();
    expect(reads, 1);
    expect(c.turns.single.error!.message, 'OCR 처리 실패');
    expect(c.input.text, '이 자료로 봉사 신청 안내');
    expect(c.selectedMaterialIds, contains('local'));
    c.dispose();
  });

  test('selected material bytes reach personalized endpoint only after explicit consent', () async {
    final gateway = CapturingGateway()
      ..response = {
        'query_id': 'query',
        'status': 'evidence_only',
        'reason': 'generator_not_configured',
        'official': false,
        'school': {
          'query_id': 'school',
          'status': 'insufficient_evidence',
          'reason': 'no_approved_matching_evidence',
        },
        'personal': {'records': [], 'official': false},
      };
    final consent = AiConsentPreferences(
      ownerId: 'owner',
      reader: (_) async => null,
      writer: (_, _) async => true,
    );
    await consent.load();
    await consent.setAllowed(AiConsentFeature.personalizedQuestion, true);
    addTearDown(consent.dispose);
    final repository = MemoryMaterials();
    await repository.save(
      PersonalMaterial(
        id: 'selected',
        title: '봉사증빙',
        type: MaterialKinds.other,
        description: '봉사 12시간',
      ),
    );
    final c =
        AssistantConversation(
          registeredOnly: true,
          guidanceApi: GuidanceApi(gateway),
          consent: consent,
          loadMaterials: () => loadAssistantMaterials(repository),
          loadDocuments: (ids) => loadGuidanceDocuments(repository, ids),
        )..setContext(
          const SchoolQueryContext(
            institutionId: 'school',
            departmentId: 'department',
          ),
        );
    c.setMode(AssistantMode.personalized);
    await c.refreshMaterials();
    c.selectMaterial('selected', true);
    c.input.text = '이 자료로 학사 안내';
    await c.send();
    expect(
      gateway.calls,
      isEmpty,
      reason: 'remembered record consent does not silently upload a document',
    );
    await c.permit(AssistantMode.personalized, remember: false);
    await c.send();
    expect(gateway.calls.single.$2, 'me/personalized-guidance');
    final body = gateway.calls.single.$3!;
    expect(body['records'], isEmpty);
    final document = (body['documents'] as List).single as Map;
    expect(document['filename'], '봉사증빙.txt');
    expect(
      utf8.decode(base64Decode(document['content_base64'] as String)),
      '봉사 12시간',
    );
    expect(c.turns.single.personalized!.status, 'evidence_only');
    c.dispose();
  });

  test('personalized catalog includes course requests by default', () async {
    final gateway = RecordsGateway();
    await loadAiRecords(StudentApi(gateway, ownerId: 'owner'));
    expect(gateway.paths.map((path) => Uri.parse(path).path), [
      'me/course-records',
      'me/activity-records',
      'me/experience-records',
      'me/credential-records',
      'me/achievement-records',
    ]);
  });

  test('career catalog can explicitly exclude course requests', () async {
    final gateway = RecordsGateway();
    expect(
      await loadAiRecords(
        StudentApi(gateway, ownerId: 'owner'),
        includeCourses: false,
      ),
      isEmpty,
    );
    expect(gateway.paths.map((path) => Uri.parse(path).path), [
      'me/activity-records',
      'me/experience-records',
      'me/credential-records',
      'me/achievement-records',
    ]);
  });

  testWidgets(
    'registration edit and deletion update selectable chat materials',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = MemoryMaterials();
      final c = AssistantConversation(
        registeredOnly: true,
        loadMaterials: () => loadAssistantMaterials(repository),
      )..setMode(AssistantMode.personalized);
      await c.refreshMaterials();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: MaterialsPage(
                    repository: repository,
                    onChanged: () => unawaited(c.refreshMaterials()),
                  ),
                ),
                AssistantPanel(conversation: c, onClose: () {}, width: 480),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('이 기기에 등록한 자료가 없습니다. 자료 메뉴에서 등록해 주세요.'), findsOneWidget);
      await tester.tap(find.byTooltip('자료 추가'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('material-title')),
        '질문용 이력서',
      );
      await tester.tap(find.byKey(const ValueKey('material-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(MaterialKinds.resume).last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('material-description')),
        '등록 설명',
      );
      await tester.ensureVisible(find.widgetWithText(FilledButton, '자료 등록'));
      await tester.tap(find.widgetWithText(FilledButton, '자료 등록'));
      await tester.pumpAndSettle();
      final id = (await repository.load()).single.id;
      final row = find.byKey(ValueKey('assistant-material-$id'));
      expect(row, findsOneWidget);
      expect(tester.widget<CheckboxListTile>(row).onChanged, isNotNull);
      c.selectMaterial(id, true);
      expect(c.selectedMaterialIds, contains(id));
      expect(c.selectedRecords, isEmpty);
      expect(find.text('다른 계정 자료'), findsNothing);
      expect(
        find.text(
          '선택한 자료의 설명·PDF를 서버에서 읽고, 추출한 내용을 Google 외부 AI로 전송합니다. 스캔 PDF는 OCR 처리하며 원본 대조가 필요합니다.',
        ),
        findsOneWidget,
      );

      await tapRecordAction(tester, '수정');
      await tester.enterText(
        find.byKey(const ValueKey('material-title')),
        '수정된 이력서',
      );
      await tester.ensureVisible(find.widgetWithText(FilledButton, '저장'));
      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();
      expect(c.materials.single.title, '수정된 이력서');
      expect(
        find.descendant(of: row, matching: find.text('수정된 이력서')),
        findsOneWidget,
      );
      await tapRecordAction(tester, '삭제');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, '삭제'),
        ),
      );
      await tester.pumpAndSettle();
      expect(c.materials, isEmpty);
      expect(row, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );

  test(
    'local reads survive server failure and retry after local failure',
    () async {
      var fail = true;
      final c = AssistantConversation(
        loadRecords: () async => throw StateError('server unavailable'),
        loadMaterials: () async {
          if (fail) throw StateError('storage unavailable');
          return [
            const AssistantMaterial(id: 'local', title: '내 자료', type: '이력서'),
          ];
        },
      );
      await c.refreshRecords();
      await Future<void>.delayed(Duration.zero);
      expect(c.materialsError, isNotNull);
      fail = false;
      await c.refreshMaterials();
      expect(c.materials.single.title, '내 자료');
      expect(c.materialsError, isNull);
      expect(c.recordsError, isNotNull);
      c.dispose();
    },
  );

  test('detached chat refreshes material metadata through the owner', () async {
    var title = '첫 자료';
    final owner = AssistantConversation(
      loadMaterials: () async => [
        AssistantMaterial(id: 'local', title: title, type: '이력서'),
      ],
    );
    final updates = StreamController<Map<String, dynamic>>.broadcast(
      sync: true,
    );
    final bridge = ConversationBridge(
      owner,
      (state) async => updates.add(state),
    );
    final child = RemoteConversation(
      request: (command) async =>
          command == null ? bridge.read() : bridge.command(command),
      changes: updates.stream,
    );
    await child.load();
    await child.refreshMaterials();
    await Future<void>.delayed(Duration.zero);
    expect(child.materials.single.title, '첫 자료');
    child.selectMaterial('local', true);
    await child.flush();
    await Future<void>.delayed(Duration.zero);
    expect(owner.selectedMaterialIds, contains('local'));
    expect(child.selectedMaterialIds, contains('local'));
    title = '수정 자료';
    await owner.refreshMaterials();
    await Future<void>.delayed(Duration.zero);
    expect(child.materials.single.title, '수정 자료');
    final snapshot = jsonEncode(conversationSnapshot(owner, 1)['materials']);
    expect(snapshot, isNot(contains('pdf')));
    expect(snapshot, isNot(contains('description')));
    child.dispose();
    bridge.dispose();
    owner.dispose();
    await updates.close();
  });
}
