import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:university_path_frontend/features/auth/local_data_owner.dart';
import 'package:university_path_frontend/features/records/personal_record_form.dart';
import 'package:university_path_frontend/features/records/personal_record_repository.dart';
import 'package:university_path_frontend/shared/drafts/form_draft_persistence.dart';
import 'package:university_path_frontend/shared/drafts/form_draft_picker.dart';
import 'package:university_path_frontend/shared/drafts/form_draft_store.dart';
import 'package:university_path_frontend/shared/widgets/input_dialog.dart';

void main() {
  late FormDraftStore store;
  late PersonalRecordRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalDataOwner.currentUserId = 'draft-user';
    store = FormDraftStore(MemoryFormDraftPersistence());
    FormDraftStore.resetInstanceForTest(store);
    repository = PersonalRecordRepository(PersonalRecordKind.activity);
  });

  tearDown(() {
    LocalDataOwner.currentUserId = null;
    FormDraftStore.resetInstanceForTest();
  });

  testWidgets('temp-save then picker restores fields', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => showPersonalRecordForm(
                    context: context,
                    kind: PersonalRecordKind.activity,
                    repository: repository,
                    addLabel: '활동 직접 기록',
                    draftStore: store,
                  ),
                  child: const Text('열기'),
                ),
                TextButton(
                  onPressed: () async {
                    final entry = await showFormDraftPicker(
                      context: context,
                      collectionKey: formDraftCollectionKey(
                        personalRecordDraftScreenId(
                          PersonalRecordKind.activity,
                        ),
                      ),
                      store: store,
                    );
                    if (entry == null || !context.mounted) return;
                    final values = {
                      for (final item in entry.payload.entries)
                        item.key: '${item.value ?? ''}',
                    };
                    await showPersonalRecordForm(
                      context: context,
                      kind: PersonalRecordKind.activity,
                      repository: repository,
                      addLabel: '활동 직접 기록',
                      draftValues: values,
                      appliedDraftId: entry.id,
                      draftStore: store,
                    );
                  },
                  child: const Text('불러오기'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.byType(InputDialog), findsOneWidget);
    expect(find.text('임시저장'), findsWidgets);

    await tester.enterText(find.byType(TextFormField).first, '봉사 초안');
    await tester.tap(find.byKey(const Key('personal-record-temp-save')));
    await tester.pumpAndSettle();
    expect(find.text('임시저장했습니다.'), findsOneWidget);

    final listed = await store.list(
      formDraftCollectionKey(
        personalRecordDraftScreenId(PersonalRecordKind.activity),
      ),
    );
    expect(listed, hasLength(1));
    expect(listed.first.summary, '봉사 초안');

    await tester.tap(find.text('취소').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('input-discard-delete')), findsOneWidget);
    await tester.tap(find.byKey(const Key('input-discard-delete')));
    await tester.pumpAndSettle();
    expect(find.byType(InputDialog), findsNothing);

    await tester.tap(find.text('불러오기'));
    await tester.pumpAndSettle();
    expect(find.text('임시저장 불러오기'), findsOneWidget);
    expect(find.text('봉사 초안'), findsOneWidget);
    await tester.tap(find.text('봉사 초안'));
    await tester.pumpAndSettle();
    expect(find.byType(InputDialog), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField).first).controller
          ?.text,
      '봉사 초안',
    );
  });

  testWidgets('discard dialog offers cancel temp-save delete', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => confirmInputDiscard(context),
              child: const Text('확인'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('input-discard-cancel')), findsOneWidget);
    expect(find.byKey(const Key('input-discard-temp-save')), findsOneWidget);
    expect(find.byKey(const Key('input-discard-delete')), findsOneWidget);
    await tester.tap(find.byKey(const Key('input-discard-cancel')));
    await tester.pumpAndSettle();
  });
}
