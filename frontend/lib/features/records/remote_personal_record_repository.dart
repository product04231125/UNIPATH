import '../api/student_api.dart';
import '../auth/local_data_owner.dart';
import 'personal_record_codec.dart';
import 'personal_record_repository.dart';

class RemotePersonalRecordRepository extends PersonalRecordRepository {
  RemotePersonalRecordRepository(
    this.api,
    PersonalRecordKind kind, {
    required this.ensureOpen,
  }) : codec = PersonalRecordCodec(kind),
       super(kind, owner: LocalDataOwner(api.ownerId));
  final StudentApi api;
  final void Function() ensureOpen;
  final PersonalRecordCodec codec;
  bool _ready = false;
  List<PersonalRecord> _items = [];
  Future<void> _pending = Future.value();
  @override
  bool get isServerBacked => true;
  @override
  List<PersonalRecord> get records => List.unmodifiable(_items);
  Future<void> _enqueue(Future<void> Function() action) {
    final result = _pending.then((_) {
      ensureOpen();
      return action();
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<void> load() => _enqueue(() async {
    _ready = false;
    final result = <PersonalRecord>[];
    final cursors = <String>{};
    final ids = <String>{};
    String? cursor;
    do {
      final page = await api.list(codec.resource, cursor: cursor);
      for (final item in page.items) {
        if (!ids.add(item.id)) {
          throw const FormatException('Repeated personal record');
        }
        result.add(codec.decode(item));
      }
      cursor = page.nextCursor;
      if (cursor != null && !cursors.add(cursor)) {
        throw const FormatException('Repeated cursor');
      }
    } while (cursor != null);
    ensureOpen();
    _items = result;
    _ready = true;
  });
  @override
  Future<void> save(PersonalRecord record) => _enqueue(() async {
    if (!_ready) throw StateError('Read records before saving');
    final payload = codec.encode(
      record.values,
      clientId: record.version == null ? record.id : null,
    );
    final saved = record.version == null
        ? await api.create(codec.resource, payload)
        : await api.patch(
            codec.resource,
            record.id,
            expectedVersion: record.version!,
            changes: payload.toJson()..remove('client_id'),
          );
    ensureOpen();
    _items = [..._items.where((v) => v.id != saved.id), codec.decode(saved)];
  });
  @override
  Future<void> delete(String id, {int? expectedVersion}) => _enqueue(() async {
    if (!_ready || expectedVersion == null) {
      throw StateError('Read and capture record version before deleting');
    }
    await api.remove(codec.resource, id, expectedVersion: expectedVersion);
    ensureOpen();
    _items = _items.where((v) => v.id != id).toList();
  });
}
