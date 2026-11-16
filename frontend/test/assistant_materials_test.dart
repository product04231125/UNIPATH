import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/api/student_api.dart';
import 'package:university_path_frontend/features/assistant/ai_record_catalog.dart';
import 'package:university_path_frontend/features/assistant/assistant_conversation.dart';
import 'package:university_path_frontend/features/assistant/assistant_panel.dart';
import 'package:university_path_frontend/features/assistant/conversation_bridge.dart';
import 'package:university_path_frontend/features/auth/auth_api.dart';
import 'package:university_path_frontend/features/records/portfolio/material_repository.dart';
import 'package:university_path_frontend/features/records/portfolio/materials_page.dart';

import 'materials_test.dart' show MemoryMaterials;

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

  test('personalized catalog excludes course requests', () async {
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
    'registration edit and deletion update chat without enabling upload',
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
      expect(tester.widget<CheckboxListTile>(row).onChanged, isNull);
      expect(c.selectedRecords, isEmpty);
      expect(find.text('다른 계정 자료'), findsNothing);
      expect(find.text('자료 질문 API가 없어 등록 자료로 질문할 수 없습니다.'), findsOneWidget);

      await tester.ensureVisible(find.widgetWithText(OutlinedButton, '수정'));
      await tester.tap(find.widgetWithText(OutlinedButton, '수정'));
      await tester.pumpAndSettle();
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
      await tester.ensureVisible(find.widgetWithText(FilledButton, '삭제'));
      await tester.tap(find.widgetWithText(FilledButton, '삭제'));
      await tester.pumpAndSettle();
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
