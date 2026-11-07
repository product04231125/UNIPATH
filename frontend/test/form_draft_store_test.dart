import 'package:flutter_test/flutter_test.dart';
import 'package:university_path_frontend/features/auth/local_data_owner.dart';
import 'package:university_path_frontend/shared/drafts/form_draft_persistence.dart';
import 'package:university_path_frontend/shared/drafts/form_draft_store.dart';

void main() {
  late FormDraftStore store;
  late MemoryFormDraftPersistence persistence;

  setUp(() {
    LocalDataOwner.currentUserId = 'user-a';
    persistence = MemoryFormDraftPersistence();
    store = FormDraftStore(persistence);
    FormDraftStore.resetInstanceForTest(store);
  });

  tearDown(() {
    LocalDataOwner.currentUserId = null;
    FormDraftStore.resetInstanceForTest();
  });

  test('add list get delete and owner clear', () async {
    final key = formDraftCollectionKey('activity');
    final first = await store.add(
      key,
      summary: '봉사 A',
      payload: {'title': '봉사 A', 'hours': '10'},
    );
    await store.add(
      key,
      summary: '봉사 B',
      payload: {'title': '봉사 B'},
    );
    final listed = await store.list(key);
    expect(listed, hasLength(2));
    expect(listed.first.summary, '봉사 B');
    expect((await store.get(key, first.id))?.summary, '봉사 A');
    await store.delete(key, first.id);
    expect(await store.list(key), hasLength(1));

    LocalDataOwner.currentUserId = 'user-b';
    final otherKey = formDraftCollectionKey('activity');
    await store.add(otherKey, summary: '다른 계정', payload: {'title': 'x'});
    await store.clearForOwner('user-a');
    LocalDataOwner.currentUserId = 'user-a';
    expect(await store.list(formDraftCollectionKey('activity')), isEmpty);
    LocalDataOwner.currentUserId = 'user-b';
    expect(await store.list(formDraftCollectionKey('activity')), hasLength(1));
  });

  test('caps at ten by dropping oldest', () async {
    final key = formDraftCollectionKey('course');
    for (var i = 0; i < 12; i++) {
      await store.add(key, summary: 's$i', payload: {'n': '$i'});
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    final listed = await store.list(key);
    expect(listed, hasLength(formDraftMaxPerCollection));
    expect(listed.map((e) => e.summary), isNot(contains('s0')));
    expect(listed.map((e) => e.summary), isNot(contains('s1')));
    expect(listed.last.summary, 's2');
  });

  test('menus stay isolated', () async {
    await store.add(
      formDraftCollectionKey('activity'),
      summary: '활동',
      payload: {'title': '활동'},
    );
    expect(await store.list(formDraftCollectionKey('schedule')), isEmpty);
    expect(await store.list(formDraftCollectionKey('activity')), hasLength(1));
  });
}
