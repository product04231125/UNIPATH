import '../../api/student_api.dart';
import '../../api/student_api_models.dart';
import '../../auth/local_data_owner.dart';
import '../personal_record_codec.dart';
import '../personal_record_repository.dart';
import '../remote_personal_record_repository.dart';
import 'portfolio_workspace_repository.dart';

class RemotePortfolioWorkspaceRepository extends PortfolioWorkspaceRepository {
  RemotePortfolioWorkspaceRepository(this.api, {required this.ensureOpen})
    : super(owner: LocalDataOwner(api.ownerId));
  final StudentApi api;
  final void Function() ensureOpen;
  bool _ready = false;
  List<PortfolioComposition> _compositions = [];
  List<ApplicationDocument> _documents = [];
  Map<String, PortfolioSource> _sources = {};
  Future<void> _pending = Future.value();
  @override
  bool get isServerBacked => true;
  @override
  List<PortfolioComposition> get compositions =>
      List.unmodifiable(_compositions);
  @override
  List<ApplicationDocument> get documents => List.unmodifiable(_documents);
  @override
  Map<String, PortfolioSource> get sources => Map.unmodifiable(_sources);
  Future<void> _enqueue(Future<void> Function() action) {
    final result = _pending.then((_) {
      ensureOpen();
      return action();
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<List<StudentRecord<T>>> _all<T extends StudentPayload>(
    StudentResource<T> resource,
  ) async {
    final result = <StudentRecord<T>>[];
    final seen = <String>{};
    final ids = <String>{};
    String? cursor;
    do {
      final page = await api.list(resource, cursor: cursor);
      for (final row in page.items) {
        if (!ids.add(row.id)) {
          throw const FormatException('Repeated portfolio record');
        }
        result.add(row);
      }
      cursor = page.nextCursor;
      if (cursor != null && !seen.add(cursor)) {
        throw const FormatException('Repeated cursor');
      }
    } while (cursor != null);
    ensureOpen();
    return result;
  }

  PortfolioComposition _composition(
    StudentRecord<StudentPortfolioCompositionCreate> row,
  ) => PortfolioComposition(
    id: row.id,
    version: row.version,
    title: row.data.title,
    description: row.data.detail,
    audience: switch (row.data.audience) {
      'private' => PortfolioAudience.private,
      'application' => PortfolioAudience.application,
      'public_review' => PortfolioAudience.publicReview,
      _ => throw const FormatException('Unknown audience'),
    },
    reviewed: row.data.reviewed,
    sources: row.data.sources
        .map((r) => PersonalRecordCodec.referenceValue(r.toJson()))
        .toList(),
  );
  ApplicationDocument _document(
    StudentRecord<StudentApplicationDocumentCreate> row,
  ) => ApplicationDocument(
    id: row.id,
    version: row.version,
    title: row.data.title,
    target: row.data.target,
    role: row.data.role,
    type: row.data.documentType,
    body: row.data.body,
    sources: row.data.sources
        .map((r) => PersonalRecordCodec.referenceValue(r.toJson()))
        .toList(),
  );
  Future<void> _reloadSources() async {
    final values = <String, PortfolioSource>{};
    for (final kind in [
      PersonalRecordKind.portfolio,
      PersonalRecordKind.experience,
    ]) {
      final repository = RemotePersonalRecordRepository(
        api,
        kind,
        ensureOpen: ensureOpen,
      );
      await repository.load();
      for (final record in repository.records) {
        final source = PortfolioSource(kind, record);
        values[source.ref] = source;
      }
    }
    ensureOpen();
    _sources = values;
  }

  @override
  Future<void> reloadSources() => _enqueue(_reloadSources);
  @override
  Future<void> load() => _enqueue(() async {
    _ready = false;
    final compositions = await _all(StudentResources.compositions);
    final documents = await _all(StudentResources.applicationDocuments);
    await _reloadSources();
    _compositions = compositions.map(_composition).toList();
    _documents = documents.map(_document).toList();
    _ready = true;
  });
  List<StudentRecordReference> _references(List<String> refs) => refs
      .map(
        (ref) => StudentRecordReference.fromJson(
          Map<String, dynamic>.from(PersonalRecordCodec.reference(ref)),
        ),
      )
      .toList();
  Future<StudentRecord<T>> _save<T extends StudentPayload>(
    StudentResource<T> resource,
    T payload,
    String id,
    int? version, {
    Set<String> omitted = const {},
  }) async {
    if (!_ready) throw StateError('Read portfolio before saving');
    final result = version == null
        ? await api.create(resource, payload)
        : await api.patch(
            resource,
            id,
            expectedVersion: version,
            changes: payload.toJson()
              ..remove('client_id')
              ..removeWhere((k, v) => omitted.contains(k)),
          );
    ensureOpen();
    return result;
  }

  @override
  Future<void> saveComposition(PortfolioComposition composition) => _enqueue(
    () async {
      final payload = StudentPortfolioCompositionCreate(
        clientId: composition.version == null ? composition.id : null,
        title: composition.title,
        detail: composition.description,
        audience: switch (composition.audience) {
          PortfolioAudience.private => 'private',
          PortfolioAudience.application => 'application',
          PortfolioAudience.publicReview => 'public_review',
        },
        reviewed: composition.reviewed,
        sources: _references(composition.sources),
      );
      final saved = _composition(
        await _save(
          StudentResources.compositions,
          payload,
          composition.id,
          composition.version,
        ),
      );
      _compositions = [..._compositions.where((c) => c.id != saved.id), saved];
    },
  );
  @override
  Future<void> saveDocument(ApplicationDocument document) => _enqueue(() async {
    final payload = StudentApplicationDocumentCreate(
      clientId: document.version == null ? document.id : null,
      title: document.title,
      target: document.target,
      role: document.role,
      documentType: document.type,
      body: document.body,
      sources: _references(document.sources),
    );
    final saved = _document(
      await _save(
        StudentResources.applicationDocuments,
        payload,
        document.id,
        document.version,
        omitted: {'detail'},
      ),
    );
    _documents = [..._documents.where((d) => d.id != saved.id), saved];
  });
  @override
  Future<void> deleteComposition(String id, {int? expectedVersion}) =>
      _enqueue(() async {
        if (!_ready || expectedVersion == null) {
          throw StateError('Capture composition version');
        }
        await api.remove(
          StudentResources.compositions,
          id,
          expectedVersion: expectedVersion,
        );
        ensureOpen();
        _compositions = _compositions.where((c) => c.id != id).toList();
      });
  @override
  Future<void> deleteDocument(String id, {int? expectedVersion}) =>
      _enqueue(() async {
        if (!_ready || expectedVersion == null) {
          throw StateError('Capture document version');
        }
        await api.remove(
          StudentResources.applicationDocuments,
          id,
          expectedVersion: expectedVersion,
        );
        ensureOpen();
        _documents = _documents.where((d) => d.id != id).toList();
      });
  @override
  String compositionText(PortfolioComposition composition) => [
    composition.title,
    '계정 서버 구성 · ${audienceLabel(composition.audience)} · 게시되지 않음',
    if (composition.description.isNotEmpty) composition.description,
    for (final ref in composition.sources)
      sources[ref]?.text ?? '원본 기록 없음 · 연결 확인 필요',
  ].join('\n\n');
}
